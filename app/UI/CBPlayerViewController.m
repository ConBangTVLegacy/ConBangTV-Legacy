#import "CBPlayerViewController.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBSync.h"
#import "CBTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static void *kKVO = &kKVO;
/// Loại server «Trình phát của trang» (mở thẳng trang tập) — iOS 6 không có WebView chạy nổi
static NSString *const kPageServer = @"page";

/// Độ dài (giây) — chỉ đọc khi AVPlayer đã sẵn sàng. Trên iOS 6, đọc duration của tệp MP4 chưa tải xong thông tin là chặn luồng
/// chính để chờ, mà bộ tải tệp của AVPlayer lại chạy trên luồng chính → kẹt tới hết hạn rồi báo lỗi -12935 (MP4 CLB Phim Xưa).
static double CBDuration(AVPlayerItem *item) {
    if (!item || item.status != AVPlayerItemStatusReadyToPlay) return NAN;
    CMTime d = item.duration;
    return CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : NAN;
}

@interface CBVideoView : UIView
@end
@implementation CBVideoView
+ (Class)layerClass {
    return [AVPlayerLayer class];
}
@end

/// Giây từ mốc thời gian phụ đề: «01:02:03.456», «02:03.456» (WebVTT) hoặc «01:02:03,456» (SRT); âm = không đọc được
static double CBSubTime(NSString *s) {
    NSArray *parts = [[s stringByReplacingOccurrencesOfString:@"," withString:@"."] componentsSeparatedByString:@":"];
    if (parts.count < 2 || parts.count > 3) return -1;
    double t = 0;
    for (NSString *p in parts) t = t * 60 + [p doubleValue];
    return t;
}

