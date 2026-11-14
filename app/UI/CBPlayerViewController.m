#import "CBPlayerViewController.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static void *kKVO = &kKVO;
/// Loại server «Trình phát của trang» (mở thẳng trang tập) — iOS 6 không có WebView chạy nổi
static NSString *const kPageServer = @"page";

@interface CBVideoView : UIView
@end
@implementation CBVideoView
+ (Class)layerClass {
    return [AVPlayerLayer class];
}
@end

@interface CBPlayerViewController () <UIActionSheetDelegate, UIGestureRecognizerDelegate>
@end

@implementation CBPlayerViewController {
    NSString *_filmUrl;
    NSDictionary *_detail;
    NSString *_epUrl;
    BOOL _resumeOpen;
    NSInteger _groupIndex, _index;
    NSDictionary *_source;
    NSArray *_servers;
    NSInteger _serverIdx;
    NSMutableArray *_probeResults;  // kết quả site.videoOf từng server (NSNull = chưa hỏi, {pending} = đang hỏi)
    NSInteger _probeNext;           // server tiếp theo được xét theo thứ tự ưu tiên
    BOOL _probing;                  // đang chọn server — đã chọn được (hoặc hết server) thì kết quả về sau không làm phát lại
    NSInteger _token;
    int _resumeAt;
    BOOL _started, _closed, _dragging, _seekedResume;
    long long _lastSave;
    // Video
    CBVideoView *_video;
    AVPlayer *_player;
    AVPlayerItem *_item;
    id _timeObs;
    BOOL _observing;
    // Giao diện
    UIView *_top, *_bottom;
    UILabel *_titleLabel, *_timeLabel, *_durLabel, *_status, *_toast;
    UIButton *_closeButton, *_serverButton, *_playButton, *_prevButton, *_nextButton, *_backButton, *_fwdButton, *_retryButton;
    UISlider *_slider;
    UIActivityIndicatorView *_spinner;
    NSTimer *_hideTimer;
}

