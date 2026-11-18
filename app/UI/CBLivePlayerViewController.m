#import "CBLivePlayerViewController.h"
#import "CBCompat.h"
#import "CBCore.h"
#import "CBImages.h"
#import "CBIPTV.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBFloatBridge.h"
#import "CBMiniPlayer.h"
#import "CBNavController.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBSync.h"
#import "CBTVGuideViewController.h"
#import "CBTheme.h"
#import "CBWatchLimit.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>

static void *kLiveKVO = &kLiveKVO;

@interface CBLiveVideoView : UIView
@end
@implementation CBLiveVideoView
+ (Class)layerClass {
    return [AVPlayerLayer class];
}
@end

/// iOS 5: xoay giao diện theo ý app (như CBPlayerViewController)
static void CBLiveForceOrientation(UIInterfaceOrientation o) {
    SEL s = NSSelectorFromString(@"setOrientation:animated:");
    UIDevice *d = [UIDevice currentDevice];
    if ([d respondsToSelector:s]) ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(d, s, (NSInteger)o, YES);
}

@interface CBLivePlayerViewController () <CBMiniPlayable, CBFloatPlayable, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@end

@implementation CBLivePlayerViewController {
    NSArray *_channels;
    NSInteger _index, _source;
    AVPlayer *_player;
    AVPlayerItem *_item;
    BOOL _observing;
    CBLiveVideoView *_video;
    UIView *_top, *_bottom, *_track, *_fill;
    UIButton *_closeButton, *_guideButton, *_sourceButton, *_channelsButton, *_prevButton, *_playButton, *_nextButton, *_liveButton;
    UIButton *_miniButton;   // «Thu nhỏ»: hình kênh vào khung nhỏ ở góc, xem tiếp trong lúc lướt app (CBMiniPlayer); radio thì ẩn
    UIButton *_floatButton;  // «Hình nổi»: khung nổi trên màn hình chính / app khác (tinh chỉnh CBFloat); radio thì ẩn
    CBRoundLabel *_badge;   // «TRỰC TIẾP» / «CHẬM m:ss» — màu nền bo góc: fillColor
    UILabel *_titleLabel, *_progLabel, *_timeLabel, *_nextLabel, *_status;
    UIActivityIndicatorView *_spinner;
    UIButton *_retryButton, *_skipButton;
    UITableView *_panel;
    BOOL _panelOpen, _controlsVisible;
    NSTimer *_tick, *_hideTimer;
    NSInteger _token, _ticks;
    BOOL _closed, _started, _appeared, _retriedReset, _baseSet;
    BOOL _listChecked;   // kênh thường hỏng hết nguồn: đã tải lại danh sách tìm link mới (một lần mỗi lần mở / mỗi lần phát được)
    NSMutableDictionary *_sniffed;   // địa chỉ → kết quả media.sniff (+ at), dùng lại 10 phút
    long long _playAt;      // lúc đưa luồng cho AVPlayer (canh «quá lâu chưa lên hình»)
    NSString *_liveHint;    // gợi ý của lõi khi máy không lên hình (# cb-hint: — vd hình PAFF)
    // Đài radio: thẻ logo / tên đài / bài đang phát thay cho hình (luồng tiếng liền qua r/… của lõi, hoặc HLS chỉ có tiếng)
    BOOL _radio;
    NSString *_radioToken;   // phiên radio của lõi (media.radioInfo — tên bài ICY); nil = HLS chỉ có tiếng
    NSString *_radioTitle, *_radioDesc;
    UIView *_radioCard;
    UIImageView *_radioLogo;
    UILabel *_radioIcon, *_radioName, *_radioSong, *_radioInfo;
    NSString *_radioLogoUrl;
    long long _startedAt;
    NSInteger _reopens;   // số lần luồng tự dừng rồi mở lại (cùng nguồn)
    double _baseBehind;   // độ trễ tự nhiên sau mép trực tiếp lúc vừa phát (AVPlayer phát sau mép ~3 đoạn)
    NSString *_srcUrl;
}

- (instancetype)initWithChannels:(NSArray *)channels index:(NSInteger)index {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _channels = channels ?: @[];
        _index = MAX(0, MIN(index, (NSInteger)_channels.count - 1));
        _panelOpen = NO;  // mở kênh là xem toàn màn hình; bảng kênh chỉ hiện khi bấm «☰ Kênh» (anh báo: iPad luôn hiện bảng)
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)dealloc {
    [self teardownPlayer];
    [_tick invalidate];
    [_hideTimer invalidate];
    _panel.delegate = nil;   // iOS 5 / 6: delegate của UITableView không tự về nil
    _panel.dataSource = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSDictionary *)channel {
    return _index >= 0 && _index < (NSInteger)_channels.count ? _channels[_index] : nil;
}

#pragma mark - Giao diện

- (UIButton *)barButton:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme text] forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
    b.titleLabel.font = [CBTheme bold:[CBTheme isPad] ? 17 : 15];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UILabel *)label:(UIFont *)font {
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
    [CBMiniPlayer closeOthers:self];   // mỗi lúc chỉ phát một: đóng trình phát đang thu nhỏ (nếu có)
    [CBSync setPlaying:YES];
    BOOL pad = [CBTheme isPad];
    _video = [[CBLiveVideoView alloc] initWithFrame:self.view.bounds];
    _video.backgroundColor = [UIColor blackColor];
    [(AVPlayerLayer *)_video.layer setVideoGravity:[CBPrefs videoFill] ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect];
    [self.view addSubview:_video];

    // Thẻ radio nằm trong khung hình (không nhận chạm: chạm / vuốt vẫn tới khung hình — hiện nút, đổi kênh)
    _radioCard = [[UIView alloc] init];
    _radioCard.userInteractionEnabled = NO;
    _radioCard.hidden = YES;
    _radioLogo = [[UIImageView alloc] init];
    _radioLogo.contentMode = UIViewContentModeScaleAspectFit;
    _radioLogo.backgroundColor = CBRGB(0x1A1D22);
    _radioLogo.layer.cornerRadius = 12;
    _radioLogo.clipsToBounds = YES;
    _radioIcon = [self label:[UIFont systemFontOfSize:pad ? 72 : 48]];
    _radioIcon.text = @"📻";
    _radioIcon.textAlignment = NSTextAlignmentCenter;
    _radioName = [self label:[CBTheme bold:pad ? 24 : 18]];
    _radioName.textAlignment = NSTextAlignmentCenter;
    _radioSong = [self label:[CBTheme bold:pad ? 18 : 15]];
    _radioSong.textColor = [CBTheme brand];
    _radioSong.textAlignment = NSTextAlignmentCenter;
    _radioSong.numberOfLines = 2;
    _radioInfo = [self label:[CBTheme font:13]];
    _radioInfo.textColor = [CBTheme dim];
    _radioInfo.textAlignment = NSTextAlignmentCenter;
    for (UIView *v in @[_radioLogo, _radioIcon, _radioName, _radioSong, _radioInfo]) [_radioCard addSubview:v];
    [_video addSubview:_radioCard];

    UIColor *shade = [UIColor colorWithWhite:0 alpha:0.62];
    _top = [[UIView alloc] init];
    _top.backgroundColor = shade;
    [self.view addSubview:_top];
    _closeButton = [self barButton:@"✕ Đóng" action:@selector(close)];
    _miniButton = [self barButton:@"Thu nhỏ" action:@selector(minimize)];
    _miniButton.hidden = ![CBMiniPlayer available];
    _floatButton = [self barButton:@"Hình nổi" action:@selector(floatOut)];
    _floatButton.hidden = ![CBFloatBridge available];
    if (!pad) {   // iPhone ngang hẹp: hai nút này là biểu tượng, chừa chỗ cho tên kênh
        for (UIButton *b in @[_miniButton, _floatButton]) {
            b.accessibilityLabel = [b titleForState:UIControlStateNormal];
            [b setTitle:nil forState:UIControlStateNormal];
            [b setImage:[CBMiniPlayer barIcon:b == _miniButton ? @"mini" : @"float"] forState:UIControlStateNormal];
            b.showsTouchWhenHighlighted = YES;
        }
    }
    _guideButton = [self barButton:@"Lịch" action:@selector(openGuide)];
    _sourceButton = [self barButton:@"Nguồn 1/1" action:@selector(nextSource)];
    _channelsButton = [self barButton:@"☰ Kênh" action:@selector(toggleChannels)];
    _titleLabel = [self label:[CBTheme bold:pad ? 16 : 14]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _badge = [CBTheme roundLabel:nil radius:4];   // màu nền gán sau (đỏ = đang phát); nền bo vẽ vào nhãn, không lớp bo góc trên video
    _badge.font = [CBTheme bold:11];
    _badge.textAlignment = NSTextAlignmentCenter;
    _badge.textColor = [UIColor whiteColor];
    for (UIView *v in @[_closeButton, _miniButton, _floatButton, _guideButton, _sourceButton, _channelsButton, _titleLabel, _badge])
        [_top addSubview:v];

    _bottom = [[UIView alloc] init];
    _bottom.backgroundColor = shade;
    [self.view addSubview:_bottom];
    _progLabel = [self label:[CBTheme bold:pad ? 18 : 15]];
    _timeLabel = [self label:[CBTheme font:13]];
    _timeLabel.textColor = [CBTheme dim];
    _nextLabel = [self label:[CBTheme font:13]];
    _nextLabel.textColor = [CBTheme dim];
    _nextLabel.textAlignment = NSTextAlignmentRight;
    _track = [[UIView alloc] init];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    _fill = [[UIView alloc] init];
    _fill.backgroundColor = [CBTheme brand];
    [_track addSubview:_fill];
    _prevButton = [self barButton:@"« Kênh trước" action:@selector(previousChannel)];
    _playButton = [self barButton:@"Tạm dừng" action:@selector(togglePlay)];
    _nextButton = [self barButton:@"Kênh sau »" action:@selector(nextChannel)];
    _liveButton = [CBTheme button:@"Về trực tiếp" primary:YES];
    _liveButton.titleLabel.font = [CBTheme bold:14];
    [_liveButton addTarget:self action:@selector(goLive) forControlEvents:UIControlEventTouchUpInside];
    _liveButton.hidden = YES;
    for (UIView *v in @[_progLabel, _timeLabel, _nextLabel, _track, _prevButton, _playButton, _nextButton, _liveButton]) [_bottom addSubview:v];

    _panel = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _panel.backgroundColor = CBRGB(0x15181C);
    _panel.separatorColor = CBRGB(0x2A2F36);
    _panel.dataSource = self;
    _panel.delegate = self;
    _panel.rowHeight = pad ? 58 : 50;
    _panel.hidden = !_panelOpen;
    [self.view addSubview:_panel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
    _status = [self label:[CBTheme font:16]];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 0;
    [self.view addSubview:_status];
    _retryButton = [CBTheme button:@"Thử lại" primary:YES];
    [_retryButton addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.hidden = YES;
    [self.view addSubview:_retryButton];
    _skipButton = [CBTheme button:@"Kênh sau »" primary:NO];
    [_skipButton addTarget:self action:@selector(nextChannel) forControlEvents:UIControlEventTouchUpInside];
    _skipButton.hidden = YES;
    [self.view addSubview:_skipButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    tap.delegate = self;
    [_video addGestureRecognizer:tap];
    UISwipeGestureRecognizer *up = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(nextChannel)];
    up.direction = UISwipeGestureRecognizerDirectionUp;
    [_video addGestureRecognizer:up];
    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(previousChannel)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [_video addGestureRecognizer:down];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(guideChanged) name:CBIPTVChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteringForeground)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    _tick = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self setControlsVisible:YES];
    [self openSource];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = !_radio;   // radio: máy tự tắt màn hình, nghe tiếp khi khoá máy
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _appeared = YES;
    if ([CBImages lowRam]) [CBImages purgeOffscreen];
    if (CBOldIOS() && ![CBTheme isPad] && UIInterfaceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation)) {
        CBLiveForceOrientation(UIInterfaceOrientationLandscapeRight);
    }
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    [self scrollPanelToCurrent];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.presentedViewController) return;  // mở «Lịch» đè lên: vẫn đang xem
    if (CBOldIOS() && ![CBTheme isPad] && self.isBeingDismissed) CBLiveForceOrientation(UIInterfaceOrientationPortrait);
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