/// Đọc phụ đề WebVTT / SRT → [{s, e, t}] theo thời gian bắt đầu; bỏ thẻ định dạng (<i>, <c.vi>, {\an8}…)
static NSArray *CBParseSubtitles(NSString *text) {
    static NSRegularExpression *tags;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]*>|\\{\\\\[^}]*\\}" options:0 error:NULL];
    NSString *norm = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r"
                                                                                                                withString:@"\n"];
    NSMutableArray *cues = [NSMutableArray array];
    for (NSString *block in [norm componentsSeparatedByString:@"\n\n"]) {
        NSArray *lines = [block componentsSeparatedByString:@"\n"];
        NSUInteger i = 0;
        while (i < lines.count && [lines[i] rangeOfString:@"-->"].location == NSNotFound) i++;
        if (i >= lines.count) continue;
        NSArray *se = [lines[i] componentsSeparatedByString:@"-->"];
        NSString *a = [se[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *b = [[[se[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            componentsSeparatedByString:@" "] firstObject];  // bỏ «align:… position:…» sau mốc kết thúc
        double s = CBSubTime(a), e = CBSubTime(b);
        if (s < 0 || e <= s) continue;
        NSMutableArray *textLines = [NSMutableArray array];
        for (NSUInteger k = i + 1; k < lines.count; k++) {
            NSString *l = [tags stringByReplacingMatchesInString:lines[k] options:0 range:NSMakeRange(0, [lines[k] length]) withTemplate:@""];
            l = [[[[l stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"] stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"]
                stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"] stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
            l = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (l.length) [textLines addObject:l];
        }
        if (textLines.count) [cues addObject:@{@"s": @(s), @"e": @(e), @"t": [textLines componentsJoinedByString:@"\n"]}];
    }
    [cues sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [x[@"s"] compare:y[@"s"]]; }];
    return cues;
}

#pragma mark - Ô tập trong bảng chọn tập

@interface CBPlayerEpCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
@end

@implementation CBPlayerEpCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        self.contentView.layer.cornerRadius = 6;
        self.contentView.layer.borderColor = [CBTheme focus].CGColor;
        _label = [[UILabel alloc] initWithFrame:CGRectInset(self.contentView.bounds, 4, 0)];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [CBTheme font:15];
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.6;
        [self.contentView addSubview:_label];
    }
    return self;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1;
}
@end

@interface CBPlayerViewController () <UIGestureRecognizerDelegate, UICollectionViewDataSource,
                                      UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
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
    BOOL _graceArmed, _skipPending;  // server sau đã có link phát được: chờ server đứng trước thêm 2,5 s rồi bỏ qua
    NSInteger _token;
    int _resumeAt;
    BOOL _started, _closed, _dragging, _seekedResume;
    BOOL _appeared, _limitWarned;
    BOOL _everPlayed;   // tập này đã phát được (rớt về sau là mất kết nối, không phải «iOS 6 không phát được»)
    BOOL _retriedSame;  // đã thử lại server đang phát sau khi rớt giữa chừng
    BOOL _ended;        // đang ở cuối tập (hiện «Hết tập.»)
    BOOL _seeking;      // đang tua — chưa cập nhật thanh tua theo thời gian cũ
    NSUInteger _tickCount;
    // Menu «⋯»
    UIButton *_moreButton;
    // Bảng chọn tự vẽ (server, menu «⋯», tốc độ, hẹn giờ): UIActionSheet của iOS 6 ở iPhone ngang thành danh sách cuộn, che mục
    UIView *_menuPanel;
    UIScrollView *_menuBox;
    UILabel *_menuTitle;
    NSMutableArray *_menuButtons;
    NSArray *_menuItems;          // @[@[tên, khối], …]
    float _speed;                 // tốc độ phát (0,75–2×), trong lần xem này
    long long _sleepAt;           // hẹn giờ tắt (ms, 0 = không hẹn)
    BOOL _sleepEndOfEp, _sleepPaused;
    int _introStart, _introEnd;   // đoạn mở đầu của phim (giây; -1 = chưa đánh dấu) — khoá intro@<phim> như bản Windows
    BOOL _introSkipped;           // tập này đã tự bỏ qua đoạn mở đầu
    // Phụ đề rời (server riêng của PhimMoi): lõi phục vụ tệp WebVTT ở cổng phát nội bộ; AVPlayer iOS 6 không gắn được → tự vẽ
    NSArray *_cues;      // [{s, e, t}] theo thời gian bắt đầu
    NSUInteger _cueIdx;
    NSInteger _subToken;
    UILabel *_subLabel;
    CBLimitBlock _pendingBlock;  // hết giờ xem trước khi màn hiện xong — xử lý lúc viewDidAppear
    NSString *_blockedEp;
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
    UIButton *_episodesButton;   // «☰ Tập»: bảng chọn tập
    UIView *_epPanel;
    UICollectionView *_epGrid;
    UISegmentedControl *_epGroups;
    UIScrollView *_epGroupsStrip;
    NSInteger _panelGroup;      // bản đang xem trong bảng (chưa đổi bản đang phát cho tới khi chọn tập)
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
        _speed = 1;
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
    [CBSync setPlaying:YES];
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
    _serverButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _serverButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _serverButton.titleLabel.minimumScaleFactor = 0.75;
    [_top addSubview:_serverButton];
    _episodesButton = [self barButton:@"☰ Tập" action:@selector(toggleEpisodes)];
    _episodesButton.hidden = YES;
    [_top addSubview:_episodesButton];
    _moreButton = [self barButton:@"⋯" action:@selector(showMenu)];
    _moreButton.titleLabel.font = [CBTheme bold:24];
    [_top addSubview:_moreButton];
    _titleLabel = [self overlayLabel:[CBTheme bold:15]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_top addSubview:_titleLabel];

    _bottom = [[UIView alloc] init];
    _bottom.backgroundColor = shade;
    [self.view addSubview:_bottom];
    _prevButton = [self barButton:@"« Tập trước" action:@selector(previousEpisode)];
    _backButton = [self barButton:[NSString stringWithFormat:@"−%lds", (long)[CBPrefs seekStep]] action:@selector(backTapped)];
    _playButton = [self barButton:@"Tạm dừng" action:@selector(togglePlay)];
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

    _subLabel = [[UILabel alloc] init];
    _subLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _subLabel.textColor = [UIColor whiteColor];
    _subLabel.font = [CBTheme bold:[CBTheme isPad] ? 24 : 17];
    _subLabel.numberOfLines = 0;
    _subLabel.textAlignment = NSTextAlignmentCenter;
    _subLabel.shadowColor = [UIColor blackColor];
    _subLabel.shadowOffset = CGSizeMake(1, 1);
    _subLabel.layer.cornerRadius = 4;
    _subLabel.clipsToBounds = YES;
    _subLabel.hidden = YES;
    _subLabel.userInteractionEnabled = NO;
    [self.view addSubview:_subLabel];

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
        [self loadFilm];
    }
}

- (void)loadFilm {
    [self showLoading:@"Đang tải phim…"];
    NSInteger t = ++_token;
    [CBCore call:@"site.detail" args:@{@"url": _filmUrl ?: @""} done:^(id ok, NSString *err) {
        if (t != self->_token || self->_closed) return;
        if (CBIsDict(ok)) [self start:ok];
        else [self showError:[NSString stringWithFormat:@"Không tải được phim.\n%@", CBCleanError(err)] button:@"Thử lại"
                      action:@selector(loadFilm)];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _appeared = YES;
    if (_pendingBlock != CBLimitNone) {
        CBLimitBlock b = _pendingBlock;
        _pendingBlock = CBLimitNone;
        [self limitBlocked:b episode:_blockedEp];
        return;
    }
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
    // Nút server rộng theo tên server (vd «HLS (bỏ quảng cáo)» — trước bị cắt còn «HLS…cáo)»), tối đa ~1/3 màn
    CGFloat sw = MIN(MIN(w * 0.32, 240), MAX(90, ceil([_serverButton.titleLabel.text sizeWithFont:_serverButton.titleLabel.font].width) + 20));
    CGFloat x = w - sw - 4;
    _serverButton.frame = CGRectMake(x, 0, sw, topH);
    if (!_episodesButton.hidden) {
        x -= 90;
        _episodesButton.frame = CGRectMake(x, 0, 86, topH);
    }
    x -= 48;
    _moreButton.frame = CGRectMake(x, 0, 44, topH);
    _titleLabel.frame = CGRectMake(98, 0, MAX(0, x - 102), topH);
    [self layoutEpisodePanel];
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
    CGFloat tw = MIN(w - 40, MAX(160, ceil([_toast.text ?: @"" sizeWithFont:_toast.font].width) + 40));  // «Xem tiếp 1:05:12»
    _toast.frame = CGRectMake((w - tw) / 2, h / 2 - 30, tw, 60);
    [self layoutSubtitle];
    [self layoutMenuPanel];
}

- (void)setServerTitle:(NSString *)title {
    [_serverButton setTitle:title ?: @"Server" forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)setControlsVisible:(BOOL)visible {
    [_hideTimer invalidate];
    _hideTimer = nil;
    if (!visible && _epPanel) return;  // đang chọn tập
    [UIView animateWithDuration:0.2 animations:^{
        self->_top.alpha = visible ? 1 : 0;
        self->_bottom.alpha = visible ? 1 : 0;
        [self layoutSubtitle];
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
    if (g.view == _menuPanel) return touch.view == _menuPanel;  // bảng chọn: chỉ chạm ra ngoài hộp mới đóng
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)showToast:(NSString *)text {
    _toast.text = text;
    [self.view setNeedsLayout];
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
    [self showError:text button:retry ? @"Chọn server" : nil action:@selector(showServers)];
}

/// Báo lỗi / trạng thái giữa màn kèm một nút (nil = không nút): «Thử lại», «Chọn server», «Tập sau »»…
- (void)showError:(NSString *)text button:(NSString *)title action:(SEL)action {
    CBLog(@"Trình phát: %@", [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
    [_spinner stopAnimating];
    _status.text = text;
    _status.hidden = NO;
    [_retryButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    if (title && action) {
        [_retryButton setTitle:title forState:UIControlStateNormal];
        [_retryButton addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    _retryButton.hidden = !(title && action);
    [self setControlsVisible:YES];
    [self.view setNeedsLayout];
}

#pragma mark - Bảng chọn tập («☰ Tập»)

- (void)toggleEpisodes {
    if (_epPanel) {
        [self hideEpisodes];
        return;
    }
    NSArray *groups = CBArr(_detail, @"groups");
    _panelGroup = _groupIndex;
    _epPanel = [[UIView alloc] init];
    _epPanel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    if (groups.count > 1) {
        NSMutableArray *names = [NSMutableArray array];
        for (id g in groups) [names addObject:CBStr(g, @"name") ?: @"?"];
        _epGroups = [[UISegmentedControl alloc] initWithItems:names];
        _epGroups.segmentedControlStyle = UISegmentedControlStyleBar;
        _epGroups.selectedSegmentIndex = _panelGroup;
        [_epGroups addTarget:self action:@selector(panelGroupChanged) forControlEvents:UIControlEventValueChanged];
        _epGroupsStrip = [[UIScrollView alloc] init];
        [_epGroupsStrip addSubview:_epGroups];
        [_epPanel addSubview:_epGroupsStrip];
    }
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    layout.minimumInteritemSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(10, 12, 16, 12);
    _epGrid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _epGrid.backgroundColor = [UIColor clearColor];
    _epGrid.dataSource = self;
    _epGrid.delegate = self;
    _epGrid.alwaysBounceVertical = YES;
    [_epGrid registerClass:[CBPlayerEpCell class] forCellWithReuseIdentifier:@"ep"];
    [_epPanel addSubview:_epGrid];
    [self.view insertSubview:_epPanel belowSubview:_top];
    [self setControlsVisible:YES];
    [self layoutEpisodePanel];
    [_epGrid reloadData];
    [self scrollPanelToCurrent];
    [_episodesButton setTitle:@"✕ Tập" forState:UIControlStateNormal];
}

- (void)hideEpisodes {
    [_epPanel removeFromSuperview];
    _epPanel = nil;
    _epGrid = nil;
    _epGroups = nil;
    _epGroupsStrip = nil;
    [_episodesButton setTitle:@"☰ Tập" forState:UIControlStateNormal];
    [self setControlsVisible:YES];
}

- (void)layoutEpisodePanel {
    if (!_epPanel) return;
    // Giữa thanh trên (44) và thanh dưới (88) — thanh nút luôn hiện khi bảng mở
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height, y = 44;
    _epPanel.frame = CGRectMake(0, y, w, h - y - 88);
    CGFloat gy = 0;
    if (_epGroups) {
        [CBTheme layoutSegments:_epGroups inStrip:_epGroupsStrip
                          frame:CGRectMake(12, 10, MIN(w - 24, 140.0 * _epGroups.numberOfSegments), 30)];
        gy = 46;
    }
    _epGrid.frame = CGRectMake(0, gy, w, _epPanel.bounds.size.height - gy);
    [_epGrid.collectionViewLayout invalidateLayout];
}

- (NSArray *)panelEpisodes {
    NSArray *groups = CBArr(_detail, @"groups");
    return _panelGroup < (NSInteger)groups.count ? (CBArr(groups[_panelGroup], @"episodes") ?: @[]) : @[];
}

- (void)panelGroupChanged {
    _panelGroup = _epGroups.selectedSegmentIndex;
    [_epGrid reloadData];
    [self scrollPanelToCurrent];
}

- (void)scrollPanelToCurrent {
    if (_panelGroup != _groupIndex || _index >= (NSInteger)[self panelEpisodes].count) return;
    [_epGrid layoutIfNeeded];
    [_epGrid scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:_index inSection:0]
                    atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return [self panelEpisodes].count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat w = cv.bounds.size.width - 24;
    NSInteger cols = MAX(4, (NSInteger)floor((w + 8) / ([CBTheme isPad] ? 96 : 76)));
    return CGSizeMake(floor((w - 8 * (cols - 1)) / cols), 40);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBPlayerEpCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ep" forIndexPath:ip];
    NSDictionary *ep = [self panelEpisodes][ip.item];
    BOOL current = _panelGroup == _groupIndex && ip.item == _index;
    BOOL watched = [[CBPrefs watchedEpisodes] containsObject:CBStr(ep, @"url") ?: @""];
    cell.label.text = CBStr(ep, @"title");
    cell.label.textColor = current ? [CBTheme focus] : (watched ? [UIColor colorWithWhite:1 alpha:0.45] : [UIColor whiteColor]);
    cell.contentView.layer.borderWidth = current ? 2 : 0;
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [self selectEpisode:ip.item];
}

/// Chọn tập trong bảng (gỡ lỗi: lệnh «ep <số>»); đổi bản nếu đang xem bản khác trong bảng
- (void)selectEpisode:(NSInteger)i {
    NSInteger group = _epPanel ? _panelGroup : _groupIndex;
    [self hideEpisodes];
    if (group == _groupIndex && i == _index) return;
    CBLog(@"Chọn tập %ld (bản %ld) từ bảng tập", (long)i, (long)group);
    if (group != _groupIndex) {
        [self savePosition];
        _groupIndex = group;
    }
    [self openEpisode:i];
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
    // Người đang xem đã hết giờ xem: chưa mở tập, hỏi mã phụ huynh trước
    CBLimitBlock blocked = [CBWatchLimit blocked];
    if (blocked != CBLimitNone) {
        [self limitBlocked:blocked episode:CBStr(eps[i], @"url") ?: _epUrl];
        return;
    }
    [self savePosition];
    [self teardownPlayer];
    // Bỏ server / kết quả hỏi link của tập trước: đang tải tập mới mà bấm «Server» thì không phát nhầm tập cũ dưới tên tập mới
    _source = nil;
    _servers = nil;
    _probeResults = nil;
    _probing = NO;
    _serverIdx = 0;
    _everPlayed = NO;
    _retriedSame = NO;
    _ended = NO;
    _sleepPaused = NO;
    _introSkipped = NO;
    [self loadIntro];
    [self setServerTitle:@"Server"];
    [self clearSubtitles];
    _index = i;
    NSDictionary *ep = eps[i];
    _epUrl = CBStr(ep, @"url");
    NSArray *groups = CBArr(_detail, @"groups");
    NSString *groupName = groups.count > 1 ? [NSString stringWithFormat:@" (%@)", CBStr(groups[_groupIndex], @"name") ?: @""] : @"";
    _titleLabel.text = [NSString stringWithFormat:@"%@ — %@%@", CBStr(_detail, @"title") ?: @"", CBStr(ep, @"title") ?: @"", groupName];
    _prevButton.enabled = i > 0;
    _nextButton.enabled = i + 1 < (NSInteger)eps.count;
    _episodesButton.hidden = eps.count <= 1 && groups.count <= 1;
    [self.view setNeedsLayout];
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
            [self showError:[NSString stringWithFormat:@"Không mở được %@.\n%@", CBStr(ep, @"title") ?: @"tập này", CBCleanError(err)]
                     button:@"Thử lại" action:@selector(retryEpisode)];
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
        // Server bản iOS 6 đã phát được lên đầu (lựa chọn đồng bộ từ TV có thể là trình phát nhúng — iOS 6 không chạy)
        if (worked && [type isEqualToString:worked]) [first insertObject:s atIndex:0];
        else if (pref && [type isEqualToString:pref]) [first addObject:s];
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
    _graceArmed = NO;
    _skipPending = NO;
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

/// Có server sau vị trí k đã trả link phát thẳng được (HLS / tệp video)?
- (BOOL)playableAfter:(NSInteger)k {
    for (NSInteger i = k + 1; i < (NSInteger)_probeResults.count; i++) {
        NSDictionary *v = _probeResults[i];
        if (!CBIsDict(v) || CBBool(v, @"pending", NO)) continue;
        NSString *url = CBStr(v, @"url");
        if (url && (CBBool(v, @"file", NO) || [[[NSURL URLWithString:url].path lowercaseString] hasSuffix:@".m3u8"])) return YES;
    }
    return NO;
}

- (void)advanceProbe:(NSInteger)t {
    if (t != _token || _closed || !_probing) return;
    while (_probeNext < (NSInteger)_servers.count) {
        NSDictionary *v = _probeResults[_probeNext];
        if (!CBIsDict(v) || CBBool(v, @"pending", NO)) {
            if (_skipPending) {
                CBLog(@"Server %@: chờ quá lâu — bỏ qua", CBStr(_servers[_probeNext], @"label"));
                _probeNext++;
                continue;
            }
            if (!_graceArmed && [self playableAfter:_probeNext]) {
                // Server sau đã sẵn link phát được: chờ server đứng trước thêm 2,5 s (thường là trình phát nhúng — chậm, vô ích)
                _graceArmed = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (t != self->_token || !self->_probing) return;
                    self->_skipPending = YES;
                    [self advanceProbe:t];
                });
            }
            NSDictionary *s = _servers[_probeNext];
            [self setServerTitle:CBStr(s, @"label")];
            return;  // chờ server đứng trước trả lời
        }
        NSDictionary *s = _servers[_probeNext];
        NSString *url = CBStr(v, @"url");
        NSString *path = [[NSURL URLWithString:url].path lowercaseString];
        BOOL playable = url && (CBBool(v, @"file", NO) || [path hasSuffix:@".m3u8"]);
        NSString *local = nil, *sub = nil;
        if (playable) {
            NSMutableDictionary *args = [@{@"src": url, @"page": CBStr(_source, @"epUrl") ?: @"", @"hls": @NO} mutableCopy];
            if (CBStr(v, @"subtitle")) args[@"sub"] = CBStr(v, @"subtitle");
            id opened = [CBCore sync:@"media.open" args:args];
            local = CBStr(opened, @"url");
            sub = CBStr(opened, @"subtitle");  // phụ đề rời qua cổng phát nội bộ (WebVTT)
        }
        if (local) {
            _serverIdx = _probeNext;
            [self setServerTitle:CBStr(s, @"label")];
            if (sub) [self loadSubtitles:sub];
            else [self clearSubtitles];
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
    if (_everPlayed) {
        // Đã phát được rồi mới rớt: mất mạng / server chập chờn — không phải lỗi «iOS 6 không phát được»
        [self showError:@"Mất kết nối tới server phát.\nKiểm tra Wi-Fi rồi bấm «Thử lại»." button:@"Thử lại"
                 action:@selector(retryEpisode)];
        return;
    }
    [self showError:@"Không server nào phát được trên iOS 6 (các server còn lại chỉ có trình phát nhúng của trang).\n"
                    @"Chọn lại server hoặc xem ở trang phim khác (vd KKPhim)."
              retry:_servers.count > 0];
}

- (void)debugStreamFailed {
    [self playbackFailed:[NSError errorWithDomain:@"gỡ lỗi" code:-1 userInfo:nil]];
}

- (void)debugPlayedToEnd {
    [_player pause];  // như hết tập thật: AVPlayer dừng ở cuối
    [self playedToEnd:nil];
}

/// «Thử lại»: mở lại tập đang xem (hỏi lại server / link từ đầu), xem tiếp từ chỗ đã lưu
- (void)retryEpisode {
    [self openEpisode:_index];
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
    _timeObs = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4) queue:dispatch_get_main_queue()
                                                usingBlock:^(CMTime time) { [weakSelf tick]; }];
    [_player play];  // tốc độ đã chọn áp khi AVPlayer sẵn sàng (lúc này chưa biết luồng có đổi tốc độ được không)
}

/// Tốc độ AVPlayer chơi được với luồng đang phát: iOS 6 chỉ đổi tốc độ khi canPlayFastForward / canPlaySlowForward (thường là
/// tệp video; luồng HLS thì không) — đặt rate không hỗ trợ thì AVPlayer bỏ qua, đang dừng mà đặt thì không phát lại được
- (BOOL)speedSupported:(float)v {
    if (fabsf(v - 1) < 0.01) return YES;
    return v > 1 ? _item.canPlayFastForward : _item.canPlaySlowForward;
}

- (float)playRate {
    return [self speedSupported:_speed] ? _speed : 1;
}

- (void)resume {
    if (!_player) return;
    _player.rate = [self playRate];
    if (_player.rate <= 0) [_player play];
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
    [_playButton setTitle:@"Phát" forState:UIControlStateNormal];  // không còn gì đang phát (đổi server, lỗi)
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
                if (self->_speed != 1 && self->_player.rate > 0) self->_player.rate = [self playRate];
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
            [self->_playButton setTitle:self->_player.rate > 0 ? @"Tạm dừng" : @"Phát" forState:UIControlStateNormal];
            [self updateNowPlaying];
        }
    });
}

- (void)playbackFailed:(NSError *)error {
    AVPlayerItemErrorLogEvent *ev = _item.errorLog.events.lastObject;
    NSError *under = error.userInfo[NSUnderlyingErrorKey];
    CBLog(@"AVPlayer lỗi (server %@): %@ [%@ %ld; gốc %@ %ld] — log %ld %@ %@",
          CBStr(_servers.count > _serverIdx ? _servers[_serverIdx] : nil, @"label"), error.localizedDescription, error.domain,
          (long)error.code, under.domain, (long)under.code, (long)ev.errorStatusCode, ev.errorDomain, ev.errorComment);
    // Giữ chỗ đang xem rồi thử server sau
    double now = CMTimeGetSeconds(_player.currentTime);
    BOOL wasPlaying = _started;
    if (_started && isfinite(now) && now > 5) _resumeAt = (int)now;
    _seekedResume = NO;
    _started = NO;  // server mới phát được thì tick mới ẩn chữ «Đang tải…», tự ẩn thanh nút, ghi nhớ server
    [self teardownPlayer];
    // Đang phát thì rớt (Wi-Fi chập chờn): hỏi lại link chính server này một lần trước khi sang server khác
    if (wasPlaying && !_retriedSame && _serverIdx < (NSInteger)_servers.count) {
        _retriedSame = YES;
        CBLog(@"Server %@ rớt giữa chừng — thử lại server này", CBStr(_servers[_serverIdx], @"label"));
        _probeResults = nil;
        [self tryServer:_serverIdx token:++_token];
        return;
    }
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
        BOOL more = self->_index + 1 < (NSInteger)[self episodes].count;
        if (self->_sleepEndOfEp) {  // hẹn «hết tập này»: dừng ở đây, không tự chuyển tập
            self->_sleepEndOfEp = NO;
            self->_ended = YES;
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            [self showError:@"Đã dừng theo hẹn giờ (hết tập)." button:more ? @"Tập sau »" : nil action:@selector(nextEpisode)];
            return;
        }
        if ([CBPrefs autoNext] && more) {
            CBLog(@"Hết tập — tự chuyển tập sau");
            [self openEpisode:self->_index + 1];
        } else {
            self->_ended = YES;
            if (more) [self showError:@"Hết tập." button:@"Tập sau »" action:@selector(nextEpisode)];
            else [self showError:@"Hết phim." button:nil action:NULL];
        }
    });
}

- (void)tick {
    if (!_player || _closed) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    double dur = CBDuration(_item);
    [self updateSubtitle:now];
    if ((_ended || _sleepPaused) && _player.rate > 0) {  // phát lại sau «Hết tập.» / hẹn giờ dừng (tua lùi, màn khoá…)
        _ended = NO;
        if (_sleepPaused) [UIApplication sharedApplication].idleTimerDisabled = YES;
        _sleepPaused = NO;
        [self hideStatus];
    }
    // Đoạn mở đầu đã đánh dấu: tới đó thì tự tua qua (mỗi tập một lần — tua lùi xem lại thì thôi)
    if (_started && !_introSkipped && _introEnd > _introStart && _introStart >= 0 && _player.rate > 0 && isfinite(now) &&
        now >= _introStart - 0.5 && now < _introEnd - 2) {
        _introSkipped = YES;
        CBLog(@"Bỏ qua đoạn mở đầu %d–%ds", _introStart, _introEnd);
        [self seekTo:_introEnd];
        [self showToast:@"Bỏ qua đoạn mở đầu"];
    }
    if (_sleepAt && CBNowMs() >= _sleepAt) [self sleepNow:@"Đã tạm dừng theo hẹn giờ tắt."];
    if (!_started && now > 0.5 && _player.rate > 0) {
        _started = YES;
        _everPlayed = YES;
        [self hideStatus];
        [self setControlsVisible:NO];
        NSString *type = _serverIdx < (NSInteger)_servers.count ? CBStr(_servers[_serverIdx], @"type") : nil;
        if (type) [CBPrefs set:[self workedKey:_source] value:type];
    }
    if (++_tickCount % 2) return;  // phần dưới mỗi 0,5 giây (nhịp 0,25 giây chỉ để phụ đề khớp hơn)
    if (!_dragging && !_seeking) {
        _timeLabel.text = [CBTheme time:now];
        _durLabel.text = [CBTheme time:dur];
        _slider.value = isfinite(dur) && dur > 0 ? (float)(now / dur) : 0;
    }
    if (_started && CBNowMs() - _lastSave > 10000) [self savePosition];
    [self checkLimit];
}

#pragma mark - Giới hạn giờ xem

/// Mỗi lần đọc trạng thái: đếm giờ xem; sắp hết giờ thì nhắc, hết giờ thì dừng phim, thoát và hỏi mã PIN phụ huynh
- (void)checkLimit {
    [CBWatchLimit tick:_started && _player.rate > 0];
    CBLimitBlock b = [CBWatchLimit blocked];
    if (b == CBLimitNone) {
        NSInteger r = [CBWatchLimit remaining];
        if (_started && !_limitWarned && r != NSNotFound && r > 0 && r <= 300) {
            _limitWarned = YES;
            [CBTheme toast:[NSString stringWithFormat:@"Còn %@ xem hôm nay (%@).", [CBWatchLimit minutesText:r],
                                                     CBStr([CBPrefs currentProfile], @"name") ?: @""]];
        }
        return;
    }
    [_player pause];
    [self limitBlocked:b episode:_epUrl];
}

- (void)limitBlocked:(CBLimitBlock)b episode:(NSString *)ep {
    if (_closed) return;
    if (!_appeared) {
        _pendingBlock = b;
        _blockedEp = ep;
        return;
    }
    UIViewController *host = self.presentingViewController;
    NSString *film = _filmUrl;
    [self close];
    [CBParental limitReached:b film:film episode:ep host:host];
}

- (void)savePosition {
    if (!_started || !_player || !_epUrl) return;
    double now = CMTimeGetSeconds(_player.currentTime);
    double dur = CBDuration(_item);
    if (!isfinite(dur)) dur = 0;
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
    if (_player.rate > 0) {
        [_player pause];
    } else {
        double now = CMTimeGetSeconds(_player.currentTime), dur = CBDuration(_item);
        if (_ended && isfinite(dur) && isfinite(now) && now >= dur - 1) [self seekTo:0];  // «Phát» ở cuối tập: xem lại từ đầu
        [self resume];
    }
    [self setControlsVisible:YES];
}

- (void)seekTo:(double)seconds {
    if (!_player) return;
    // Chưa tua xong thì tick không đặt lại thanh tua theo thời gian cũ (núm tua nhảy về chỗ cũ rồi mới tới)
    _seeking = YES;
    _cueIdx = 0;
    __weak CBPlayerViewController *weakSelf = self;
    [_player seekToTime:CMTimeMakeWithSeconds(MAX(0, seconds), 600) completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CBPlayerViewController *s = weakSelf;
            if (s) s->_seeking = NO;
        });
    }];
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
    double dur = CBDuration(_item);
    if (isfinite(dur)) _timeLabel.text = [CBTheme time:dur * _slider.value];
}

- (void)sliderUp {
    _dragging = NO;
    double dur = CBDuration(_item);
    if (isfinite(dur)) [self seekTo:dur * _slider.value];
    [self setControlsVisible:YES];
}

- (void)nextEpisode {
    if (_index + 1 < (NSInteger)[self episodes].count) [self openEpisode:_index + 1];
}

- (void)previousEpisode {
    if (_index > 0) [self openEpisode:_index - 1];
}

- (void)showServers {
    if (!_servers.count) {
        [self showToast:@"Đang tìm server…"];
        return;
    }
    __weak CBPlayerViewController *weakSelf = self;
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < _servers.count; i++) {
        NSString *label = CBStr(_servers[i], @"label") ?: @"?";
        [items addObject:@[(NSInteger)i == _serverIdx ? [@"✓ " stringByAppendingString:label] : label,
                           ^{ [weakSelf selectServer:(NSInteger)i]; }]];
    }
    [self sheet:@"Chọn server" items:items];
}

#pragma mark - Menu «⋯»

/// Bảng chọn tự vẽ từ danh sách @[@[tên, khối], …] — giữa màn, nền tối; chạm ra ngoài / «Huỷ» để đóng
- (void)sheet:(NSString *)title items:(NSArray *)items {
    [self hideMenuPanel];
    NSMutableArray *copied = [NSMutableArray array];
    for (NSArray *it in items) [copied addObject:@[it[0], [it[1] copy]]];
    _menuItems = copied;
    _menuPanel = [[UIView alloc] initWithFrame:self.view.bounds];
    _menuPanel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _menuPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *outside = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideMenuPanel)];
    outside.delegate = self;
    [_menuPanel addGestureRecognizer:outside];
    _menuBox = [[UIScrollView alloc] init];
    _menuBox.backgroundColor = [CBTheme surface];
    _menuBox.layer.cornerRadius = 12;
    _menuBox.alwaysBounceVertical = NO;
    [_menuPanel addSubview:_menuBox];
    _menuTitle = [self overlayLabel:[CBTheme bold:15]];
    _menuTitle.textColor = [CBTheme dim];
    _menuTitle.textAlignment = NSTextAlignmentCenter;
    _menuTitle.text = title;
    [_menuBox addSubview:_menuTitle];
    _menuButtons = [NSMutableArray array];
    for (NSUInteger i = 0; i <= _menuItems.count; i++) {
        BOOL cancel = i == _menuItems.count;
        UIButton *b = [CBTheme button:cancel ? @"Huỷ" : _menuItems[i][0] primary:NO];
        b.tag = cancel ? -1 : (NSInteger)i;
        b.titleLabel.font = cancel ? [CBTheme bold:16] : [CBTheme font:16];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.7;
        if (cancel) [b setTitleColor:[CBTheme dim] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(menuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_menuBox addSubview:b];
        [_menuButtons addObject:b];
    }
    [self.view addSubview:_menuPanel];
    [self layoutMenuPanel];
}