- (instancetype)initWithFilm:(NSString *)filmUrl detail:(NSDictionary *)detail episode:(NSString *)epUrl resume:(BOOL)resume {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _filmUrl = filmUrl;
        _detail = detail;
        _epUrl = epUrl;
        _resumeOpen = resume;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)dealloc {
    [self teardownPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Giao diện

- (UIButton *)barButton:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme text] forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.3] forState:UIControlStateDisabled];
    b.titleLabel.font = [CBTheme bold:[CBTheme isPad] ? 17 : 15];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UILabel *)overlayLabel:(UIFont *)font {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [CBTheme text];
    l.font = font;
    return l;
}

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    root.backgroundColor = [UIColor blackColor];
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _video = [[CBVideoView alloc] initWithFrame:self.view.bounds];
    _video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _video.backgroundColor = [UIColor blackColor];
    [(AVPlayerLayer *)_video.layer setVideoGravity:[CBPrefs videoFill] ? AVLayerVideoGravityResizeAspectFill
                                                                       : AVLayerVideoGravityResizeAspect];
    [self.view addSubview:_video];

    UIColor *shade = [UIColor colorWithWhite:0 alpha:0.6];
    _top = [[UIView alloc] init];
    _top.backgroundColor = shade;
    [self.view addSubview:_top];
    _closeButton = [self barButton:@"✕ Đóng" action:@selector(close)];
    [_top addSubview:_closeButton];
    _serverButton = [self barButton:@"Server" action:@selector(showServers)];
    [_top addSubview:_serverButton];
    _titleLabel = [self overlayLabel:[CBTheme bold:15]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_top addSubview:_titleLabel];

    _bottom = [[UIView alloc] init];
    _bottom.backgroundColor = shade;
    [self.view addSubview:_bottom];
    _prevButton = [self barButton:@"« Tập trước" action:@selector(previousEpisode)];
    _backButton = [self barButton:[NSString stringWithFormat:@"−%lds", (long)[CBPrefs seekStep]] action:@selector(backTapped)];
    _playButton = [self barButton:@"Dừng" action:@selector(togglePlay)];
    _fwdButton = [self barButton:[NSString stringWithFormat:@"+%lds", (long)[CBPrefs seekStep]] action:@selector(fwdTapped)];
    _nextButton = [self barButton:@"Tập sau »" action:@selector(nextEpisode)];
    for (UIButton *b in @[_prevButton, _backButton, _playButton, _fwdButton, _nextButton]) [_bottom addSubview:b];
    _slider = [[UISlider alloc] init];
    _slider.minimumTrackTintColor = [CBTheme brand];
    _slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.3];
    [_slider addTarget:self action:@selector(sliderDown) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(sliderMoved) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                                                       UIControlEventTouchCancel];
    [_bottom addSubview:_slider];
    _timeLabel = [self overlayLabel:[CBTheme font:13]];
    _durLabel = [self overlayLabel:[CBTheme font:13]];
    _durLabel.textAlignment = NSTextAlignmentRight;
    [_bottom addSubview:_timeLabel];
    [_bottom addSubview:_durLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
    _status = [self overlayLabel:[CBTheme font:16]];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 0;
    [self.view addSubview:_status];
    _retryButton = [CBTheme button:@"Thử server khác" primary:YES];
    [_retryButton addTarget:self action:@selector(showServers) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.hidden = YES;
    [self.view addSubview:_retryButton];
    _toast = [self overlayLabel:[CBTheme bold:22]];
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.backgroundColor = shade;
    _toast.layer.cornerRadius = 8;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0;
    [self.view addSubview:_toast];

    // Chạm: hiện / ẩn thanh nút; chạm đúp nửa trái / phải: lùi / tới; chụm: vừa / lấp đầy màn hình
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    dbl.numberOfTapsRequired = 2;
    dbl.delegate = self;
    [_video addGestureRecognizer:dbl];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    [tap requireGestureRecognizerToFail:dbl];
    tap.delegate = self;
    [_video addGestureRecognizer:tap];
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    [_video addGestureRecognizer:pinch];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appResigning) name:UIApplicationWillResignActiveNotification object:nil];

    [self setControlsVisible:YES];
    if (_detail) {
        [self start:_detail];
    } else {
        [self showLoading:@"Đang tải phim…"];
        NSInteger t = ++_token;
        [CBCore call:@"site.detail" args:@{@"url": _filmUrl ?: @""} done:^(id ok, NSString *err) {
            if (t != self->_token || self->_closed) return;
            if (CBIsDict(ok)) [self start:ok];
            else [self showError:[NSString stringWithFormat:@"Không tải được phim.\n%@", err ?: @""] retry:NO];
        }];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [CBTheme isPad] ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (![CBTheme isPad]) return UIInterfaceOrientationLandscapeRight;
    return [UIApplication sharedApplication].statusBarOrientation;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    BOOL pad = [CBTheme isPad];
    CGFloat topH = 44;
    _top.frame = CGRectMake(0, 0, w, topH);
    _closeButton.frame = CGRectMake(4, 0, 90, topH);
    _serverButton.frame = CGRectMake(w - 94, 0, 90, topH);
    _titleLabel.frame = CGRectMake(98, 0, w - 196, topH);
    CGFloat bottomH = 88;
    _bottom.frame = CGRectMake(0, h - bottomH, w, bottomH);
    _timeLabel.frame = CGRectMake(10, 8, 64, 28);
    _durLabel.frame = CGRectMake(w - 74, 8, 64, 28);
    _slider.frame = CGRectMake(78, 8, w - 156, 28);
    NSArray *row = @[_prevButton, _backButton, _playButton, _fwdButton, _nextButton];
    CGFloat bw = MIN(pad ? 140 : 110, w / row.count);
    CGFloat x0 = (w - bw * row.count) / 2;
    for (NSUInteger i = 0; i < row.count; i++) [row[i] setFrame:CGRectMake(x0 + bw * i, 40, bw, 44)];
    _spinner.center = CGPointMake(w / 2, h / 2 - 30);
    _status.frame = CGRectMake(30, h / 2 - 10, w - 60, [CBTheme heightOf:_status.text font:_status.font width:w - 60] + 4);
    CGSize rs = [_retryButton sizeThatFits:CGSizeMake(300, 44)];
    _retryButton.frame = CGRectMake((w - rs.width) / 2, CGRectGetMaxY(_status.frame) + 14, rs.width, 44);
    _toast.frame = CGRectMake((w - 160) / 2, h / 2 - 30, 160, 60);
}