// iOS 5 hỏi hàm này; màn trình bày đè lên phải tự khai báo (xem CBCompat)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return ([self supportedInterfaceOrientations] & (1u << o)) != 0;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (![CBTheme isPad]) return UIInterfaceOrientationLandscapeRight;
    return [UIApplication sharedApplication].statusBarOrientation;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL pad = [CBTheme isPad];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat panelW = _panelOpen ? (pad ? 300 : 230) : 0, cw = w - panelW;
    if (_video.superview == self.view) _video.frame = CGRectMake(0, 0, cw, h);  // bảng kênh mở: hình thu vào phần còn lại (đang thu nhỏ: hình ở khung nhỏ)
    _panel.frame = CGRectMake(cw, 0, panelW, h);

    CGFloat topH = pad ? 52 : 44;
    _top.frame = CGRectMake(0, 0, cw, topH);
    CGFloat x = 6;
    CGSize cs = [_closeButton sizeThatFits:CGSizeMake(200, topH)];
    _closeButton.frame = CGRectMake(x, 0, cs.width + 16, topH);
    CGFloat leftEnd = CGRectGetMaxX(_closeButton.frame);
    _miniButton.hidden = ![CBMiniPlayer available] || _radio;   // radio: không có hình, nghe tiếp khi ra ngoài sẵn rồi
    _floatButton.hidden = ![CBFloatBridge available] || _radio;
    for (UIButton *b in @[_miniButton, _floatButton]) {
        if (b.hidden) continue;
        CGSize ms = [b sizeThatFits:CGSizeMake(200, topH)];
        b.frame = CGRectMake(leftEnd, 0, MAX(40, ms.width + 16), topH);
        leftEnd = CGRectGetMaxX(b.frame);
    }
    CGFloat right = cw - 6;
    for (UIButton *b in @[_channelsButton, _sourceButton, _guideButton]) {
        if (b.hidden) continue;
        CGSize s = [b sizeThatFits:CGSizeMake(200, topH)];
        right -= s.width + 16;
        b.frame = CGRectMake(right, 0, s.width + 16, topH);
    }
    CGFloat titleL = leftEnd + 8, titleR = right - 8;
    CGSize bs = [_badge.text ?: @"" sizeWithFont:_badge.font];
    CGFloat badgeW = bs.width + 12;
    CGSize ts = [_titleLabel.text ?: @"" sizeWithFont:_titleLabel.font];
    CGFloat avail = MAX(40, titleR - titleL - badgeW - 8), tw = MIN(ts.width, avail);
    CGFloat startX = titleL + (titleR - titleL - tw - 8 - badgeW) / 2;
    _titleLabel.frame = CGRectMake(startX, 0, tw, topH);
    _badge.frame = CGRectMake(startX + tw + 8, (topH - 20) / 2, badgeW, 20);

    CGFloat bh = pad ? 124 : 104;
    _bottom.frame = CGRectMake(0, h - bh, cw, bh);
    CGFloat pad16 = pad ? 18 : 12;
    CGFloat nextW = MIN(cw * 0.42, [_nextLabel.text ?: @"" sizeWithFont:_nextLabel.font].width + 4);
    _progLabel.frame = CGRectMake(pad16, 8, cw - pad16 * 2 - nextW - 10, pad ? 24 : 20);
    _nextLabel.frame = CGRectMake(cw - pad16 - nextW, 10, nextW, 20);
    _timeLabel.frame = CGRectMake(pad16, CGRectGetMaxY(_progLabel.frame), cw - pad16 * 2, 18);
    _track.frame = CGRectMake(pad16, CGRectGetMaxY(_timeLabel.frame) + 6, cw - pad16 * 2, 4);
    [self layoutFill];
    CGFloat by = CGRectGetMaxY(_track.frame) + 6, bH = bh - by - 4;
    NSArray *btns = @[_prevButton, _playButton, _nextButton];
    CGFloat liveW = _liveButton.hidden ? 0 : [_liveButton sizeThatFits:CGSizeMake(200, 34)].width + 24;
    // Chỗ hẹp (bảng kênh mở khi máy dọc / iPhone): chữ ngắn «« Trước» / «Sau »», khoảng cách co lại cho vừa
    for (int pass = 0; pass < 2; pass++) {
        BOOL shortTitles = pass == 1;
        [_prevButton setTitle:shortTitles ? @"« Trước" : @"« Kênh trước" forState:UIControlStateNormal];
        [_nextButton setTitle:shortTitles ? @"Sau »" : @"Kênh sau »" forState:UIControlStateNormal];
        CGFloat sum = liveW;
        for (UIButton *b in btns) sum += [b sizeThatFits:CGSizeMake(200, bH)].width + 16;
        if (sum + 3 * 12 <= cw - 16) break;
    }
    CGFloat sum = liveW;
    for (UIButton *b in btns) sum += [b sizeThatFits:CGSizeMake(200, bH)].width + 16;
    NSInteger gaps = liveW ? 3 : 2;
    CGFloat gap = MAX(4, MIN(pad ? 30 : 14, (cw - 16 - sum) / gaps));
    CGFloat total = sum + gap * gaps;
    CGFloat bx = MAX(8, (cw - total) / 2);
    for (UIButton *b in btns) {
        CGFloat bw = [b sizeThatFits:CGSizeMake(200, bH)].width + 16;
        b.frame = CGRectMake(bx, by, bw, bH);
        bx += bw + gap;
    }
    if (liveW) _liveButton.frame = CGRectMake(bx, by + (bH - 34) / 2, liveW, 34);

    _spinner.center = CGPointMake(cw / 2, h / 2 - 20);
    CGFloat sw = MIN(cw - 40, 560);
    CGFloat sh = [CBTheme heightOf:_status.text ?: @"" font:_status.font width:sw] + 4;
    _status.frame = CGRectMake((cw - sw) / 2, h / 2 + (_spinner.isAnimating ? 20 : -sh - 10), sw, sh);
    CGFloat rw = 150, ry = CGRectGetMaxY(_status.frame) + 14;
    BOOL both = !_retryButton.hidden && !_skipButton.hidden;
    _retryButton.frame = CGRectMake(both ? cw / 2 - rw - 6 : (cw - rw) / 2, ry, rw, 44);
    _skipButton.frame = CGRectMake(both ? cw / 2 + 6 : (cw - rw) / 2, ry, rw, 44);

    // Thẻ radio: giữa khoảng trống giữa hai thanh nút (ẩn khi đang báo trạng thái — đang mở / lỗi)
    _radioCard.hidden = !_radio || !_status.hidden;
    if (!_radioCard.hidden) {
        CGFloat ch = h - topH - bh, tw = MIN(cw - 32, pad ? 620 : 440);
        CGFloat songH = _radioSong.text.length ? MIN(ceil(_radioSong.font.lineHeight * 2) + 2,
                                                     [CBTheme heightOf:_radioSong.text font:_radioSong.font width:tw] + 2) : 0;
        CGFloat textH = (pad ? 30 : 24) + (songH ? songH + 6 : 0) + 20;
        CGFloat L = MAX(48, MIN(pad ? 180 : 112, ch - textH - 28));
        CGFloat y = MAX(8, (ch - L - 12 - textH) / 2);
        _radioCard.frame = CGRectMake(0, topH, cw, ch);
        _radioLogo.frame = _radioIcon.frame = CGRectMake((cw - L) / 2, y, L, L);
        y += L + 12;
        _radioName.frame = CGRectMake((cw - tw) / 2, y, tw, pad ? 30 : 24);
        y += _radioName.frame.size.height;
        _radioSong.frame = CGRectMake((cw - tw) / 2, y + (songH ? 6 : 0), tw, songH);
        y += songH ? songH + 6 : 0;
        _radioInfo.frame = CGRectMake((cw - tw) / 2, y + 2, tw, 18);
    }
}

