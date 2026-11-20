#import "CBMiniPlayer.h"
#import "CBGlass.h"
#import "CBIcon.h"
#import "CBLog.h"
#import "CBRootViewController.h"
#import "CBTheme.h"

@interface CBMiniPlayer () <UIGestureRecognizerDelegate>
@end

static CBMiniPlayer *gMini;                              // nhận chạm / nút / nhịp của khung
static UIViewController<CBMiniPlayable> *gPlayer;       // trình phát đang thu nhỏ (giữ sống tới khi mở lại / đóng)
static UIView *gBox, *gVideo;                            // khung nổi ở góc (iPad; iPhone khi kéo thanh lên)
static UIView *gBar, *gSlot;                             // iPhone: thanh ở đáy (nằm trong CBRootViewController) + ô hình bên trái
static UILabel *gTitle, *gSubtitle;
static UIView *gProgress, *gTrack;
static UIButton *gPlayButton;
static NSTimer *gTimer;
static NSInteger gCorner;                                // 0 dưới phải, 1 dưới trái, 2 trên phải, 3 trên trái
static BOOL gDragging;

// Thanh thu nhỏ của iPhone: viên kính cao 52 pt nằm trên thanh tab, hình 16:9 bên trái (71×40), hai nút 44 pt bên phải
static const CGFloat kBarH = 52, kBarVideoW = 71, kBarVideoH = 40, kBarButtonW = 44;
// Khung nổi: viền kính 6 pt quanh hình, góc ngoài bo 22
static const CGFloat kBoxPad = 6, kBoxRadius = 22;
// iPhone: lần trước anh kéo thanh lên thành khung nổi → lần thu nhỏ sau ra khung nổi luôn (kéo khung xuống mép dưới = về thanh)
static NSString *const kPhoneBoxKey = @"CBMiniPhoneBox";

static UIWindow *CBMainWin(void) {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    return [d respondsToSelector:@selector(window)] ? d.window : nil;
}

static UIViewController *CBTopVC(void) {
    UIViewController *vc = CBMainWin().rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

/// Biểu tượng (CBIcon): pause / play / close
static UIImage *CBMiniIcon(NSString *kind) {
    return [CBIcon named:kind size:[kind isEqualToString:@"close"] ? 16 : 18 color:[UIColor whiteColor]];
}

/// Ảnh che 4 góc của hình (màu kính, giữa trong suốt): hình vuông góc trông như bo tròn mà không cần layer.cornerRadius
/// (bo góc lớp video bắt GPU vẽ ngoài màn hình mỗi khung — xem CBTheme imageWithColor:radius:)
static UIImage *CBCornerMask(CGFloat r) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *img = cache[@(r)];
    if (img) return img;
    CGFloat side = r * 2 + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, side, side)];
    [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:r]];
    p.usesEvenOddFillRule = YES;
    [[UIColor colorWithRed:36 / 255.0 green:40 / 255.0 blue:48 / 255.0 alpha:1] setFill];
    [p fill];
    img = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(r, r, r, r)];
    UIGraphicsEndImageContext();
    cache[@(r)] = img;
    return img;
}

/// Thanh thu nhỏ iPhone (viên kính): hẹp (thanh tab thu gọn — nằm giữa nút tab và nút tìm) thì bỏ nút ✕, chữ co lại
@interface CBMiniBar : CBGlassView
@property (nonatomic, weak) UIView *slot, *title, *subtitle, *play, *close, *track;
@end