- (void)layoutMenuPanel {
    if (!_menuPanel) return;
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat bw = MIN(400, w - 40), pad = 12, rowH = 44, gap = 6;
    CGFloat y = pad;
    _menuTitle.frame = CGRectMake(pad, y, bw - 2 * pad, _menuTitle.text.length ? 24 : 0);
    y += _menuTitle.text.length ? 30 : 0;
    for (UIButton *b in _menuButtons) {
        if (b.tag < 0) y += 4;  // «Huỷ» tách khỏi các mục
        b.frame = CGRectMake(pad, y, bw - 2 * pad, rowH);
        y += rowH + gap;
    }
    CGFloat contentH = y - gap + pad;
    CGFloat bh = MIN(contentH, h - 24);
    _menuBox.frame = CGRectMake((w - bw) / 2, (h - bh) / 2, bw, bh);
    _menuBox.contentSize = CGSizeMake(bw, contentH);
}

- (void)menuButtonTapped:(UIButton *)b {
    [self pressMenuItem:b.tag];
}

- (BOOL)pressMenuItem:(NSInteger)index {
    if (!_menuPanel) return NO;
    NSArray *items = _menuItems;
    [self hideMenuPanel];
    if (index >= 0 && index < (NSInteger)items.count) ((void (^)(void))items[index][1])();
    return YES;
}