- (void)layoutFill {
    NSDictionary *c = [self channel];
    NSDictionary *p = [CBIPTV nowFor:c at:[[NSDate date] timeIntervalSince1970]];
    double s = CBNum(p, @"s", 0), e = CBNum(p, @"e", 0), now = [[NSDate date] timeIntervalSince1970];
    double f = p && e > s ? MAX(0, MIN(1, (now - s) / (e - s))) : 0;
    // Trận đang đá: thanh tiến độ theo thời lượng trận
    BOOL live = !p && [CBIPTV matchState:c at:now] == CBMatchLive;
    if (live) f = MAX(0, MIN(1, (now - CBNum(c, @"kick", 0)) / (CBNum(c, @"dur", 150) * 60)));
    _track.hidden = !p && !live;
    _fill.frame = CGRectMake(0, 0, _track.bounds.size.width * f, 4);
}

#pragma mark - Radio

/// Radio nghe tiếp khi ra màn hình chính / khoá máy: iOS dừng AVPlayer còn gắn lớp hình khi app vào nền (QA1668) — tách trình
/// phát khỏi lớp hình; vào lại thì gắn lại. Kênh có hình thì để iOS dừng như cũ.
- (void)enteredBackground {
    if (_radio && _player) {
        [(AVPlayerLayer *)_video.layer setPlayer:nil];
        CBLog(@"Truyền hình: app vào nền — %@ nghe tiếp", CBStr([self channel], @"n"));
    }
}

- (void)enteringForeground {
    if (_player && [(AVPlayerLayer *)_video.layer player] != _player) [(AVPlayerLayer *)_video.layer setPlayer:_player];
}

/// Bật / tắt kiểu đài radio: thẻ đài thay cho hình, nút luôn hiện, máy được tự tắt màn hình (nghe tiếp khi khoá máy — app có
/// UIBackgroundModes audio)
- (void)setRadio:(BOOL)on {
    if (_radio != on) {
        _radio = on;
        [UIApplication sharedApplication].idleTimerDisabled = !on;
        [self setControlsVisible:YES];
    }
    if (on) [self updateRadioCard];
    [self.view setNeedsLayout];
}

- (void)updateRadioCard {
    NSDictionary *c = [self channel];
    _radioName.text = CBStr(c, @"n");
    NSDictionary *p = [CBIPTV nowFor:c at:[[NSDate date] timeIntervalSince1970]];
    _radioSong.text = _radioTitle.length ? [@"♪ " stringByAppendingString:_radioTitle] : (p ? CBStr(p, @"t") : nil);
    _radioInfo.text = _radioDesc ? [@"📻 Radio · " stringByAppendingString:_radioDesc] : @"📻 Radio";
    NSString *logo = CBStr(c, @"logo");
    if (!(logo == _radioLogoUrl || [logo isEqualToString:_radioLogoUrl])) {
        _radioLogoUrl = logo;
        _radioLogo.image = nil;
        CGFloat L = [CBTheme isPad] ? 180 : 112;
        if (logo) [CBImages load:logo size:CGSizeMake(L, L) into:_radioLogo];
    }
    _radioLogo.hidden = !logo;
    _radioIcon.hidden = logo != nil;
    [self.view setNeedsLayout];
}