@implementation CBMiniBar
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    BOOL narrow = s.width < 250;
    CGFloat right = s.width - 4;
    self.close.hidden = narrow;
    if (!narrow) {
        self.close.frame = CGRectMake(right - kBarButtonW, (s.height - 44) / 2, kBarButtonW, 44);
        right -= kBarButtonW;
    }
    self.play.frame = CGRectMake(right - kBarButtonW, (s.height - 44) / 2, kBarButtonW, 44);
    right -= kBarButtonW;
    // Hẹp: ô hình nhỏ lại cho chữ còn chỗ
    CGFloat vw = narrow ? 50 : kBarVideoW, vh = narrow ? 28 : kBarVideoH;
    if (CGAffineTransformIsIdentity(self.slot.transform)) self.slot.frame = CGRectMake(narrow ? 10 : 6, (s.height - vh) / 2, vw, vh);
    CGFloat x = (narrow ? 10 : 6) + vw + (narrow ? 8 : 10);
    self.title.frame = CGRectMake(x, s.height / 2 - 18, MAX(10, right - x), 18);
    self.subtitle.frame = CGRectMake(x, s.height / 2 + 1, MAX(10, right - x), 16);
    self.track.frame = CGRectMake(24, s.height - 4, s.width - 48, 2);
}
@end

@implementation CBMiniPlayer

+ (BOOL)available {
    // RAM ≥ 400 MB: iPad mini 1…, iPhone 4 / 4S / 5, iPod touch 5. Máy 256 MB (iPad 1, iPhone 3GS, iPod touch 4) tắt.
    // iPhone: thanh ở đáy — cần màn gốc CBRootViewController (luôn có trên iPhone).
    // CBMiniTest (lệnh gỡ lỗi «minitest 1»): bật cả trên máy RAM thấp để thử chức năng
    BOOL ram = [NSProcessInfo processInfo].physicalMemory >= 400ull * 1024 * 1024 ||
               [[NSUserDefaults standardUserDefaults] boolForKey:@"CBMiniTest"];
    return ram && ([CBTheme isPad] || [CBRootViewController current]);
}

+ (BOOL)active {
    return gPlayer != nil;
}

/// iPhone: thu nhỏ ra thanh ở đáy (mặc định) hay khung nổi (anh đã kéo thanh lên lần trước)
+ (BOOL)phoneBox {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPhoneBoxKey];
}

+ (void)setPhoneBox:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kPhoneBoxKey];
}

+ (UIImage *)barIcon:(NSString *)kind {
    CGFloat s = 24;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [[UIColor whiteColor] set];
    if ([kind isEqualToString:@"float"]) {
        // màn hình + khung nhỏ nổi ở góc dưới phải
        UIBezierPath *outer = [UIBezierPath bezierPathWithRect:CGRectMake(2, 4.5, 20, 15)];
        outer.lineWidth = 1.8;
        [outer stroke];
        UIRectFill(CGRectMake(11.5, 11.5, 8, 6));
    } else {
        // mũi tên xuống: kéo trình phát xuống thanh ở đáy
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(5, 8.5)];
        [p addLineToPoint:CGPointMake(12, 15.5)];
        [p addLineToPoint:CGPointMake(19, 8.5)];
        p.lineWidth = 2.6;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p stroke];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (BOOL)isMini:(UIViewController *)player {
    return player && player == gPlayer;
}

+ (UIViewController *)hostFor:(UIViewController *)player {
    return player.presentingViewController ?: CBTopVC();
}

/// Khổ khung nổi (cả viền kính): hình iPad 320×180; iPhone 192×108 (~60% bề ngang màn 320 pt — như «Hình nổi»)
+ (CGSize)boxSize {
    CGSize v = [CBTheme isPad] ? CGSizeMake(320, 180) : CGSizeMake(192, 108);
    return CGSizeMake(v.width + kBoxPad * 2, v.height + kBoxPad * 2);
}