- (void)hideMenuPanel {
    [_menuPanel removeFromSuperview];
    _menuPanel = nil;
    _menuBox = nil;
    _menuTitle = nil;
    _menuButtons = nil;
    _menuItems = nil;
}

- (NSString *)speedText:(float)v {
    return [[NSString stringWithFormat:@"%g×", v] stringByReplacingOccurrencesOfString:@"." withString:@","];
}

- (double)now {
    double now = _player ? CMTimeGetSeconds(_player.currentTime) : NAN;
    return isfinite(now) ? now : 0;
}

- (void)showMenu {
    __weak CBPlayerViewController *weakSelf = self;
    NSMutableArray *items = [NSMutableArray array];
    NSString *speed = [NSString stringWithFormat:@"Tốc độ: %@", [self speedText:[self playRate]]];
    if (_item && !_item.canPlayFastForward && !_item.canPlaySlowForward) speed = @"Tốc độ: 1× (server này không đổi được)";
    [items addObject:@[speed, ^{ [weakSelf showSpeeds]; }]];
    // Đoạn mở đầu: đánh dấu đầu → đánh dấu hết → các tập sau tự tua qua
    int now = (int)[self now];
    if (_introStart < 0) {
        [items addObject:@[[NSString stringWithFormat:@"Đánh dấu đầu đoạn mở đầu (%@)", [CBTheme time:now]],
                           ^{ [weakSelf markIntroStart:now]; }]];
    } else if (_introEnd <= _introStart) {
        [items addObject:@[[NSString stringWithFormat:@"Đánh dấu hết đoạn mở đầu (%@)", [CBTheme time:now]],
                           ^{ [weakSelf markIntroEnd:now]; }]];
    } else {
        [items addObject:@[[NSString stringWithFormat:@"Bỏ đánh dấu đoạn mở đầu (%@–%@)", [CBTheme time:_introStart],
                                                   [CBTheme time:_introEnd]], ^{ [weakSelf clearIntro]; }]];
    }
    NSString *sleep = @"Hẹn giờ tắt…";
    if (_sleepEndOfEp) sleep = @"Hẹn giờ tắt: hết tập này";
    else if (_sleepAt) sleep = [NSString stringWithFormat:@"Hẹn giờ tắt: còn %lld phút", MAX(1, (_sleepAt - CBNowMs() + 59999) / 60000)];
    [items addObject:@[sleep, ^{ [weakSelf showSleep]; }]];
    [items addObject:@[@"Tải lại tập này", ^{ [weakSelf reloadEpisode]; }]];
    [self sheet:CBStr(_detail, @"title") items:items];
}