/// Mỗi giây khi đang phát: luồng radio của lõi → hỏi tên bài (ICY) mỗi 4 giây; HLS → nhận ra luồng chỉ có tiếng (đài HLS như
/// VOV) sau 2,5 giây, hoặc có hình trở lại thì thôi kiểu radio
- (void)radioTick {
    if (!_started) return;
    if (_radioToken) {
        if (_ticks % 4) return;
        id r = [CBCore sync:@"media.radioInfo" args:@{@"token": _radioToken}];
        NSString *title = CBStr(r, @"title");
        NSString *codec = [CBStr(r, @"codec") uppercaseString] ?: @"MP3";
        double br = CBNum(r, @"br", 0);
        NSString *desc = br > 0 ? [NSString stringWithFormat:@"%@ · %.0f kbps", codec, br] : codec;
        BOOL changed = !(title == _radioTitle || [title isEqualToString:_radioTitle]) || ![desc isEqualToString:_radioDesc];
        if (changed) {
            if (title && ![title isEqualToString:_radioTitle]) CBLog(@"Truyền hình: %@ đang phát «%@»", CBStr([self channel], @"n"), title);
            _radioTitle = title;
            _radioDesc = desc;
            [self updateRadioCard];
            [self updateNowPlaying];
        }
        return;
    }
    BOOL video = _item.presentationSize.width > 0;
    for (AVPlayerItemTrack *tr in _item.tracks) {
        if ([tr.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) video = YES;
    }
    BOOL want = !video && ([CBIPTV isRadio:[self channel]] || CBNowMs() - _startedAt > 4000);
    if (want != _radio) {
        CBLog(@"Truyền hình: %@ %@", CBStr([self channel], @"n"), want ? @"chỉ có tiếng — hiện kiểu đài radio" : @"có hình — thôi kiểu radio");
        [self setRadio:want];
        [self updateNowPlaying];
    }
}

- (void)setControlsVisible:(BOOL)visible {
    [_hideTimer invalidate];
    _hideTimer = nil;
    _controlsVisible = visible;
    [UIView animateWithDuration:0.2 animations:^{
        self->_top.alpha = visible ? 1 : 0;
        self->_bottom.alpha = visible ? 1 : 0;
    }];
    if (visible && _started && !_radio) {
        _hideTimer = [NSTimer scheduledTimerWithTimeInterval:6 target:self selector:@selector(autoHide) userInfo:nil repeats:NO];
    }
}

/// Không chạm 6 giây khi đang phát: ẩn thanh nút và cả bảng kênh (hình toàn màn hình). Radio: không có hình để xem — giữ nút.
- (void)autoHide {
    if (!_started || _player.rate <= 0 || _radio) return;
    if (_panelOpen) [self toggleChannels];
    [self setControlsVisible:NO];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)sv {
    if (sv == _panel) [self setControlsVisible:YES];  // đang lướt bảng kênh: chưa ẩn
}

- (void)toggleControls {
    [self setControlsVisible:!_controlsVisible];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return touch.view == _video;
}

#pragma mark - Phát

- (void)showLoading:(NSString *)text {
    [_spinner startAnimating];
    _status.text = text;
    _status.hidden = NO;
    _retryButton.hidden = YES;
    _skipButton.hidden = YES;
    [self.view setNeedsLayout];
}

- (void)showError:(NSString *)text retry:(BOOL)retry {
    CBLog(@"Truyền hình: %@", [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
    [_spinner stopAnimating];
    _status.text = text;
    _status.hidden = NO;
    _retryButton.hidden = !retry;
    _skipButton.hidden = _channels.count < 2;
    [self setControlsVisible:YES];
    [self.view setNeedsLayout];
}

- (void)hideStatus {
    [_spinner stopAnimating];
    _status.hidden = YES;
    _retryButton.hidden = YES;
    _skipButton.hidden = YES;
    [self.view setNeedsLayout];   // thẻ radio ẩn khi đang báo trạng thái
}

- (void)playChannelAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_channels.count) return;
    _index = index;
    _source = 0;
    _listChecked = NO;
    // Bỏ qua nguồn đã biết là máy không phát được
    NSArray *urls = CBArr([self channel], @"urls");
    while (_source + 1 < (NSInteger)urls.count && [CBIPTV badReason:urls[_source]]) _source++;
    _retriedReset = NO;
    _reopens = 0;
    [self openSource];
    [self scrollPanelToCurrent];
}

- (void)nextChannel {
    if (_channels.count < 2) return;
    [self playChannelAt:(_index + 1) % (NSInteger)_channels.count];
}

- (void)previousChannel {
    if (_channels.count < 2) return;
    [self playChannelAt:(_index - 1 + (NSInteger)_channels.count) % (NSInteger)_channels.count];
}

- (void)nextSource {
    NSArray *urls = CBArr([self channel], @"urls");
    if (urls.count < 2) return;
    _source = (_source + 1) % (NSInteger)urls.count;
    _retriedReset = NO;
    _reopens = 0;
    [self openSource];
}

- (void)retry {
    [self showLoading:@"Đang kiểm tra link mới…"];
    // Kênh trận đấu: lấy danh sách mới (link thật hay được thêm sát giờ) rồi thử lại từ nguồn đầu
    if (CBNum([self channel], @"kick", 0) > 0) {
        [self refreshThenRetry];
        return;
    }
    // Kênh thường: danh sách cũ quá 10 phút thì tải lại (link có hạn dùng); nguồn đổi thì thử từ đầu, không thì mở lại nguồn này
    __weak CBLivePlayerViewController *weakSelf = self;
    [self refreshChannel:600 done:^(BOOL changed) {
        CBLivePlayerViewController *s = weakSelf;
        if (changed) {
            [s retryFromFirstSource];
            return;
        }
        s->_retriedReset = NO;
        s->_reopens = 0;
        [s openSource];
    }];
}

- (void)updateLabels {
    NSDictionary *c = [self channel];
    NSArray *urls = CBArr(c, @"urls");
    [_sourceButton setTitle:[NSString stringWithFormat:@"Nguồn %ld/%lu", (long)_source + 1, (unsigned long)urls.count]
                   forState:UIControlStateNormal];
    _sourceButton.hidden = urls.count < 2;
    _prevButton.enabled = _nextButton.enabled = _channels.count > 1;
    [self updateProgramme];
    [self updateBadge];
    [self.view setNeedsLayout];
}

- (void)updateProgramme {
    NSDictionary *c = [self channel];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *p = [CBIPTV nowFor:c at:now], *n = [CBIPTV nextFor:c at:now];
    NSString *name = CBStr(c, @"n") ?: @"";
    _titleLabel.text = p ? [NSString stringWithFormat:@"%@ · %@", name, CBStr(p, @"t")] : name;
    _progLabel.text = p ? CBStr(p, @"t") : name;
    if (p) {
        double e = CBNum(p, @"e", 0);
        _timeLabel.text = [NSString stringWithFormat:@"%@–%@ · còn %ld phút", [CBIPTV clock:CBNum(p, @"s", 0)], [CBIPTV clock:e],
                                                     (long)MAX(1, ceil((e - now) / 60))];
    } else if ([CBIPTV matchLine:c at:now]) {
        _timeLabel.text = [NSString stringWithFormat:@"%@ · %@", CBStr(c, @"g") ?: @"Trận đấu", [CBIPTV matchLine:c at:now]];
    } else {
        _timeLabel.text = [NSString stringWithFormat:@"%@ · chưa có lịch phát sóng", CBStr(c, @"g") ?: @"Kênh"];
    }
    _nextLabel.text = n ? [NSString stringWithFormat:@"Tiếp theo: %@ %@", [CBIPTV clock:CBNum(n, @"s", 0)], CBStr(n, @"t")] : @"";
    [self layoutFill];
}

- (double)behindLive {
    NSValue *v = _item.seekableTimeRanges.lastObject;
    if (!v) return 0;
    CMTimeRange r = [v CMTimeRangeValue];
    double end = CMTimeGetSeconds(CMTimeRangeGetEnd(r)), cur = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(end) || !isfinite(cur)) return 0;
    return MAX(0, end - cur);
}

- (void)updateBadge {
    if (_radioToken) {
        // Luồng tiếng liền của đài: không có khung xem lùi — tạm dừng rồi phát là mở lại từ đầu luồng (đúng giờ phát)
        NSString *text = !_started ? @"CHƯA PHÁT" : (_player.rate > 0 ? @"● TRỰC TIẾP" : @"TẠM DỪNG");
        if (![_badge.text isEqualToString:text]) {
            _badge.text = text;
            [self.view setNeedsLayout];
        }
        _badge.fillColor = _started && _player.rate > 0 ? CBRGB(0xD93A3F) : CBRGB(0x5A6068);
        if (!_liveButton.hidden) {
            _liveButton.hidden = YES;
            [self.view setNeedsLayout];
        }
        return;
    }
    double delay = _started && _baseSet ? [self behindLive] - _baseBehind : 0;
    BOOL behind = _started && (delay > 8 || _player.rate == 0);
    NSString *text = behind ? (delay > 8 ? [NSString stringWithFormat:@"CHẬM %@", [CBTheme time:delay]] : @"TẠM DỪNG")
                            : (_started ? @"● TRỰC TIẾP" : @"CHƯA PHÁT");
    if (![_badge.text isEqualToString:text]) {
        _badge.text = text;
        [self.view setNeedsLayout];   // bề ngang nhãn tính lúc bố cục
    }
    _badge.fillColor = behind || !_started ? CBRGB(0x5A6068) : CBRGB(0xD93A3F);
    BOOL showLive = behind && delay > 8;
    if (_liveButton.hidden == showLive) {
        _liveButton.hidden = !showLive;
        [self.view setNeedsLayout];
    }
}