/// Khung ở góc `corner` trong `host`: dưới thanh điều hướng, trên bàn phím (iPhone)
+ (CGRect)frameForCorner:(NSInteger)corner in:(UIView *)host {
    CGRect b = host.bounds;
    CGSize s = [self boxSize];
    CGFloat m = 12, top = 64 + m, bottom = b.size.height;   // dưới thanh trạng thái + thanh điều hướng / thanh tab
    CBRootViewController *root = [CBRootViewController current];
    if (root && host == root.view) {
        UINavigationController *c = (UINavigationController *)root.content;
        UINavigationBar *nb = [c isKindOfClass:[UINavigationController class]] ? c.navigationBar : nil;
        top = root.overlayTop + m;
        if (nb.window && !c.navigationBarHidden) top = MAX(top, CGRectGetMaxY([host convertRect:nb.bounds fromView:nb]) + m);
        bottom -= root.overlayBottom - (root.bottomBar ? kBarH + 8 : 0);   // trên thanh tab
        if (root.keyboardTop > 0) bottom = MIN(bottom, root.keyboardTop);
    }
    CGFloat x = corner == 1 || corner == 3 ? m : b.size.width - s.width - m;
    CGFloat y = corner >= 2 ? top : MAX(top, bottom - s.height - m);
    return CGRectMake(round(x), round(y), s.width, s.height);
}

+ (UIViewAutoresizing)maskForCorner:(NSInteger)corner {
    return (corner == 1 || corner == 3 ? UIViewAutoresizingFlexibleRightMargin : UIViewAutoresizingFlexibleLeftMargin) |
           (corner >= 2 ? UIViewAutoresizingFlexibleBottomMargin : UIViewAutoresizingFlexibleTopMargin);
}