- (void)showSpeeds {
    __weak CBPlayerViewController *weakSelf = self;
    NSMutableArray *items = [NSMutableArray array];
    for (NSNumber *v in @[@0.75, @1, @1.25, @1.5, @2]) {
        NSString *t = [self speedText:v.floatValue];
        if (fabsf(v.floatValue - _speed) < 0.01) t = [@"✓ " stringByAppendingString:t];
        [items addObject:@[t, ^{ [weakSelf setSpeed:v.floatValue]; }]];
    }
    [self sheet:@"Tốc độ phát" items:items];
}

- (void)setSpeed:(float)speed {
    _speed = MIN(2, MAX(0.5f, speed));
    BOOL ok = [self speedSupported:_speed];
    if (_player.rate > 0) _player.rate = [self playRate];
    CBLog(@"Tốc độ phát %.2f%@ (nhanh %d, chậm %d)", _speed, ok ? @"" : @" — luồng này không đổi được", _item.canPlayFastForward,
          _item.canPlaySlowForward);
    if (ok) [self showToast:[@"Tốc độ " stringByAppendingString:[self speedText:_speed]]];
    else [CBTheme toast:@"Server này không đổi được tốc độ trên iOS 6 (chỉ tệp video đổi được, luồng HLS thì không) — vẫn phát 1×."];
}