- (void)openSource {
    NSInteger t = ++_token;
    [self teardownPlayer];
    _started = NO;
    _baseBehind = 0;
    _baseSet = NO;
    _radioToken = nil;
    _radioTitle = nil;
    _radioDesc = nil;
    _playAt = 0;
    _liveHint = nil;
    NSDictionary *c = [self channel];
    // Danh sách ghi là đài radio: hiện thẻ đài ngay lúc mở (đài không ghi thì nhận ra khi phát — luồng tiếng / HLS không hình)
    [self setRadio:[CBIPTV isRadio:c]];
    [self updateLabels];
    [_panel reloadData];
    NSArray *urls = CBArr(c, @"urls");
    NSString *name = CBStr(c, @"n") ?: @"kênh";
    if (_source >= (NSInteger)urls.count) {
        [self showError:[NSString stringWithFormat:@"%@ không có địa chỉ phát.", name] retry:NO];
        return;
    }
    NSString *url = urls[_source];
    _srcUrl = url;
    NSString *bad = [CBIPTV badReason:url];
    if (bad) {
        [self sourceFailed:bad permanent:YES token:t];
        return;
    }
    if ([CBIPTV isPlaceholderURL:url]) {
        // Link giả «không có tín hiệu»: đừng phát hình chờ (hết 10 s lại mở lại) — coi như nguồn chưa có
        [self sourceFailed:@"Danh sách chưa có link phát (đang để hình «không có tín hiệu»)." permanent:NO token:t];
        return;
    }
    [self showLoading:[NSString stringWithFormat:@"Đang mở %@…", name]];
    NSString *path = [[[NSURL URLWithString:url] path] lowercaseString] ?: @"";
    if ([path hasSuffix:@".mpd"]) {
        [CBIPTV markBad:url reason:@"Luồng DASH (.mpd) — iOS 5 / 6 chỉ phát HLS."];
        [self sourceFailed:[CBIPTV badReason:url] permanent:YES token:t];
        return;
    }
    NSString *ext = path.pathExtension;
    NSString *kind = [@[@"mp4", @"m4v", @"mov"] containsObject:ext] ? @"mp4"
                   : [ext isEqualToString:@"flv"] ? @"flv"
                   : [ext isEqualToString:@"ts"] ? @"ts"
                   : [ext isEqualToString:@"mkv"] ? @"mkv"
                   : [ext isEqualToString:@"m3u8"] ? @"hls" : nil;
    if (kind) [self openURL:url kind:kind codec:nil token:t];
    else [self sniffThenOpen:url token:t];
}

/// Link không rõ loại theo đuôi — đài radio (luồng MP3 / AAC liền: «…/radio_128», .mp3, .aac; danh sách .pls / .m3u của đài),
/// link chuyển tiếp («…/?id=vtv6»), .php…: lõi đọc vài KB đầu (`media.sniff`) rồi mở đúng kiểu. Nhớ kết quả 10 phút (mở lại
/// khi luồng đứt, đổi kênh qua lại khỏi hỏi lại).
- (void)sniffThenOpen:(NSString *)url token:(NSInteger)t {
    NSDictionary *cached = _sniffed[url];
    if (cached && CBNowMs() - (long long)CBNum(cached, @"at", 0) < 600000) {
        [self openSniffed:cached url:url token:t];
        return;
    }
    NSMutableDictionary *args = [@{@"src": url} mutableCopy];
    [args addEntriesFromDictionary:[CBIPTV headersFor:[self channel] url:url]];
    long long t0 = CBNowMs();
    __weak CBLivePlayerViewController *weakSelf = self;
    [CBCore call:@"media.sniff" args:args done:^(id ok, NSString *err) {
        CBLivePlayerViewController *s = weakSelf;
        if (!s || t != s->_token || s->_closed) return;
        NSString *kind = CBStr(ok, @"kind");
        CBLog(@"Truyền hình: nhận dạng %@ → %@%@ (HTTP %.0f, %lld ms)%@", url, kind ?: @"lỗi",
              CBStr(ok, @"codec") ? [@" " stringByAppendingString:CBStr(ok, @"codec")] : @"", CBNum(ok, @"status", 0), CBNowMs() - t0,
              CBStr(ok, @"error") || err ? [NSString stringWithFormat:@" — %@", CBStr(ok, @"error") ?: err] : @"");
        if (!kind) {
            [s sourceFailed:@"Máy chủ của kênh không trả lời." permanent:NO token:t];
            return;
        }
        NSMutableDictionary *r = [ok mutableCopy];
        r[@"at"] = @(CBNowMs());
        if ([@[@"hls", @"audio", @"flv", @"mp4", @"ts"] containsObject:kind]) {
            if (!s->_sniffed) s->_sniffed = [NSMutableDictionary dictionary];
            s->_sniffed[url] = r;
        }
        [s openSniffed:r url:url token:t];
    }];
}

- (void)openSniffed:(NSDictionary *)r url:(NSString *)url token:(NSInteger)t {
    NSString *kind = CBStr(r, @"kind") ?: @"unknown";
    // Danh sách .pls / .m3u của đài: mở địa chỉ luồng ghi bên trong; còn lại giữ link gốc (link chuyển tiếp đổi token mỗi lần)
    NSString *target = CBStr(r, @"url") ?: url;
    if ([@[@"hls", @"audio", @"flv", @"mp4", @"ts"] containsObject:kind]) {
        [self openURL:target kind:kind codec:CBStr(r, @"codec") token:t];
        return;
    }
    if ([kind isEqualToString:@"unknown"]) {
        // Không đọc ra loại: thử như HLS (cách cũ)
        [self openURL:url kind:@"hls" codec:nil token:t];
        return;
    }
    NSString *why;
    BOOL hard = NO;
    if ([kind isEqualToString:@"ogg"]) {
        why = @"Đài phát định dạng Ogg (Vorbis / Opus) — iOS 5 / 6 không giải mã được.";
        hard = YES;
        [CBIPTV markBad:url reason:why];
    } else if ([kind isEqualToString:@"http"]) {
        why = [NSString stringWithFormat:@"Link không còn phát (máy chủ trả lỗi HTTP %.0f).", CBNum(r, @"status", 0)];
    } else if ([kind isEqualToString:@"html"]) {
        why = @"Link dẫn tới một trang web, không phải luồng phát.";
    } else if ([kind isEqualToString:@"playlist"]) {
        why = @"Danh sách của đài không ghi địa chỉ luồng nào dùng được.";
    } else {
        why = @"Máy chủ của kênh không trả lời.";
    }
    [self sourceFailed:why permanent:hard token:t];
}