+ (UIButton *)roundButton:(NSString *)icon action:(SEL)action {
    CBPillButton *b = [CBPillButton circle:icon diameter:32];
    [b setIcon:icon size:[icon isEqualToString:@"close"] ? 13 : 15];
    [b addTarget:gMini action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// Nút phẳng của thanh iPhone (cao gần bằng thanh — dễ bấm một tay)
+ (UIButton *)barButton:(NSString *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, kBarButtonW, 44);
    [b setImage:CBMiniIcon(icon) forState:UIControlStateNormal];
    [b setBackgroundImage:[CBGlass pill:22 color:[UIColor colorWithWhite:1 alpha:0.12] sheen:NO] forState:UIControlStateHighlighted];
    b.accessibilityLabel = [icon isEqualToString:@"close"] ? @"Đóng" : @"Phát / tạm dừng";
    [b addTarget:gMini action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (void)minimize:(UIViewController<CBMiniPlayable> *)player {
    if (![self available] || !player || player == gPlayer) return;
    UIViewController *presenting = player.presentingViewController;
    if (!presenting) return;
    if (gPlayer) [self closeCurrent];
    if (!gMini) gMini = [[CBMiniPlayer alloc] init];
    gPlayer = player;
    UIView *video = [player miniVideoView];
    [video removeFromSuperview];
    BOOL phone = ![CBTheme isPad], box = !phone || [self phoneBox];
    CBLog(@"Thu nhỏ trình phát (%@%@)", NSStringFromClass([player class]), phone ? (box ? @", khung nổi" : @", thanh ở đáy") : @"");
    // Đóng màn phát không hiệu ứng (iPhone: app xoay lại dọc) rồi hình tự thu từ giữa màn hình về góc / về thanh ở đáy
    [presenting dismissViewControllerAnimated:NO completion:^{
        if (gPlayer != player) return;
        UIView *host = CBMainWin().rootViewController.view;
        CGRect b = host.bounds;
        // Điểm xuất phát của hiệu ứng: iPad cả màn hình; iPhone dải 16:9 giữa màn (app chưa kịp xoay về dọc thì thôi hiệu ứng)
        CGRect start = !phone ? b : (b.size.height > b.size.width
            ? CGRectMake(0, round((b.size.height - b.size.width * 9 / 16) / 2), b.size.width, round(b.size.width * 9 / 16)) : CGRectNull);
        if (box) [self showBoxWithVideo:video from:start];
        else [self showBarWithVideo:video from:start];
    }];
}

/// Khung nổi ở góc gCorner; hình bay từ `start` (toạ độ màn gốc; CGRectNull = hiện ngay)
+ (void)showBoxWithVideo:(UIView *)video from:(CGRect)start {
    UIView *host = CBMainWin().rootViewController.view;
    gVideo = video;
    if (!host) {
        [self closeCurrent];
        return;
    }
    CGRect end = [self frameForCorner:gCorner in:host];
    // Viền kính bo tròn quanh hình (hình vuông góc + ảnh che góc cùng màu kính)
    gBox = [[CBGlassView alloc] initWithFrame:CGRectIsNull(start) ? end : start radius:kBoxRadius style:CBGlassHeavy];
    gBox.autoresizingMask = [self maskForCorner:gCorner];
    UIView *inner = [[UIView alloc] initWithFrame:CGRectInset(gBox.bounds, kBoxPad, kBoxPad)];
    inner.backgroundColor = [UIColor blackColor];
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    inner.userInteractionEnabled = NO;
    [gBox addSubview:inner];
    video.frame = inner.bounds;
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    video.userInteractionEnabled = NO;   // chạm vào khung (cử chỉ của màn phát nằm yên tới khi mở lại)
    [inner addSubview:video];
    UIImageView *corners = [[UIImageView alloc] initWithImage:CBCornerMask(kBoxRadius - kBoxPad)];
    corners.frame = inner.frame;
    corners.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [gBox addSubview:corners];

    UIButton *close = [self roundButton:@"close" action:@selector(closeTapped)];
    close.center = CGPointMake(kBoxPad + 22, kBoxPad + 22);
    close.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    close.accessibilityLabel = @"Đóng";
    UIButton *open = [self roundButton:@"expand" action:@selector(tapped)];
    open.center = CGPointMake(gBox.bounds.size.width - kBoxPad - 22, kBoxPad + 22);
    open.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    open.accessibilityLabel = @"Mở lại toàn màn hình";
    gPlayButton = [self roundButton:@"pause" action:@selector(playTapped)];
    gPlayButton.bounds = CGRectMake(0, 0, 44, 44);
    [(CBPillButton *)gPlayButton setIcon:@"pause" size:18];
    gPlayButton.center = CGPointMake(gBox.bounds.size.width / 2, gBox.bounds.size.height / 2);
    gPlayButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [gBox addSubview:close];
    [gBox addSubview:open];
    [gBox addSubview:gPlayButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gMini action:@selector(tapped)];
    tap.delegate = gMini;
    [gBox addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gMini action:@selector(panned:)];
    pan.delegate = gMini;
    [gBox addGestureRecognizer:pan];
    [host addSubview:gBox];
    [self watchKeyboard];
    [self startRefresh];
    if (CGRectIsNull(start)) return;
    close.alpha = open.alpha = gPlayButton.alpha = 0;
    UIView *box = gBox, *playButton = gPlayButton;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        box.frame = end;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            close.alpha = 1;
            open.alpha = 1;
            playButton.alpha = 1;
        }];
    }];
}