- (NSString *)introKey {
    return [@"intro@" stringByAppendingString:_filmUrl ?: @""];
}

/// «đầu,hết» (giây; hết = -1: mới đánh dấu đầu) — như Prefs.Intro của bản Windows
- (void)loadIntro {
    _introStart = _introEnd = -1;
    id v = [CBPrefs get:[self introKey]];
    NSArray *p = CBIsStr(v) ? [v componentsSeparatedByString:@","] : nil;
    if (!p.count || ![p[0] length]) return;
    _introStart = [p[0] intValue];
    _introEnd = p.count > 1 ? [p[1] intValue] : -1;
}

- (void)markIntroStart:(int)s {
    _introStart = s;
    _introEnd = -1;
    [CBPrefs set:[self introKey] value:[NSString stringWithFormat:@"%d,-1", s]];
    [CBTheme toast:[NSString stringWithFormat:@"Đã đánh dấu đầu đoạn mở đầu (%@). Tới chỗ hết đoạn mở đầu thì đánh dấu hết.",
                                              [CBTheme time:s]]];
}

- (void)markIntroEnd:(int)e {
    if (e <= _introStart + 3) {
        [CBTheme toast:@"Mốc hết phải sau mốc đầu — tua tới chỗ hết đoạn mở đầu rồi đánh dấu lại."];
        return;
    }
    _introEnd = e;
    _introSkipped = YES;  // tập đang xem đã qua đoạn đó
    [CBPrefs set:[self introKey] value:[NSString stringWithFormat:@"%d,%d", _introStart, e]];
    [CBTheme toast:[NSString stringWithFormat:@"Đã lưu đoạn mở đầu %@–%@ — các tập sau tự bỏ qua.", [CBTheme time:_introStart],
                                              [CBTheme time:e]]];
}