/// Mở một nguồn đã biết loại: hls | flv (lõi đổi sang HLS trực tiếp — bản vá 0004) | ts (MPEG-TS liền, lõi cắt thành HLS trực
/// tiếp — bản vá 0007) | mp4 (tệp) | mkv (không phát được) | audio (đài radio — luồng tiếng liền qua `r/…` của lõi, bản vá 0006)
- (void)openURL:(NSString *)url kind:(NSString *)kind codec:(NSString *)codec token:(NSInteger)t {
    NSDictionary *c = [self channel];
    NSString *name = CBStr(c, @"n") ?: @"kênh";
    BOOL file = [kind isEqualToString:@"mp4"], flv = [kind isEqualToString:@"flv"], audio = [kind isEqualToString:@"audio"];
    BOOL tsLive = [kind isEqualToString:@"ts"];
    BOOL live = flv || tsLive;   // luồng liền lõi cắt thành HLS trực tiếp (w/live.m3u8)
    if ([kind isEqualToString:@"mkv"]) {
        // MKV: AVPlayer của iOS 5 / 6 chỉ phát HLS và tệp MP4 — báo ngay, sang nguồn khác (thường có bản HLS)
        NSString *why = @"Luồng MKV — iOS 5 / 6 chỉ phát luồng HLS (.m3u8).";
        [CBIPTV markBad:url reason:why];
        [self sourceFailed:why permanent:YES token:t];
        return;
    }
    // Referer gửi đúng như danh sách kênh ghi; User-Agent riêng của nguồn (máy chủ thể thao hay đòi)
    NSMutableDictionary *args = [@{@"src": url} mutableCopy];
    [args addEntriesFromDictionary:[CBIPTV headersFor:c url:url]];
    id opened;
    if (audio) {
        if (codec) args[@"codec"] = codec;
        opened = [CBCore sync:@"media.openRadio" args:args];
    } else {
        // Biến BOOL riêng: @(a && b) là số 1 (kiểu int) → JSON 1, lõi đọc cờ bool thành false → coi là tệp MP4 — hỏng mọi link
        // không đuôi .m3u8 (link chuyển tiếp «…/?id=vtv6», .php…)
        BOOL hls = !file && !live;
        args[@"hls"] = @(hls);
        args[@"flv"] = @(flv);
        if (tsLive) args[@"ts"] = @YES;
        opened = [CBCore sync:@"media.open" args:args];
    }
    NSString *local = CBStr(opened, @"url");
    if (!local) {
        [self sourceFailed:@"Địa chỉ kênh không dùng được." permanent:NO token:t];
        return;
    }
    CBLog(@"Truyền hình: %@ (nguồn %ld/%lu) %@ qua %@", name, (long)_source + 1, (unsigned long)CBArr(c, @"urls").count, url, local);
    if (audio) {
        // Đài radio: luồng tiếng liền (như Icecast) — AVPlayer phát thẳng, không có danh sách phát để kiểm trước
        _radioToken = CBStr(opened, @"token");
        _radioDesc = [codec isEqualToString:@"aac"] ? @"AAC" : @"MP3";
        [self setRadio:YES];
        [self play:local];
        return;
    }
    if (file) {
        [self play:local];
        return;
    }
    // Đọc danh sách chính qua cổng nội bộ trước khi đưa cho AVPlayer: bản nào cũng quá sức máy thì báo ngay
    // (FLV / TS liền: lõi chờ đủ vài đoạn — tối đa 25 s — mới trả danh sách phát)
    if (live) [self showLoading:[NSString stringWithFormat:@"Đang mở %@ (luồng %@)…", name, flv ? @"FLV" : @"TS"]];
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:local] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:live ? 40 : 25];
    __weak CBLivePlayerViewController *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        CBLivePlayerViewController *s = weakSelf;
        if (!s || t != s->_token || s->_closed) return;
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (code != 200 || [text rangeOfString:@"#EXTM3U"].location == NSNotFound) {
            if (live && code == 502) {
                // Lõi báo lý do trong thân trả lời: mã hình máy không giải mã được / không phải FLV / TS → hỏng hẳn; còn lại (404
                // lúc chưa tới giờ phát, đứt mạng, máy chủ giới hạn số kết nối) thì thử lại được
                NSString *r = text.length ? text : @"Máy chủ của kênh không trả hình.";
                BOOL hard = [r rangeOfString:@"H.265"].location != NSNotFound || [r rangeOfString:@"mã hình"].location != NSNotFound ||
                            [r rangeOfString:@"không phải luồng"].location != NSNotFound;
                NSString *why = [[[r substringToIndex:1] uppercaseString] stringByAppendingString:[r substringFromIndex:1]];
                if (hard) [CBIPTV markBad:url reason:why];
                [s sourceFailed:why permanent:hard token:t];
                return;
            }
            NSString *why = code == 502 ? @"Máy chủ của kênh không trả lời, hoặc nguồn này không phải luồng HLS."
                                        : (err.localizedDescription ?: [NSString stringWithFormat:@"Lỗi HTTP %ld.", (long)code]);
            [s sourceFailed:why permanent:NO token:t];
            return;
        }
        NSString *undecodable = [CBIPTV undecodableReason:text];
        if (undecodable) {
            [CBIPTV markBad:url reason:undecodable];
            [s sourceFailed:undecodable permanent:YES token:t];
            return;
        }
        if ([CBIPTV isPlaceholderPlaylist:text]) {
            [s sourceFailed:@"Kênh đang phát hình chờ (đoạn phim ngắn), chưa có luồng trực tiếp." permanent:NO token:t];
            return;
        }
        // Lõi ghi chú về luồng (vd kênh TS tiếng MP2: đã bỏ tiếng, phát hình không tiếng) — dòng chú thích «# cb-note: …»; gợi ý
        // khi máy không lên hình («# cb-hint: …», vd hình xen kẽ dạng trường PAFF) — dùng khi canh giờ báo lỗi
        NSRange nr = [text rangeOfString:@"# cb-note: "];
        if (nr.location != NSNotFound) {
            NSString *note = [[[text substringFromIndex:NSMaxRange(nr)] componentsSeparatedByString:@"\n"] firstObject];
            CBLog(@"Truyền hình: %@ — %@", name, note);
            [CBTheme toast:note];
        }
        NSRange hr = [text rangeOfString:@"# cb-hint: "];
        if (hr.location != NSNotFound) {
            s->_liveHint = [[[text substringFromIndex:NSMaxRange(hr)] componentsSeparatedByString:@"\n"] firstObject];
            CBLog(@"Truyền hình: %@ — gợi ý: %@", name, s->_liveHint);
        }
        [s play:local];
    }];
}

- (void)sourceFailed:(NSString *)reason permanent:(BOOL)permanent token:(NSInteger)t {
    if (t != _token || _closed) return;
    [self teardownPlayer];
    NSDictionary *c = [self channel];
    NSArray *urls = CBArr(c, @"urls");
    NSString *name = CBStr(c, @"n") ?: @"Kênh";
    if ([CBIPTV autoSource] && _source + 1 < (NSInteger)urls.count) {
        CBLog(@"Truyền hình: %@ nguồn %ld lỗi (%@) — sang nguồn %ld", name, (long)_source + 1, reason, (long)_source + 2);
        _source++;
        _retriedReset = NO;
        _reopens = 0;
        [self openSource];
        return;
    }
    // Trận sắp / đang đá mà chưa nguồn nào có hình (kênh trận chỉ lên sóng gần giờ bóng lăn, có khi trễ): chờ rồi thử lại từ nguồn
    // đầu — trừ khi mọi nguồn đều đã biết là máy không phát được
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    CBMatchState ms = [CBIPTV matchState:c at:now];
    BOOL usable = NO;
    for (NSString *u in urls) if (![CBIPTV badReason:u]) { usable = YES; break; }
    if (usable && (ms == CBMatchLater || ms == CBMatchSoon || ms == CBMatchLive)) {
        double kick = CBNum(c, @"kick", 0);
        NSString *msg = now < kick
            ? [NSString stringWithFormat:@"Trận chưa bắt đầu — bóng lăn lúc %@.\nKênh chưa lên sóng, tự thử lại sau 20 giây…", [CBIPTV kickText:kick now:now]]
            : @"Trận đang đá nhưng kênh chưa phát hình.\nTự thử lại sau 20 giây…";
        CBLog(@"Truyền hình: %@ chưa có hình (%@) — chờ 20 s", name, reason);
        [self showError:msg retry:YES];
        __weak CBLivePlayerViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CBLivePlayerViewController *s = weakSelf;
            if (!s || s->_closed || t != s->_token || s->_started) return;
            [s refreshThenRetry];
        });
        return;
    }
    NSString *msg = [NSString stringWithFormat:@"%@ không phát được.\n%@", name, reason];
    // Kênh thường hỏng hết nguồn: link có hạn dùng (token) / người làm danh sách vừa thay link — tải lại danh sách (cũ quá 10 phút)
    // một lần; nguồn của kênh đổi thì thử lại từ đầu
    if (!permanent && !_listChecked && ms == CBMatchNone) {
        _listChecked = YES;
        CBLog(@"Truyền hình: %@ hỏng hết nguồn (%@) — xem danh sách có link mới không", name, reason);
        [self showLoading:@"Đang kiểm tra link mới…"];
        __weak CBLivePlayerViewController *weakSelf = self;
        [self refreshChannel:600 done:^(BOOL changed) {
            CBLivePlayerViewController *s = weakSelf;
            if (changed) [s retryFromFirstSource];
            else [s showError:msg retry:YES];
        }];
        return;
    }
    [self showError:msg retry:!permanent];
}

/// Tải lại danh sách nếu cũ hơn `age` giây (đang tải thì chờ), thay kênh đang xem bằng bản mới (cùng khoá); done(YES) = nguồn của
/// kênh vừa đổi. Không gọi done nếu trong lúc chờ người xem đã đổi kênh / đóng trình phát
- (void)refreshChannel:(double)age done:(void (^)(BOOL changed))done {
    NSInteger t = _token;
    __weak CBLivePlayerViewController *weakSelf = self;
    [CBIPTV refreshIfOlderThan:age done:^(NSString *err) {
        CBLivePlayerViewController *s = weakSelf;
        if (!s || s->_closed || t != s->_token || s->_started) return;
        NSDictionary *old = [s channel];
        NSDictionary *fresh = [CBIPTV channelForKey:CBStr(old, @"k")];
        BOOL changed = fresh && ![CBArr(fresh, @"urls") isEqualToArray:CBArr(old, @"urls")];
        if (changed) {
            CBLog(@"Truyền hình: %@ — danh sách vừa cập nhật nguồn (%lu → %lu)", CBStr(old, @"n"),
                  (unsigned long)CBArr(old, @"urls").count, (unsigned long)CBArr(fresh, @"urls").count);
        }
        if (fresh && s->_index < (NSInteger)s->_channels.count) {
            NSMutableArray *m = [s->_channels mutableCopy];
            m[s->_index] = fresh;
            s->_channels = m;
        }
        done(changed);
    }];
}

/// Kênh trận đấu chờ lên sóng: link thật thường chỉ có khi người làm danh sách cập nhật — tải lại danh sách (cũ quá 2 phút),
/// lấy bản mới của kênh (cùng khoá) rồi thử lại từ nguồn đầu
- (void)refreshThenRetry {
    __weak CBLivePlayerViewController *weakSelf = self;
    [self refreshChannel:120 done:^(BOOL changed) {
        [weakSelf retryFromFirstSource];
    }];
}