/// iPhone: thanh ở đáy màn hình — hình 16:9 bên trái, tên + tập ở giữa, phát / tạm dừng và ✕ bên phải, vạch tiến độ ở mép trên.
/// Hình bay từ `start` (toạ độ màn gốc; CGRectNull = hiện ngay)
+ (void)showBarWithVideo:(UIView *)video from:(CGRect)start {
    CBRootViewController *root = [CBRootViewController current];
    gVideo = video;
    if (!root) {
        [self closeCurrent];
        return;
    }
    CGFloat W = root.view.bounds.size.width - 20;
    CBMiniBar *bar = [[CBMiniBar alloc] initWithFrame:CGRectMake(10, root.view.bounds.size.height - 120, W, kBarH) radius:-1 style:CBGlassBar];
    UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(6, (kBarH - kBarVideoH) / 2, kBarVideoW, kBarVideoH)];
    slot.backgroundColor = [UIColor blackColor];
    [bar addSubview:slot];
    video.frame = slot.bounds;
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    video.userInteractionEnabled = NO;
    [slot addSubview:video];
    UIImageView *corners = [[UIImageView alloc] initWithImage:CBCornerMask(9)];
    corners.frame = slot.bounds;
    corners.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [slot addSubview:corners];

    gTitle = [[UILabel alloc] init];
    gTitle.font = [CBTheme medium:14];
    gSubtitle = [[UILabel alloc] init];
    gSubtitle.font = [CBTheme font:12];
    for (UILabel *l in @[gTitle, gSubtitle]) {
        l.backgroundColor = [UIColor clearColor];
        l.textColor = l == gTitle ? [CBTheme text] : CBRGB(0xA9B1BE);
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        [bar addSubview:l];
    }
    gPlayButton = [self barButton:@"pause" action:@selector(playTapped)];
    UIButton *close = [self barButton:@"close" action:@selector(closeTapped)];
    [bar addSubview:gPlayButton];
    [bar addSubview:close];
    // Mép dưới trong viên kính: vạch tiến độ mảnh (phim)
    gTrack = [[UIView alloc] init];
    gTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    gTrack.userInteractionEnabled = NO;
    [bar addSubview:gTrack];
    gProgress = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 2)];
    gProgress.backgroundColor = [CBTheme accent];
    [gTrack addSubview:gProgress];
    bar.slot = slot;
    bar.title = gTitle;
    bar.subtitle = gSubtitle;
    bar.play = gPlayButton;
    bar.close = close;
    bar.track = gTrack;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gMini action:@selector(tapped)];
    tap.delegate = gMini;
    [bar addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gMini action:@selector(barPanned:)];
    pan.delegate = gMini;
    [bar addGestureRecognizer:pan];
    gBar = bar;
    gSlot = slot;
    [root setBottomBar:bar height:kBarH];
    [self startRefresh];

    // Hình bay từ `start` về ô bên trái thanh; chữ / nút hiện dần sau đó
    if (CGRectIsNull(start)) return;
    NSArray *fade = @[gTitle, gSubtitle, gPlayButton, close];
    for (UIView *v in fade) v.alpha = 0;
    video.frame = [slot convertRect:start fromView:root.view];
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        video.frame = slot.bounds;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            for (UIView *v in fade) v.alpha = 1;
        }];
    }];
}

/// iPhone, khung nổi: bàn phím hiện thì khung góc dưới dời lên trên bàn phím
+ (void)watchKeyboard {
    CBRootViewController *root = [CBRootViewController current];
    if (!root) return;
    root.keyboardChanged = ^(NSTimeInterval duration) {
        UIView *box = gBox;
        if (!box.superview || gDragging) return;
        CGRect end = [CBMiniPlayer frameForCorner:gCorner in:box.superview];
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            box.frame = end;
        } completion:nil];
    };
}

+ (void)startRefresh {
    [UIApplication sharedApplication].idleTimerDisabled = YES;   // đang xem: máy không tự tắt màn hình
    [gMini refresh];
    [gTimer invalidate];
    gTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:gMini selector:@selector(refresh) userInfo:nil repeats:YES];
}

/// Bỏ khung / thanh (giữ trình phát); trả view hình
+ (UIView *)detachVideo {
    [gTimer invalidate];
    gTimer = nil;
    UIView *video = gVideo;
    [gBox removeFromSuperview];
    gBox = nil;
    if (gBar) {
        [[CBRootViewController current] setBottomBar:nil height:0];
        gBar = nil;
    }
    [CBRootViewController current].keyboardChanged = nil;
    gSlot = nil;
    gTitle = gSubtitle = nil;
    gProgress = nil;
    gTrack = nil;
    gVideo = nil;
    gPlayButton = nil;
    gDragging = NO;
    return video;
}