- (void)clearIntro {
    _introStart = _introEnd = -1;
    [CBPrefs set:[self introKey] value:nil];
    [CBTheme toast:@"Đã bỏ đánh dấu đoạn mở đầu."];
}

- (void)showSleep {
    __weak CBPlayerViewController *weakSelf = self;
    NSMutableArray *items = [NSMutableArray array];
    for (NSNumber *m in @[@15, @30, @60, @90]) {
        [items addObject:@[[NSString stringWithFormat:@"%@ phút", m], ^{ [weakSelf setSleepAfter:m.intValue * 60 endOfEpisode:NO]; }]];
    }
    [items addObject:@[@"Hết tập này", ^{ [weakSelf setSleepAfter:0 endOfEpisode:YES]; }]];
    if (_sleepAt || _sleepEndOfEp) [items addObject:@[@"Tắt hẹn giờ", ^{ [weakSelf setSleepAfter:0 endOfEpisode:NO]; }]];
    [self sheet:@"Hẹn giờ tắt" items:items];
}

- (void)setSleepAfter:(NSTimeInterval)seconds endOfEpisode:(BOOL)endOfEpisode {
    _sleepEndOfEp = endOfEpisode;
    _sleepAt = seconds > 0 ? CBNowMs() + (long long)(seconds * 1000) : 0;
    CBLog(@"Hẹn giờ tắt: %@", endOfEpisode ? @"hết tập" : seconds > 0 ? [NSString stringWithFormat:@"%.0fs", seconds] : @"tắt");
    [self showToast:endOfEpisode ? @"Dừng khi hết tập" : seconds > 0 ? [NSString stringWithFormat:@"Dừng sau %.0f phút", ceil(seconds / 60)]
                                                         : @"Đã tắt hẹn giờ"];
}