- (void)setControlsVisible:(BOOL)visible {
    [_hideTimer invalidate];
    _hideTimer = nil;
    [UIView animateWithDuration:0.2 animations:^{
        self->_top.alpha = visible ? 1 : 0;
        self->_bottom.alpha = visible ? 1 : 0;
    }];
    if (visible && _player.rate > 0) {
        _hideTimer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(autoHide) userInfo:nil repeats:NO];
    }
}

- (void)autoHide {
    if (!_dragging && _player.rate > 0) [self setControlsVisible:NO];
}

- (void)toggleControls {
    [self setControlsVisible:_top.alpha < 0.5];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)showToast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.4 delay:0.6 options:0 animations:^{ self->_toast.alpha = 0; } completion:nil];
}

- (void)showLoading:(NSString *)text {
    _status.text = text;
    _status.hidden = NO;
    _retryButton.hidden = YES;
    [_spinner startAnimating];
    [self.view setNeedsLayout];
}

- (void)hideStatus {
    _status.hidden = YES;
    _retryButton.hidden = YES;
    [_spinner stopAnimating];
}

- (void)showError:(NSString *)text retry:(BOOL)retry {
    CBLog(@"Trình phát báo lỗi: %@", [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
    [_spinner stopAnimating];
    _status.text = text;
    _status.hidden = NO;
    _retryButton.hidden = !retry;
    [self setControlsVisible:YES];
    [self.view setNeedsLayout];
}

#pragma mark - Mở tập

- (NSArray *)episodes {
    NSArray *groups = CBArr(_detail, @"groups");
    return _groupIndex < (NSInteger)groups.count ? (CBArr(groups[_groupIndex], @"episodes") ?: @[]) : @[];
}

- (void)start:(NSDictionary *)d {
    _detail = d;
    _filmUrl = CBStr(d, @"url") ?: _filmUrl;
    NSInteger g = CBDetailGroupIndexOf(d, _epUrl);
    _groupIndex = g >= 0 ? g : 0;
    NSArray *eps = [self episodes];
    if (!eps.count) {
        [self showError:@"Phim này chưa có tập nào." retry:NO];
        return;
    }
    NSInteger i = 0;
    for (NSUInteger k = 0; k < eps.count; k++) {
        if ([CBStr(eps[k], @"url") isEqualToString:_epUrl]) i = (NSInteger)k;
    }
    // Mở từ «Xem tiếp» mà tập đó đã xem hết → sang tập sau
    if (_resumeOpen && [CBPrefs finished:CBStr(eps[i], @"url") ?: @""] && i + 1 < (NSInteger)eps.count) i++;
    [self openEpisode:i];
}

- (void)openEpisode:(NSInteger)i {
    NSArray *eps = [self episodes];
    if (i < 0 || i >= (NSInteger)eps.count) return;
    [self savePosition];
    [self teardownPlayer];
    _index = i;
    NSDictionary *ep = eps[i];
    _epUrl = CBStr(ep, @"url");
    NSArray *groups = CBArr(_detail, @"groups");
    NSString *groupName = groups.count > 1 ? [NSString stringWithFormat:@" (%@)", CBStr(groups[_groupIndex], @"name") ?: @""] : @"";
    _titleLabel.text = [NSString stringWithFormat:@"%@ — %@%@", CBStr(_detail, @"title") ?: @"", CBStr(ep, @"title") ?: @"", groupName];
    _prevButton.enabled = i > 0;
    _nextButton.enabled = i + 1 < (NSInteger)eps.count;
    _resumeAt = [CBPrefs positionOf:_epUrl];
    _started = NO;
    _seekedResume = NO;
    _slider.value = 0;
    _timeLabel.text = @"00:00";
    _durLabel.text = @"--:--";
    [CBPrefs addHistory:_detail episode:ep];
    [CBCore sync:@"home.markSeen" args:@{@"detail": _detail}];
    NSDictionary *latest = CBDetailLatestEpisode(_detail);
    if (latest) {
        [CBPrefs updateFollow:CBStr(_detail, @"url") count:CBDetailEpisodeCount(_detail) latest:CBStr(latest, @"title") seen:YES];
    }
    [self updateNowPlaying];
    [self showLoading:[NSString stringWithFormat:@"Đang mở %@…", CBStr(ep, @"title") ?: @"tập phim"]];
    NSInteger t = ++_token;
    long long t0 = CBNowMs();
    NSDictionary *group = groups.count > _groupIndex ? groups[_groupIndex] : nil;
    NSMutableDictionary *args = [@{@"detail": _detail, @"ep": ep} mutableCopy];
    if (group) args[@"group"] = group;
    [CBCore call:@"kk.source" args:args done:^(id ok, NSString *err) {
        if (t != self->_token || self->_closed) return;
        if (!CBIsDict(ok)) {
            [self showError:[NSString stringWithFormat:@"Không mở được %@.\n%@", CBStr(ep, @"title") ?: @"tập này", err ?: @""]
                      retry:NO];
            return;
        }
        self->_source = ok;
        self->_servers = [self orderedServers:ok];
        self->_probeResults = nil;
        CBLog(@"Tập %@: %lu server (%lld ms) — %@", CBStr(ep, @"title"), (unsigned long)self->_servers.count, CBNowMs() - t0,
              [[self->_servers valueForKey:@"label"] componentsJoinedByString:@", "]);
        if (!self->_servers.count) {
            [self showError:@"Tập này chỉ xem được bằng trình phát của trang — iOS 6 không mở được.\nThử trang phim khác (vd KKPhim)."
                      retry:NO];
            return;
        }
        [self tryServer:0 token:t];
    }];
}

- (NSString *)workedKey:(NSDictionary *)src {
    return [@"legacy_server@" stringByAppendingString:CBHostOf(CBStr(src, @"epUrl") ?: @"") ?: @""];
}

/// Server của tập (bỏ «Trình phát của trang»): server người xem chọn lần trước, rồi server bản iOS 6 phát được lần trước
- (NSArray *)orderedServers:(NSDictionary *)src {
    NSString *pref = [CBPrefs serverTypeForHost:CBHostOf(CBStr(src, @"epUrl") ?: @"")];
    NSMutableArray *list = [NSMutableArray array];
    // Server bản iOS 6 phát được lần trước trên trang này (khoá riêng, không đè lựa chọn server của bản TV khi đồng bộ)
    id workedValue = [CBPrefs get:[self workedKey:src]];
    NSString *worked = CBIsStr(workedValue) ? workedValue : nil;
    NSMutableArray *first = [NSMutableArray array];
    for (id s in CBArr(src, @"servers") ?: @[]) {
        if (!CBIsDict(s) || [CBStr(s, @"type") isEqualToString:kPageServer]) continue;
        NSString *type = CBStr(s, @"type");
        if (pref && [type isEqualToString:pref]) [first insertObject:s atIndex:0];
        else if (worked && [type isEqualToString:worked]) [first addObject:s];
        else [list addObject:s];
    }
    return [first arrayByAddingObjectsFromArray:list];
}

/// Hỏi link của mọi server cùng lúc (trang chậm + nhiều server nhúng: không phải chờ lần lượt) nhưng vẫn chọn theo thứ tự ưu tiên:
/// server k chỉ được phát khi các server đứng trước đã trả lời là không phát được.
- (void)tryServer:(NSInteger)k token:(NSInteger)t {
    if (t != _token || _closed) return;
    _probeNext = k;
    _probing = YES;
    if (!_probeResults || _probeResults.count != _servers.count) {
        _probeResults = [NSMutableArray array];
        for (NSUInteger i = 0; i < _servers.count; i++) [_probeResults addObject:[NSNull null]];
    }
    [self showLoading:@"Đang tìm server phát được…"];
    long long t0 = CBNowMs();
    for (NSInteger i = k; i < (NSInteger)_servers.count; i++) {
        if (_probeResults[i] != [NSNull null]) continue;
        _probeResults[i] = @{@"pending": @YES};
        NSDictionary *s = _servers[i];
        [CBCore call:@"site.videoOf" args:@{@"src": _source, @"server": s} done:^(id v, NSString *err) {
            if (t != self->_token || self->_closed || i >= (NSInteger)self->_probeResults.count) return;
            self->_probeResults[i] = CBIsDict(v) ? v : @{@"err": err ?: @"không có link"};
            CBLog(@"Server %@: %@ (%lld ms)", CBStr(s, @"label"), CBStr(v, @"url") ?: err, CBNowMs() - t0);
            [self advanceProbe:t];
        }];
    }
    [self advanceProbe:t];
}

- (void)advanceProbe:(NSInteger)t {
    if (t != _token || _closed || !_probing) return;
    while (_probeNext < (NSInteger)_servers.count) {
        NSDictionary *v = _probeResults[_probeNext];
        if (!CBIsDict(v) || CBBool(v, @"pending", NO)) {
            NSDictionary *s = _servers[_probeNext];
            [_serverButton setTitle:CBStr(s, @"label") ?: @"Server" forState:UIControlStateNormal];
            return;  // chờ server đứng trước trả lời
        }
        NSDictionary *s = _servers[_probeNext];
        NSString *url = CBStr(v, @"url");
        NSString *path = [[NSURL URLWithString:url].path lowercaseString];
        BOOL playable = url && (CBBool(v, @"file", NO) || [path hasSuffix:@".m3u8"]);
        NSString *local = nil;
        if (playable) {
            NSMutableDictionary *args = [@{@"src": url, @"page": CBStr(_source, @"epUrl") ?: @"", @"hls": @NO} mutableCopy];
            if (CBStr(v, @"subtitle")) args[@"sub"] = CBStr(v, @"subtitle");
            local = CBStr([CBCore sync:@"media.open" args:args], @"url");
        }
        if (local) {
            _serverIdx = _probeNext;
            [_serverButton setTitle:CBStr(s, @"label") ?: @"Server" forState:UIControlStateNormal];
            [self showLoading:[NSString stringWithFormat:@"Đang tải %@…", CBStr(s, @"label") ?: @"server"]];
            CBLog(@"Phát %@ qua %@ (server %@, bắt đầu %ds)", url, local, CBStr(s, @"label"), _resumeAt);
            _probing = NO;
            [self play:local];
            return;
        }
        CBLog(@"Server %@: bỏ qua — %@", CBStr(s, @"label"),
              playable ? @"cổng phát nội bộ không mở được" : (url ? @"chỉ có trình phát nhúng" : CBStr(v, @"err")));
        _probeNext++;
    }
    _probing = NO;
    [self showError:@"Không server nào phát được trên iOS 6 (các server còn lại chỉ có trình phát nhúng của trang).\n"
                    @"Chọn lại server hoặc xem ở trang phim khác (vd KKPhim)."
              retry:_servers.count > 0];
}

#pragma mark - AVPlayer

- (void)play:(NSString *)url {
    [self teardownPlayer];
    _item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    _player = [AVPlayer playerWithPlayerItem:_item];
    [(AVPlayerLayer *)_video.layer setPlayer:_player];
    [_item addObserver:self forKeyPath:@"status" options:0 context:kKVO];
    [_item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:kKVO];
    [_player addObserver:self forKeyPath:@"rate" options:0 context:kKVO];
    _observing = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(playedToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [nc addObserver:self selector:@selector(failedToEnd:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    __weak CBPlayerViewController *weakSelf = self;
    _timeObs = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:dispatch_get_main_queue()
                                                usingBlock:^(CMTime time) { [weakSelf tick]; }];
    [_player play];
}

- (void)teardownPlayer {
    if (!_player) return;
    [_player pause];
    if (_timeObs) [_player removeTimeObserver:_timeObs];
    _timeObs = nil;
    if (_observing) {
        [_item removeObserver:self forKeyPath:@"status" context:kKVO];
        [_item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:kKVO];
        [_player removeObserver:self forKeyPath:@"rate" context:kKVO];
        _observing = NO;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    [(AVPlayerLayer *)_video.layer setPlayer:nil];
    _player = nil;
    _item = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kKVO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_player || self->_closed) return;
        if ([keyPath isEqualToString:@"status"] && object == self->_item) {
            if (self->_item.status == AVPlayerItemStatusReadyToPlay) {
                if (!self->_seekedResume && self->_resumeAt > 5) {
                    self->_seekedResume = YES;
                    CBLog(@"Xem tiếp từ %ds", self->_resumeAt);
                    [self->_player seekToTime:CMTimeMakeWithSeconds(self->_resumeAt, 600)];
                    [self showToast:[NSString stringWithFormat:@"Xem tiếp %@", [CBTheme time:self->_resumeAt]]];
                }
            } else if (self->_item.status == AVPlayerItemStatusFailed) {
                [self playbackFailed:self->_item.error];
            }
        } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
            if (self->_item.playbackLikelyToKeepUp || self->_player.rate > 0) [self->_spinner stopAnimating];
            else if (self->_started) [self->_spinner startAnimating];
        } else if ([keyPath isEqualToString:@"rate"]) {
            [self->_playButton setTitle:self->_player.rate > 0 ? @"Dừng" : @"Phát" forState:UIControlStateNormal];
            [self updateNowPlaying];
        }
    });
}

- (void)playbackFailed:(NSError *)error {
    AVPlayerItemErrorLogEvent *ev = _item.errorLog.events.lastObject;
    CBLog(@"AVPlayer lỗi (server %@): %@ — %ld %@", CBStr(_servers.count > _serverIdx ? _servers[_serverIdx] : nil, @"label"),
          error.localizedDescription, (long)ev.errorStatusCode, ev.errorComment);
    // Giữ chỗ đang xem rồi thử server sau
    double now = CMTimeGetSeconds(_player.currentTime);
    if (_started && isfinite(now) && now > 5) _resumeAt = (int)now;
    _seekedResume = NO;
    [self teardownPlayer];
    [self tryServer:_serverIdx + 1 token:_token];
}

- (void)failedToEnd:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_closed) return;
        [self playbackFailed:n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]];
    });
}

