#import "PlayerViewController.h"
#import "CBLog.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static void *kKVO = &kKVO;

static NSString *CBFormatTime(double t) {
    if (!isfinite(t) || t < 0) return @"--:--";
    long s = (long)t;
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%02ld:%02ld", s / 60, s % 60];
}

@interface CBPlayerView : UIView
@end

@implementation CBPlayerView
+ (Class)layerClass {
    return [AVPlayerLayer class];
}
@end

@interface PlayerViewController () <UIGestureRecognizerDelegate>
@end

@implementation PlayerViewController {
    NSURL *_url;
    NSString *_title;
    AVPlayer *_player;
    AVPlayerItem *_item;
    id _timeObserver;
    BOOL _observing;
    BOOL _torndown;
    UILabel *_info;
    UIView *_bar;
    NSDate *_openedAt;
    NSTimeInterval _startupSecs;  // giây từ lúc mở tới khi thời gian phát bắt đầu chạy
    NSInteger _stalls;
    NSInteger _ticks;
    double _peakMB;
    AVPlayerItemVideoOutput *_videoOut;  // chỉ để đọc kích thước khung hình đã giải mã (presentationSize báo 853x480 với nguồn 1080p)
    BOOL _decodedSizeLogged;
}

- (instancetype)initWithURL:(NSURL *)url title:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _url = url;
        _title = [title copy];
        _startupSecs = -1;
    }
    return self;
}

- (void)loadView {
    CBPlayerView *view = [[CBPlayerView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.backgroundColor = [UIColor blackColor];
    self.view = view;
}

- (AVPlayerLayer *)playerLayer {
    return (AVPlayerLayer *)self.view.layer;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _info = [[UILabel alloc] init];
    _info.numberOfLines = 0;
    _info.font = [UIFont fontWithName:@"Courier-Bold" size:12] ?: [UIFont systemFontOfSize:12];
    _info.textColor = [UIColor whiteColor];
    _info.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [self.view addSubview:_info];

    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [self.view addSubview:_bar];
    NSArray *buttons = @[@[@"Đóng", @"close"], @[@"−10s", @"back10"], @[@"Dừng/Phát", @"toggle"], @[@"+60s", @"fwd60"],
                         @[@"Tới 50%", @"half"]];
    for (NSArray *b in buttons) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:b[0] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [btn addTarget:self action:NSSelectorFromString(b[1]) forControlEvents:UIControlEventTouchUpInside];
        [_bar addSubview:btn];
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOverlay)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    _openedAt = [NSDate date];
    CBLog(@"Mở trình phát: %@", _url);
    _item = [AVPlayerItem playerItemWithURL:_url];
    _player = [AVPlayer playerWithPlayerItem:_item];
    [self playerLayer].player = _player;
    [self playerLayer].videoGravity = AVLayerVideoGravityResizeAspect;

    _videoOut = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:nil];
    [_item addOutput:_videoOut];

    for (NSString *key in @[@"status", @"playbackLikelyToKeepUp", @"presentationSize"]) {
        [_item addObserver:self forKeyPath:key options:0 context:kKVO];
    }
    [_player addObserver:self forKeyPath:@"rate" options:0 context:kKVO];
    _observing = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(failedToEnd:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    [nc addObserver:self selector:@selector(stalled:) name:AVPlayerItemPlaybackStalledNotification object:_item];
    [nc addObserver:self selector:@selector(errorLogEntry:) name:AVPlayerItemNewErrorLogEntryNotification object:_item];
    [nc addObserver:self selector:@selector(playedToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];

    __weak PlayerViewController *weakSelf = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2)
                                                          queue:dispatch_get_main_queue()
                                                     usingBlock:^(CMTime time) { [weakSelf tick]; }];
    [_player play];
    [self tick];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Đang xem thì không cho máy tự khoá (lần thử đầu: máy tự khoá sau 1 phút → AVPlayer dừng)
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    if (self.autoCloseAfter <= 0) return;
    NSTimeInterval total = self.autoCloseAfter;
    self.autoCloseAfter = 0;
    CBLog(@"Tự chạy: phát %.0f s, tua tới giữa phim ở giây %.0f", total, total * 0.4);
    __weak PlayerViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(total * 0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf half];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(total * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PlayerViewController *strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_torndown) [strongSelf close];
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat barH = 48;
    _bar.frame = CGRectMake(0, b.size.height - barH, b.size.width, barH);
    NSArray *btns = _bar.subviews;
    CGFloat w = b.size.width / MAX(btns.count, 1u);
    for (NSUInteger i = 0; i < btns.count; i++) [btns[i] setFrame:CGRectMake(i * w, 0, w, barH)];
    CGSize fit = [_info sizeThatFits:CGSizeMake(b.size.width - 16, CGFLOAT_MAX)];
    _info.frame = CGRectMake(8, 8, MIN(b.size.width - 16, fit.width + 8), fit.height);
}