/// Danh sách vừa tải lại: thay các kênh khác trong bảng kênh bằng bản mới (cùng khoá) — kênh đang xem chỉ đổi khi phát hỏng
/// (refreshChannel:), để không đổi nguồn dưới chân luồng đang chạy
- (void)syncChannels {
    if ([CBIPTV loading]) return;
    NSArray *all = [CBIPTV channels];
    if (!all.count) return;
    NSMutableDictionary *byKey = [NSMutableDictionary dictionaryWithCapacity:all.count];
    for (NSDictionary *c in all) {
        NSString *k = CBStr(c, @"k");
        if (k && !byKey[k]) byKey[k] = c;   // khoá trùng: lấy kênh đầu như channelForKey:
    }
    NSMutableArray *m = [_channels mutableCopy];
    BOOL changed = NO;
    for (NSUInteger i = 0; i < m.count; i++) {
        if ((NSInteger)i == _index) continue;
        NSDictionary *f = byKey[CBStr(m[i], @"k")];
        if (f && f != m[i]) {
            m[i] = f;
            changed = YES;
        }
    }
    if (changed) _channels = m;
}

- (void)retryFromFirstSource {
    NSArray *urls = CBArr([self channel], @"urls");
    _source = 0;
    while (_source + 1 < (NSInteger)urls.count && [CBIPTV badReason:urls[_source]]) _source++;
    _retriedReset = NO;
    _reopens = 0;
    [self openSource];
}

- (void)play:(NSString *)url {
    [self teardownPlayer];
    _playAt = CBNowMs();
    _item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    _player = [AVPlayer playerWithPlayerItem:_item];
    [(AVPlayerLayer *)_video.layer setPlayer:_player];
    [_item addObserver:self forKeyPath:@"status" options:0 context:kLiveKVO];
    [_item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:kLiveKVO];
    [_player addObserver:self forKeyPath:@"rate" options:0 context:kLiveKVO];
    _observing = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [nc addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    // Kênh đang trao cho «Hình nổi» (app chạy nền nhờ âm thanh câm): mở lại nguồn thì chỉ nạp — không phát chồng tiếng khung nổi
    if ([CBFloatBridge isFloating:self]) return;
    [_player play];
}

- (void)teardownPlayer {
    if (!_player) return;
    [_player pause];
    if (_observing) {
        [_item removeObserver:self forKeyPath:@"status" context:kLiveKVO];
        [_item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:kLiveKVO];
        [_player removeObserver:self forKeyPath:@"rate" context:kLiveKVO];
        _observing = NO;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    [(AVPlayerLayer *)_video.layer setPlayer:nil];
    _player = nil;
    _item = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kLiveKVO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_player || self->_closed) return;
        if ([keyPath isEqualToString:@"status"]) {
            if (self->_item.status == AVPlayerItemStatusReadyToPlay && !self->_started) {
                self->_started = YES;
                self->_startedAt = CBNowMs();
                self->_listChecked = NO;   // phát được rồi: lần sau hỏng (link hết hạn sau vài giờ) lại được tìm link mới
                [self hideStatus];
                [CBIPTV addRecent:[self channel]];
                CBLog(@"Truyền hình: %@ đang phát (nguồn %ld)", CBStr([self channel], @"n"), (long)self->_source + 1);
                [self setControlsVisible:YES];
                [self updateNowPlaying];
            } else if (self->_item.status == AVPlayerItemStatusFailed) {
                [self playbackFailed:self->_item.error];
            }
        } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
            if (self->_item.playbackLikelyToKeepUp || self->_player.rate > 0) [self->_spinner stopAnimating];
            else if (self->_started) [self->_spinner startAnimating];
        } else if ([keyPath isEqualToString:@"rate"]) {
            [self->_playButton setTitle:self->_player.rate > 0 ? @"Tạm dừng" : @"Phát" forState:UIControlStateNormal];
            [self updateBadge];
            [self.view setNeedsLayout];
        }
    });
}

- (void)playbackFailed:(NSError *)error {
    NSError *under = error.userInfo[NSUnderlyingErrorKey];
    CBLog(@"Truyền hình: AVPlayer lỗi %@ [%@ %ld; gốc %@ %ld]", error.localizedDescription, error.domain, (long)error.code,
          under.domain, (long)under.code);
    NSInteger t = _token;
    // Dịch vụ phát của iOS vừa khởi động lại (-11819): thử lại cùng nguồn một lần
    if (error.code == -11819 && !_retriedReset) {
        _retriedReset = YES;
        [self openSource];
        return;
    }
    if (error.code == -11848 || error.code == -11828 || error.code == -11829 || under.code == -12925) {
        NSString *why = @"Máy không giải mã được định dạng của luồng này.";
        [CBIPTV markBad:_srcUrl reason:why];
        [self sourceFailed:why permanent:YES token:t];
        return;
    }
    [self sourceFailed:[NSString stringWithFormat:@"%@ (lỗi %ld)", error.localizedDescription ?: @"Không mở được luồng.", (long)error.code]
             permanent:NO token:t];
}

- (void)itemEnded:(NSNotification *)n {
    NSError *err = n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    BOOL failed = [n.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_closed || n.object != self->_item) return;
        AVPlayerItemErrorLogEvent *ev = self->_item.errorLog.events.lastObject;
        // Luồng trực tiếp «hết» / đứt (máy chủ ngừng phát, đoạn video lỗi, mạng chập chờn): mở lại nguồn này — sau 1 giây,
        // tối đa 5 lần liền; quá thì báo lỗi (nguồn sau nếu có)
        CBLog(@"Truyền hình: luồng %@ %@ (%@ %ld; nhật ký lỗi %ld %@ %@) — mở lại lần %ld", CBStr([self channel], @"n"),
              failed ? @"đứt" : @"hết", err.localizedDescription ?: @"", (long)err.code, (long)ev.errorStatusCode, ev.errorDomain ?: @"",
              ev.errorComment ?: @"", (long)self->_reopens + 1);
        if (++self->_reopens > 5) {
            [self sourceFailed:@"Luồng liên tục bị đứt." permanent:NO token:self->_token];
            return;
        }
        NSInteger t = self->_token;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (t == self->_token && !self->_closed) [self openSource];
        });
    });
}

#pragma mark - Thu nhỏ (CBMiniPlayer)

- (void)minimize {
    [CBMiniPlayer minimize:self];
}

- (UIView *)miniVideoView {
    return _video;
}

- (void)miniRestoreVideo:(UIView *)video {
    [self.view insertSubview:video atIndex:0];   // dưới thẻ radio / thanh nút như lúc đầu; khung đặt lại ở viewDidLayoutSubviews
    [self.view setNeedsLayout];
}

- (BOOL)miniPlaying {
    return _player.rate > 0;
}

- (void)miniTogglePlay {
    [self togglePlay];
}

- (NSString *)miniTitle {
    return CBStr([self channel], @"n") ?: _titleLabel.text;
}

/// Chương trình đang chiếu (có lịch phát sóng), không thì «Trực tiếp»
- (NSString *)miniSubtitle {
    NSDictionary *p = [CBIPTV nowFor:[self channel] at:[[NSDate date] timeIntervalSince1970]];
    return CBStr(p, @"t") ?: @"Trực tiếp";
}

- (double)miniProgress {
    return -1;
}

#pragma mark - Hình nổi (CBFloatBridge)

- (void)floatOut {
    [CBFloatBridge handoff:self];
}

- (NSString *)floatURL {
    if (!_started || !_item || _radio) return nil;
    NSURL *u = [_item.asset isKindOfClass:[AVURLAsset class]] ? [(AVURLAsset *)_item.asset URL] : nil;
    return u.absoluteString;
}

- (double)floatTime {
    return 0;
}

- (NSString *)floatTitle {
    return CBStr([self channel], @"n") ?: _titleLabel.text;
}

- (BOOL)floatLive {
    return YES;
}

- (BOOL)floatFill {
    return [CBPrefs videoFill];
}

- (void)floatPause {
    [_player pause];
}

- (void)floatSaveAt:(double)time {
}

/// Kênh trực tiếp: mở lại thì về mép trực tiếp (phần đệm lúc dừng đã cũ)
- (void)floatReturnedAt:(double)time play:(BOOL)play {
    if (_closed) return;
    if (play) [self goLive];
    [self setControlsVisible:YES];
}

- (void)togglePlay {
    // Chưa có trình phát (lỗi / đã dừng), hoặc đài radio đang tạm dừng: mở lại — radio nghe tiếp đúng giờ phát, không phát
    // phần đệm cũ
    if (!_player || (_radioToken && _player.rate <= 0)) {
        [self openSource];
        return;
    }
    if (_player.rate > 0) [_player pause];
    else [_player play];
    [self setControlsVisible:YES];
}