- (void)playedToEnd:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_closed) return;
        [CBPrefs savePosition:self->_epUrl seconds:0 film:self->_filmUrl];
        if ([CBPrefs autoNext] && self->_index + 1 < (NSInteger)[self episodes].count) {
            CBLog(@"Hết tập — tự chuyển tập sau");
            [self openEpisode:self->_index + 1];
        } else {
            [self showError:@"Hết phim." retry:NO];
        }
    });
}

- (void)tick {
    if (!_player || _closed) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    CMTime d = _item.duration;
    double dur = CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : NAN;
    if (!_started && now > 0.5 && _player.rate > 0) {
        _started = YES;
        [self hideStatus];
        [self setControlsVisible:NO];
        NSString *type = _serverIdx < (NSInteger)_servers.count ? CBStr(_servers[_serverIdx], @"type") : nil;
        if (type) [CBPrefs set:[self workedKey:_source] value:type];
    }
    if (!_dragging) {
        _timeLabel.text = [CBTheme time:now];
        _durLabel.text = [CBTheme time:dur];
        _slider.value = isfinite(dur) && dur > 0 ? (float)(now / dur) : 0;
    }
    if (_started && CBNowMs() - _lastSave > 10000) [self savePosition];
}

- (void)savePosition {
    if (!_started || !_player || !_epUrl) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    CMTime d = _item.duration;
    double dur = CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : 0;
    if (!isfinite(now) || now < 1) return;
    // Xem gần hết thì coi như xong (lần sau mở lại từ đầu) — như bản Windows / TV
    BOOL done = dur > 0 && now > dur - 90;
    [CBPrefs savePosition:_epUrl seconds:done ? 0 : (int)now film:_filmUrl];
    _lastSave = CBNowMs();
}