#pragma mark - Xoay

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) return UIInterfaceOrientationLandscapeRight;
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    return o == UIInterfaceOrientationPortraitUpsideDown ? UIInterfaceOrientationPortrait : o;
}

#pragma mark - Trạng thái

- (void)tick {
    if (_torndown) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    CMTime d = _item.duration;
    double dur = CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : NAN;
    double ahead = 0;
    for (NSValue *v in _item.loadedTimeRanges) {
        CMTimeRange r = [v CMTimeRangeValue];
        double s = CMTimeGetSeconds(r.start), e = s + CMTimeGetSeconds(r.duration);
        if (now >= s - 0.5 && now <= e) ahead = MAX(ahead, e - now);
    }
    AVPlayerItemAccessLogEvent *ev = _item.accessLog.events.lastObject;
    double mb = CBResidentMB();
    _peakMB = MAX(_peakMB, mb);
    if (_startupSecs < 0 && now > 0.05 && _player.rate > 0) {
        _startupSecs = -[_openedAt timeIntervalSinceNow];
        CBLog(@"Bắt đầu chạy sau %.1f s", _startupSecs);
    }
    if (!_decodedSizeLogged && now > 3) {
        CMTime t = [_videoOut itemTimeForHostTime:CACurrentMediaTime()];
        CVPixelBufferRef pb = [_videoOut copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
        if (pb) {
            _decodedSizeLogged = YES;
            OSType fmt = CVPixelBufferGetPixelFormatType(pb);
            CBLog(@"Khung hình đã giải mã: %zux%zu, định dạng '%c%c%c%c' (presentationSize %.0fx%.0f, lớp hình %.0fx%.0f pt)",
                  CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), (char)(fmt >> 24), (char)(fmt >> 16), (char)(fmt >> 8),
                  (char)fmt, _item.presentationSize.width, _item.presentationSize.height, self.view.bounds.size.width,
                  self.view.bounds.size.height);
            CVBufferRelease(pb);
        }
    }
    CGSize ps = _item.presentationSize;
    NSString *state = _item.status == AVPlayerItemStatusFailed ? @"LỖI"
                    : _item.status != AVPlayerItemStatusReadyToPlay ? @"đang mở"
                    : _player.rate > 0 ? @"đang phát" : @"dừng";
    NSString *started = _startupSecs < 0 ? @"…" : [NSString stringWithFormat:@"%.1f s", _startupSecs];
    NSString *text = [NSString stringWithFormat:
        @"%@\n%@ %@ / %@  đệm trước %.0f s\nhình %.0fx%.0f  bitrate %.0f kbps (đo %.0f)\nkhựng %ld  rơi khung %ld  mở %@\nRAM app %.0f MB (cao nhất %.0f)",
        _title, state, CBFormatTime(now), CBFormatTime(dur), ahead, ps.width, ps.height, ev.indicatedBitrate / 1000,
        ev.observedBitrate / 1000, (long)_stalls, (long)ev.numberOfDroppedVideoFrames, started, mb, _peakMB];
    _info.text = text;
    [self.view setNeedsLayout];
    if (++_ticks % 20 == 0) CBLog(@"[phát] %@", [text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
}

- (void)logErrorLog {
    for (AVPlayerItemErrorLogEvent *e in _item.errorLog.events) {
        CBLog(@"  errorLog: %ld %@ — %@ (%@)", (long)e.errorStatusCode, e.errorDomain, e.errorComment, e.URI);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kKVO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_torndown) return;
        if (object == self->_player) {
            CBLog(@"Tốc độ phát → %.1f ở %.0f s (app %@)", self->_player.rate, CMTimeGetSeconds(self->_player.currentTime),
                  [UIApplication sharedApplication].applicationState == UIApplicationStateActive ? @"đang mở" : @"ở nền");
            return;
        }
        if ([keyPath isEqualToString:@"status"]) {
            if (self->_item.status == AVPlayerItemStatusReadyToPlay) {
                CBLog(@"Sẵn sàng phát sau %.1f s, dài %.0f s", -[self->_openedAt timeIntervalSinceNow],
                      CMTimeGetSeconds(self->_item.duration));
            } else if (self->_item.status == AVPlayerItemStatusFailed) {
                CBLog(@"Trình phát LỖI: %@", self->_item.error);
                [self logErrorLog];
            }
        } else if ([keyPath isEqualToString:@"presentationSize"]) {
            CBLog(@"Kích thước hình: %.0fx%.0f", self->_item.presentationSize.width, self->_item.presentationSize.height);
        } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
            CBLog(@"playbackLikelyToKeepUp = %d", self->_item.playbackLikelyToKeepUp);
        }
        [self tick];
    });
}