/// Bỏ khung / thanh; trả view hình (cho trình phát gắn lại)
+ (UIView *)removeBox {
    UIView *video = [self detachVideo];
    video.userInteractionEnabled = YES;
    gPlayer = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    return video;
}

/// iPhone: thanh → khung nổi ở góc gần chỗ thả tay (`p` — toạ độ màn gốc)
+ (void)floatBarAt:(CGPoint)p {
    CBRootViewController *root = [CBRootViewController current];
    UIView *video = gVideo;
    if (!root || !video) return;
    CGRect from = [root.view convertRect:video.bounds fromView:video];
    CGSize b = root.view.bounds.size;
    gCorner = (p.y < b.height / 2 ? 2 : 0) + (p.x < b.width / 2 ? 1 : 0);
    [self setPhoneBox:YES];
    [self detachVideo];
    CBLog(@"Thanh thu nhỏ → khung nổi (góc %ld)", (long)gCorner);
    [self showBoxWithVideo:video from:from];
}

/// iPhone: khung nổi kéo xuống mép dưới → về thanh ở đáy
+ (void)dockBox {
    CBRootViewController *root = [CBRootViewController current];
    UIView *video = gVideo;
    if (!root || !video) return;
    CGRect from = [root.view convertRect:video.bounds fromView:video];
    [self setPhoneBox:NO];
    [self detachVideo];
    CBLog(@"Khung nổi → thanh thu nhỏ");
    [self showBarWithVideo:video from:from];
}

+ (void)expand {
    UIViewController<CBMiniPlayable> *p = gPlayer;
    UIViewController *top = CBTopVC();
    if (!p || !top) return;
    UIView *video = [self removeBox];
    if (video) [p miniRestoreVideo:video];
    CBLog(@"Mở lại trình phát (%@)", NSStringFromClass([p class]));
    [top presentViewController:p animated:YES completion:nil];
}

+ (void)closeCurrent {
    UIViewController<CBMiniPlayable> *p = gPlayer;
    if (!p) return;
    UIView *video = [self removeBox];
    if (video) [p miniRestoreVideo:video];
    CBLog(@"Đóng trình phát thu nhỏ (%@)", NSStringFromClass([p class]));
    [p close];
}

+ (void)closeOthers:(UIViewController *)player {
    if (gPlayer && gPlayer != player) [self closeCurrent];
}

+ (void)playerClosed:(UIViewController *)player {
    if (!player || player != gPlayer) return;
    UIView *video = [self removeBox];
    if (video) [(UIViewController<CBMiniPlayable> *)player miniRestoreVideo:video];
}

#pragma mark - Chạm

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIButton class]];
}

- (void)tapped {
    [CBMiniPlayer expand];
}

- (void)closeTapped {
    [CBMiniPlayer closeCurrent];
}

- (void)playTapped {
    [gPlayer miniTogglePlay];
    [self refresh];
}

/// Mỗi giây: nút phát / tạm dừng, tên (tự sang tập sau thì đổi), vạch tiến độ
- (void)refresh {
    if (!gPlayButton) return;
    BOOL playing = [gPlayer miniPlaying];
    [gPlayButton setImage:CBMiniIcon(playing ? @"pause" : @"play") forState:UIControlStateNormal];
    [UIApplication sharedApplication].idleTimerDisabled = playing;   // tạm dừng thì máy được tự tắt màn hình
    if (!gBar) return;
    NSString *title = [gPlayer respondsToSelector:@selector(miniTitle)] ? [gPlayer miniTitle] : nil;
    NSString *sub = [gPlayer respondsToSelector:@selector(miniSubtitle)] ? [gPlayer miniSubtitle] : nil;
    if (![gTitle.text isEqualToString:title ?: @""]) gTitle.text = title ?: @"";
    if (![gSubtitle.text isEqualToString:sub ?: @""]) gSubtitle.text = sub ?: @"";
    double p = [gPlayer respondsToSelector:@selector(miniProgress)] ? [gPlayer miniProgress] : -1;
    gTrack.hidden = !(p >= 0);
    if (p >= 0) gProgress.frame = CGRectMake(0, 0, round(gTrack.bounds.size.width * MIN(1, p)), 2);
}