- (void)appResigning {
    [self savePosition];
}

#pragma mark - Điều khiển

- (void)togglePlay {
    if (!_player) return;
    if (_player.rate > 0) [_player pause];
    else [_player play];
    [self setControlsVisible:YES];
}

- (void)seekTo:(double)seconds {
    if (!_player) return;
    [_player seekToTime:CMTimeMakeWithSeconds(MAX(0, seconds), 600)];
}

- (void)seekBy:(double)delta {
    if (!_player) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(now)) return;
    [self seekTo:now + delta];
    [self showToast:[NSString stringWithFormat:@"%@%.0fs", delta < 0 ? @"−" : @"+", fabs(delta)]];
}

- (void)backTapped {
    [self seekBy:-(double)[CBPrefs seekStep]];
}

- (void)fwdTapped {
    [self seekBy:(double)[CBPrefs seekStep]];
}

- (void)doubleTap:(UITapGestureRecognizer *)g {
    BOOL left = [g locationInView:_video].x < _video.bounds.size.width / 2;
    [self seekBy:(left ? -1 : 1) * (double)[CBPrefs seekStep]];
}

- (void)pinch:(UIPinchGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    BOOL fill = g.scale > 1;
    [CBPrefs setVideoFill:fill];
    [(AVPlayerLayer *)_video.layer setVideoGravity:fill ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect];
    [self showToast:fill ? @"Lấp đầy" : @"Vừa màn hình"];
}