/// Hết giờ hẹn: tạm dừng, cho máy tự khoá màn hình (không giữ sáng nữa), «Xem tiếp» để phát lại
- (void)sleepNow:(NSString *)text {
    _sleepAt = 0;
    [_player pause];
    [self savePosition];
    _sleepPaused = YES;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    CBLog(@"Hẹn giờ tắt: tạm dừng");
    [self showError:text button:@"Xem tiếp" action:@selector(togglePlay)];
}

- (void)reloadEpisode {
    [self savePosition];
    [self openEpisode:_index];
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
    _retriedSame = NO;
    _ended = NO;
    _probeResults = nil;  // lượt hỏi cũ (mã cũ) bị bỏ — hỏi lại
    [self tryServer:index token:++_token];
}

#pragma mark - Phụ đề rời

- (void)clearSubtitles {
    _subToken++;
    _cues = nil;
    _cueIdx = 0;
    _subLabel.hidden = YES;
    _subLabel.text = nil;
}

/// Tải tệp phụ đề (WebVTT / SRT) từ cổng phát nội bộ, đọc ở luồng nền
- (void)loadSubtitles:(NSString *)url {
    [self clearSubtitles];
    NSInteger t = _subToken;
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:30];
    if (!req.URL) return;
    __weak CBPlayerViewController *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:req queue:[[NSOperationQueue alloc] init]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (!text && data.length) text = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
        NSArray *cues = text ? CBParseSubtitles(text) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            CBPlayerViewController *s = weakSelf;
            if (!s || t != s->_subToken || s->_closed) return;
            CBLog(@"Phụ đề: %lu câu%@", (unsigned long)cues.count, err ? [@" — lỗi " stringByAppendingString:err.localizedDescription] : @"");
            s->_cues = cues.count ? cues : nil;
            s->_cueIdx = 0;
        });
    }];
}

- (void)updateSubtitle:(double)now {
    if (!_cues || !isfinite(now)) return;
    NSUInteger n = _cues.count;
    if (_cueIdx >= n || [_cues[_cueIdx][@"s"] doubleValue] > now) _cueIdx = 0;  // tua lùi
    while (_cueIdx + 1 < n && [_cues[_cueIdx + 1][@"s"] doubleValue] <= now) _cueIdx++;
    NSDictionary *c = _cues[_cueIdx];
    NSString *text = ([c[@"s"] doubleValue] <= now && now < [c[@"e"] doubleValue]) ? c[@"t"] : nil;
    if ([text isEqualToString:_subLabel.text] || (!text && _subLabel.hidden)) return;
    _subLabel.text = text;
    _subLabel.hidden = !text;
    [self layoutSubtitle];
}

- (void)layoutSubtitle {
    if (_subLabel.hidden || !_subLabel.text.length) return;
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat maxW = w * 0.86;
    CGFloat th = [CBTheme heightOf:_subLabel.text font:_subLabel.font width:maxW - 16];
    CGSize one = [_subLabel.text sizeWithFont:_subLabel.font];
    CGFloat lw = MIN(maxW, ceil(one.width) + 16);
    // Trên thanh nút dưới khi thanh đang hiện
    CGFloat bottom = _bottom.alpha > 0.5 ? 88 + 8 : 16;
    _subLabel.frame = CGRectMake((w - lw) / 2, h - bottom - th - 8, lw, th + 8);
}

- (void)close {
    if (_closed) return;
    [self savePosition];
    [CBWatchLimit flush];
    _closed = YES;
    _token++;
    [self teardownPlayer];
    [CBCore sync:@"media.closeAll" args:nil];
    [CBSync setPlaying:NO];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateNowPlaying {
    NSArray *eps = [self episodes];
    NSString *ep = _index < (NSInteger)eps.count ? CBStr(eps[_index], @"title") : nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = ep ?: @"";
    info[MPMediaItemPropertyArtist] = CBStr(_detail, @"title") ?: @"Côn Bằng TV";
    if (isfinite(CBDuration(_item))) {
        info[MPMediaItemPropertyPlaybackDuration] = @(CBDuration(_item));
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(_player.currentTime));
        info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlay]; break;
        case UIEventSubtypeRemoteControlPlay: [self resume]; break;
        case UIEventSubtypeRemoteControlPause: [_player pause]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self nextEpisode]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self previousEpisode]; break;
        default: break;
    }
}

- (NSString *)statusLine {
    double now = _player ? CMTimeGetSeconds(_player.currentTime) : 0;
    AVPlayerItemAccessLogEvent *ev = _item.accessLog.events.lastObject;
    return [NSString stringWithFormat:@"%@ | %@ / %@ | rate %.2f (chọn %.2f) | server %@ | đệm %@ | bitrate %.0f kbps | khựng %ld | RAM %.0f MB",
            _titleLabel.text, [CBTheme time:now], [CBTheme time:CBDuration(_item)], _player.rate, _speed,
            CBStr(_servers.count > _serverIdx ? _servers[_serverIdx] : nil, @"label"),
            _item.playbackLikelyToKeepUp ? @"đủ" : @"thiếu", ev.observedBitrate / 1000, (long)ev.numberOfStalls, CBResidentMB()];
}

@end