/// Kéo khung; thả ra thì bám vào góc gần nhất. iPhone: kéo khung xuống quá mép dưới (hoặc hất mạnh xuống ở nửa dưới) = về thanh
- (void)panned:(UIPanGestureRecognizer *)g {
    UIView *host = gBox.superview;
    if (!host) return;
    CGPoint t = [g translationInView:host];
    gBox.center = CGPointMake(gBox.center.x + t.x, gBox.center.y + t.y);
    [g setTranslation:CGPointZero inView:host];
    gDragging = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    if (gDragging) return;
    CGFloat bottom = host.bounds.size.height;
    CBRootViewController *root = [CBRootViewController current];
    if (root.keyboardTop > 0) bottom = MIN(bottom, root.keyboardTop);
    CGFloat vy = [g velocityInView:host].y;
    if (![CBTheme isPad] && root && g.state == UIGestureRecognizerStateEnded &&
        (CGRectGetMaxY(gBox.frame) > bottom + 24 || (vy > 900 && gBox.center.y > bottom / 2))) {
        [CBMiniPlayer dockBox];
        return;
    }
    CGPoint c = gBox.center;
    BOOL left = c.x < host.bounds.size.width / 2, top = c.y < bottom / 2;
    gCorner = (top ? 2 : 0) + (left ? 1 : 0);
    gBox.autoresizingMask = [CBMiniPlayer maskForCorner:gCorner];
    CGRect end = [CBMiniPlayer frameForCorner:gCorner in:host];
    UIView *box = gBox;
    [UIView animateWithDuration:0.2 animations:^{ box.frame = end; }];
}

/// Thanh iPhone: kéo lên = hình tách khỏi thanh thành khung nổi (thả ở đâu thì bám góc gần đó), vuốt xuống = đóng hẳn;
/// kéo chưa đủ xa thì trả về chỗ cũ
- (void)barPanned:(UIPanGestureRecognizer *)g {
    UIView *bar = gBar, *slot = gSlot;
    if (!bar || !slot) return;
    UIView *host = bar.superview;
    CGPoint t = [g translationInView:host];
    if (g.state == UIGestureRecognizerStateBegan) [bar bringSubviewToFront:slot];   // ô hình đi lên đè vạch tiến độ / chữ
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        if (t.y < 0) {   // lên: ô hình đi theo ngón tay, thanh nằm yên
            bar.transform = CGAffineTransformIdentity;
            bar.alpha = 1;
            slot.transform = CGAffineTransformMakeTranslation(MAX(0, t.x), t.y);
        } else {         // xuống: cả thanh đi xuống, mờ dần
            slot.transform = CGAffineTransformIdentity;
            bar.transform = CGAffineTransformMakeTranslation(0, t.y);
            bar.alpha = MAX(0.3, 1 - t.y / 120);
        }
        return;
    }
    CGFloat vy = [g velocityInView:host].y;
    BOOL ended = g.state == UIGestureRecognizerStateEnded;
    if (ended && (t.y > 32 || vy > 600)) {
        [UIView animateWithDuration:0.18 animations:^{
            bar.transform = CGAffineTransformMakeTranslation(0, kBarH);
            bar.alpha = 0;
        } completion:^(BOOL finished) {
            if (gBar == bar) [CBMiniPlayer closeCurrent];
        }];
    } else if (ended && (t.y < -40 || vy < -600)) {
        [CBMiniPlayer floatBarAt:[g locationInView:host]];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            bar.transform = CGAffineTransformIdentity;
            bar.alpha = 1;
            slot.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [bar insertSubview:slot atIndex:0];   // vạch tiến độ lại nằm trên ô hình
        }];
    }
}

@end