- (void)sliderDown {
    _dragging = YES;
    [_hideTimer invalidate];
}

- (void)sliderMoved {
    CMTime d = _item.duration;
    if (CMTIME_IS_NUMERIC(d)) _timeLabel.text = [CBTheme time:CMTimeGetSeconds(d) * _slider.value];
}

- (void)sliderUp {
    _dragging = NO;
    CMTime d = _item.duration;
    if (CMTIME_IS_NUMERIC(d)) [self seekTo:CMTimeGetSeconds(d) * _slider.value];
    [self setControlsVisible:YES];
}

- (void)nextEpisode {
    if (_index + 1 < (NSInteger)[self episodes].count) [self openEpisode:_index + 1];
}

- (void)previousEpisode {
    if (_index > 0) [self openEpisode:_index - 1];
}

- (void)showServers {
    if (!_servers.count) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chọn server" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSUInteger i = 0; i < _servers.count; i++) {
        NSString *label = CBStr(_servers[i], @"label") ?: @"?";
        [sheet addButtonWithTitle:(NSInteger)i == _serverIdx ? [@"✓ " stringByAppendingString:label] : label];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Huỷ"];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index < 0) return;
    [self selectServer:index];
}

- (void)selectServer:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_servers.count) return;
    NSDictionary *s = _servers[index];
    [CBPrefs setServerForHost:CBHostOf(CBStr(_source, @"epUrl") ?: @"") type:CBStr(s, @"type") label:CBStr(s, @"label")];
    double now = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    if (_started && isfinite(now) && now > 5) _resumeAt = (int)now;
    _seekedResume = NO;
    [self savePosition];
    [self teardownPlayer];
    _started = NO;
    _probeResults = nil;  // lượt hỏi cũ (mã cũ) bị bỏ — hỏi lại
    [self tryServer:index token:++_token];
}