- (void)goLive {
    NSValue *v = _item.seekableTimeRanges.lastObject;
    if (!v) {
        [self openSource];
        return;
    }
    CMTimeRange r = [v CMTimeRangeValue];
    CMTime target = CMTimeSubtract(CMTimeRangeGetEnd(r), CMTimeMakeWithSeconds(_baseBehind, 600));
    [_player seekToTime:target];
    [_player play];
    [self updateBadge];
}

- (void)tick {
    if (_closed) return;
    _ticks++;
    BOOL playing = _started && _player.rate > 0;
    [CBWatchLimit tick:playing];
    CBLimitBlock b = [CBWatchLimit blocked];
    if (b != CBLimitNone && _appeared) {
        UIViewController *host = [CBMiniPlayer hostFor:self];
        [self close];
        [CBParental limitReached:b film:nil episode:nil host:host];
        return;
    }
    // Độ trễ tự nhiên sau mép trực tiếp: đo ở giây đầu có khung xem lùi (seekableTimeRanges) khi đang phát — AVPlayer báo khung
    // này muộn; đo sớm quá thì gốc = 0 và luồng có khung dài (ABC News) bị báo «CHẬM 1:17» dù không tạm dừng
    if (playing && _reopens && CBNowMs() - _startedAt > 60000) _reopens = 0;  // phát ổn một phút: đếm lại từ đầu
    if (playing && !_baseSet && _item.seekableTimeRanges.count && CBNowMs() - _startedAt > 2000) {
        _baseSet = YES;
        _baseBehind = [self behindLive];
    }
    [self updateBadge];
    [self radioTick];
    // Đưa luồng cho AVPlayer mà mãi chưa sẵn sàng (không báo lỗi, chỉ «đệm thiếu»): máy không giải mã được — vd hình xen kẽ
    // dạng trường (PAFF) của đài phát sóng trên iPad 1 — báo rõ thay vì quay mãi; có gợi ý của lõi thì ghi nhớ «không phát được»
    long long waited = _playAt && _item && !_started ? CBNowMs() - _playAt : 0;
    if (waited > (_liveHint ? 20000 : 35000)) {
        _playAt = 0;
        NSString *why = _liveHint ? [_liveHint stringByReplacingOccurrencesOfString:@"có thể không nhận." withString:@"không nhận — máy này không phát được kênh này."]
                                  : @"Quá lâu chưa lên hình — máy không giải mã được luồng này, hoặc mạng quá chậm.";
        CBLog(@"Truyền hình: %@ — %.0f s chưa lên hình (%@)", CBStr([self channel], @"n"), waited / 1000.0, _liveHint ?: @"không rõ lý do");
        if (_liveHint) [CBIPTV markBad:_srcUrl reason:why];
        [self sourceFailed:why permanent:_liveHint != nil token:_token];
        return;
    }
    if (_ticks % 15 == 0) {
        [self updateProgramme];
        [self.view setNeedsLayout];
        if (_panelOpen) [_panel reloadData];
        [self updateNowPlaying];
    }
}

- (void)guideChanged {
    [self syncChannels];
    [self updateProgramme];
    [_panel reloadData];
    [self.view setNeedsLayout];
}

#pragma mark - Bảng kênh / lịch

- (void)toggleChannels {
    _panelOpen = !_panelOpen;
    _panel.hidden = !_panelOpen;
    [_panel reloadData];
    [self.view setNeedsLayout];
    [self scrollPanelToCurrent];
    [self setControlsVisible:YES];
}

- (void)scrollPanelToCurrent {
    if (!_panelOpen || _index >= (NSInteger)_channels.count) return;
    [_panel layoutIfNeeded];
    [_panel scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_index inSection:0] atScrollPosition:UITableViewScrollPositionMiddle
                          animated:NO];
}

- (void)openGuide {
    CBTVGuideViewController *g = [[CBTVGuideViewController alloc] initWithChannel:[self channel]];
    g.fromPlayer = YES;
    CBNavController *nav = [[CBNavController alloc] initWithRootViewController:g];
    if ([CBTheme isPad]) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _channels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"ch"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ch"];
        cell.textLabel.font = [CBTheme bold:[CBTheme isPad] ? 15 : 14];
        cell.detailTextLabel.font = [CBTheme font:12];
        cell.textLabel.backgroundColor = cell.detailTextLabel.backgroundColor = [UIColor clearColor];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = CBRGB(0x1B2B26);
        cell.selectedBackgroundView = sel;
    }
    NSDictionary *c = _channels[ip.row];
    BOOL cur = ip.row == _index;
    cell.backgroundColor = cur ? CBRGB(0x1B2B26) : CBRGB(0x15181C);
    cell.textLabel.textColor = cur ? [CBTheme brand] : [CBTheme text];
    cell.textLabel.text = [NSString stringWithFormat:@"%@   %@", CBStr(c, @"num") ?: @"", CBStr(c, @"n") ?: @""];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *p = [CBIPTV nowFor:c at:now];
    NSString *bad = [CBIPTV channelBadReason:c], *match = [CBIPTV matchLine:c at:now];
    BOOL live = [CBIPTV matchState:c at:now] == CBMatchLive;
    cell.detailTextLabel.textColor = bad ? CBRGB(0xF0B44C) : (live ? CBRGB(0xFF6166) : [CBTheme dim]);
    NSString *g = CBStr(c, @"g") ?: @"";
    if ([CBIPTV isRadio:c]) g = [@"📻 " stringByAppendingString:g];
    cell.detailTextLabel.text = bad ? @"Máy này không phát được" : (p ? CBStr(p, @"t") : (match ?: g));
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    if (ip.row != _index) [self playChannelAt:ip.row];
    [self setControlsVisible:YES];
}

#pragma mark - Đóng / màn khoá

- (void)close {
    if (_closed) return;
    [CBWatchLimit flush];
    _closed = YES;
    _token++;
    [_tick invalidate];
    _tick = nil;
    [_hideTimer invalidate];
    [self teardownPlayer];
    [CBCore sync:@"media.closeAll" args:nil];
    [CBSync setPlaying:NO];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    if (self.presentingViewController) [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    [CBMiniPlayer playerClosed:self];
}

- (void)updateNowPlaying {
    NSDictionary *c = [self channel];
    NSDictionary *p = [CBIPTV nowFor:c at:[[NSDate date] timeIntervalSince1970]];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    // Radio: màn khoá hiện bài đang phát (tên bài ICY của đài) + logo đài
    info[MPMediaItemPropertyTitle] = _radioTitle.length ? _radioTitle : (p ? CBStr(p, @"t") : (CBStr(c, @"n") ?: @""));
    info[MPMediaItemPropertyArtist] = [NSString stringWithFormat:@"%@ · %@", CBStr(c, @"n") ?: @"Truyền hình", _radio ? @"radio" : @"trực tiếp"];
    if (_radio && _radioLogo.image && !_radioLogo.hidden) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:_radioLogo.image];
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlay]; break;
        case UIEventSubtypeRemoteControlPlay:
            if (_player.rate <= 0) [self togglePlay];
            break;
        case UIEventSubtypeRemoteControlPause: [_player pause]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self nextChannel]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self previousChannel]; break;
        default: break;
    }
}

- (NSString *)statusLine {
    AVPlayerItemAccessLogEvent *ev = _item.accessLog.events.lastObject;
    CGSize px = _item.presentationSize;
    NSDictionary *c = [self channel];
    return [NSString stringWithFormat:@"kênh %@ (%ld/%lu) nguồn %ld/%lu | %@ | rate %.2f | hình %.0fx%.0f, rớt %ld khung | đệm %@ | bitrate %.0f kbps | sau mép trực tiếp %.0f s (gốc %.0f s) | khựng %ld | RAM %.0f MB%@",
            CBStr(c, @"n"), (long)_index + 1, (unsigned long)_channels.count, (long)_source + 1, (unsigned long)CBArr(c, @"urls").count,
            _status.hidden ? @"đang phát" : [_status.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "], _player.rate,
            px.width, px.height, (long)ev.numberOfDroppedVideoFrames, _item.playbackLikelyToKeepUp ? @"đủ" : @"thiếu",
            ev.observedBitrate / 1000, [self behindLive], _baseBehind, (long)ev.numberOfStalls, CBResidentMB(),
            _radio ? [NSString stringWithFormat:@" | radio %@%@ «%@»", _radioToken ? @"luồng tiếng" : @"HLS", _radioDesc ? [@" " stringByAppendingString:_radioDesc] : @"",
                      _radioTitle ?: @""] : @""];
}

@end