- (void)stalled:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_stalls++;
        CBLog(@"Khựng (lần %ld) ở %.0f s", (long)self->_stalls, CMTimeGetSeconds(self->_player.currentTime));
    });
}

- (void)failedToEnd:(NSNotification *)n {
    CBLog(@"Dừng giữa chừng: %@", n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]);
    dispatch_async(dispatch_get_main_queue(), ^{ [self logErrorLog]; });
}

- (void)errorLogEntry:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerItemErrorLogEvent *e = self->_item.errorLog.events.lastObject;
        CBLog(@"errorLog mới: %ld %@ — %@ (%@)", (long)e.errorStatusCode, e.errorDomain, e.errorComment, e.URI);
    });
}

- (void)playedToEnd:(NSNotification *)n {
    CBLog(@"Hết phim");
}

#pragma mark - Nút

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIButton class]];
}

- (void)toggleOverlay {
    BOOL hide = !_bar.hidden;
    _bar.hidden = hide;
    _info.hidden = hide;
}

- (void)seekTo:(double)t {
    if (t < 0) t = 0;
    NSDate *start = [NSDate date];
    CBLog(@"Tua tới %.0f s", t);
    [_player seekToTime:CMTimeMakeWithSeconds(t, 600) completionHandler:^(BOOL finished) {
        CBLog(@"Tua xong (%d) sau %.1f s", finished, -[start timeIntervalSinceNow]);
    }];
}

- (void)back10 {
    [self seekTo:CMTimeGetSeconds(_player.currentTime) - 10];
}

- (void)fwd60 {
    [self seekTo:CMTimeGetSeconds(_player.currentTime) + 60];
}

- (void)half {
    double d = CMTimeGetSeconds(_item.duration);
    if (isfinite(d) && d > 0) [self seekTo:d / 2];
}

- (void)toggle {
    if (_player.rate > 0) [_player pause];
    else [_player play];
    [self tick];
}

- (void)close {
    [self tick];
    CBLog(@"Đóng trình phát; RAM cao nhất %.0f MB, khựng %ld lần. Trạng thái cuối: %@", _peakMB, (long)_stalls,
          [_info.text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
    [self teardown];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)teardown {
    if (_torndown) return;
    _torndown = YES;
    [_player pause];
    if (_timeObserver) {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    if (_observing) {
        for (NSString *key in @[@"status", @"playbackLikelyToKeepUp", @"presentationSize"]) {
            [_item removeObserver:self forKeyPath:key context:kKVO];
        }
        [_player removeObserver:self forKeyPath:@"rate" context:kKVO];
        _observing = NO;
    }
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.isViewLoaded) [self playerLayer].player = nil;
}

- (void)dealloc {
    [self teardown];
}

@end