- (void)close {
    if (_closed) return;
    [self savePosition];
    _closed = YES;
    _token++;
    [self teardownPlayer];
    [CBCore sync:@"media.closeAll" args:nil];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateNowPlaying {
    NSArray *eps = [self episodes];
    NSString *ep = _index < (NSInteger)eps.count ? CBStr(eps[_index], @"title") : nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = ep ?: @"";
    info[MPMediaItemPropertyArtist] = CBStr(_detail, @"title") ?: @"Côn Bằng TV Legacy";
    if (_item && CMTIME_IS_NUMERIC(_item.duration)) {
        info[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(_item.duration));
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime));
        info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlay]; break;
        case UIEventSubtypeRemoteControlPlay: [_player play]; break;
        case UIEventSubtypeRemoteControlPause: [_player pause]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self nextEpisode]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self previousEpisode]; break;
        default: break;
    }
}

- (NSString *)statusLine {
    double now = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    CMTime d = _item.duration;
    AVPlayerItemAccessLogEvent *ev = _item.accessLog.events.lastObject;
    return [NSString stringWithFormat:@"%@ | %@ / %@ | rate %.1f | server %@ | đệm %@ | bitrate %.0f kbps | khựng %ld | RAM %.0f MB",
            _titleLabel.text, [CBTheme time:now], [CBTheme time:CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : NAN], _player.rate,
            CBStr(_servers.count > _serverIdx ? _servers[_serverIdx] : nil, @"label"),
            _item.playbackLikelyToKeepUp ? @"đủ" : @"thiếu", ev.observedBitrate / 1000, (long)ev.numberOfStalls, CBResidentMB()];
}

@end
