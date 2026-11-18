#import "CBMiniPlayer.h"
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
static UIView *gProgress;
static UIButton *gPlayButton;
static NSTimer *gTimer;
static NSInteger gCorner;                                // 0 dưới phải, 1 dưới trái, 2 trên phải, 3 trên trái
static BOOL gDragging;

// Thanh thu nhỏ của iPhone: cao 64 pt, hình 16:9 bên trái (114×64), hai nút 44 pt bên phải
static const CGFloat kBarH = 64, kBarVideoW = 114, kBarButtonW = 44;
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

/// Biểu tượng vẽ bằng CoreGraphics (khỏi phụ thuộc phông chữ: iOS 5 vẽ ▶ thành emoji, thiếu ❚)
static UIImage *CBMiniIcon(NSString *kind) {
    CGFloat s = 20;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [[UIColor whiteColor] set];
    if ([kind isEqualToString:@"pause"]) {
        UIRectFill(CGRectMake(s * 0.26, s * 0.2, s * 0.17, s * 0.6));
        UIRectFill(CGRectMake(s * 0.57, s * 0.2, s * 0.17, s * 0.6));
    } else if ([kind isEqualToString:@"play"]) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(s * 0.3, s * 0.18)];
        [p addLineToPoint:CGPointMake(s * 0.3, s * 0.82)];
        [p addLineToPoint:CGPointMake(s * 0.82, s * 0.5)];
        [p closePath];
        [p fill];
    } else {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(s * 0.26, s * 0.26)];
        [p addLineToPoint:CGPointMake(s * 0.74, s * 0.74)];
        [p moveToPoint:CGPointMake(s * 0.74, s * 0.26)];
        [p addLineToPoint:CGPointMake(s * 0.26, s * 0.74)];
        p.lineWidth = 2.5;
        p.lineCapStyle = kCGLineCapRound;
        [p stroke];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

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

/// Khổ khung nổi: iPad 320×180; iPhone 192×108 (~60% bề ngang màn 320 pt — như «Hình nổi»)
+ (CGSize)boxSize {
    return [CBTheme isPad] ? CGSizeMake(320, 180) : CGSizeMake(192, 108);
}

/// Khung ở góc `corner` trong `host`: dưới thanh điều hướng, trên bàn phím (iPhone)
+ (CGRect)frameForCorner:(NSInteger)corner in:(UIView *)host {
    CGRect b = host.bounds;
    CGSize s = [self boxSize];
    CGFloat m = 12, top = 64 + m, bottom = b.size.height;   // iPad: dưới thanh trạng thái + thanh điều hướng
    CBRootViewController *root = [CBRootViewController current];
    if (root && host == root.view) {
        UIViewController *c = root.content;
        UINavigationBar *nb = [c isKindOfClass:[UINavigationController class]] ? [(UINavigationController *)c navigationBar] : nil;
        if (nb.window) top = CGRectGetMaxY([host convertRect:nb.bounds fromView:nb]) + m;
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
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 34, 34);
    // Nền tròn là ảnh (không layer.cornerRadius — xem CBTheme imageWithColor:radius:)
    [b setBackgroundImage:[CBTheme imageWithColor:[UIColor colorWithWhite:0 alpha:0.6] radius:17] forState:UIControlStateNormal];
    [b setBackgroundImage:[CBTheme imageWithColor:[UIColor colorWithWhite:0.25 alpha:0.8] radius:17] forState:UIControlStateHighlighted];
    [b setImage:CBMiniIcon(icon) forState:UIControlStateNormal];
    [b addTarget:gMini action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// Nút phẳng của thanh iPhone (cao bằng thanh — dễ bấm một tay)
+ (UIButton *)barButton:(NSString *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, kBarButtonW, kBarH);
    [b setImage:CBMiniIcon(icon) forState:UIControlStateNormal];
    [b setBackgroundImage:[CBTheme imageWithColor:[UIColor colorWithWhite:1 alpha:0.08]] forState:UIControlStateHighlighted];
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
    gBox = [[UIView alloc] initWithFrame:CGRectIsNull(start) ? end : start];
    gBox.backgroundColor = [UIColor blackColor];
    gBox.autoresizingMask = [self maskForCorner:gCorner];
    video.frame = gBox.bounds;
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    video.userInteractionEnabled = NO;   // chạm vào khung (cử chỉ của màn phát nằm yên tới khi mở lại)
    [gBox addSubview:video];
    UIImageView *border = [[UIImageView alloc] initWithImage:[CBTheme imageWithColor:[UIColor clearColor] radius:0
                                                                             border:[UIColor colorWithWhite:1 alpha:0.3] width:1]];
    border.frame = gBox.bounds;
    border.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [gBox addSubview:border];

    UIButton *close = [self roundButton:@"close" action:@selector(closeTapped)];
    close.center = CGPointMake(gBox.bounds.size.width - 22, 22);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    gPlayButton = [self roundButton:@"pause" action:@selector(playTapped)];
    gPlayButton.center = CGPointMake(22, gBox.bounds.size.height - 22);
    gPlayButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [gBox addSubview:close];
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
    close.alpha = gPlayButton.alpha = 0;
    UIView *box = gBox, *playButton = gPlayButton;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        box.frame = end;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            close.alpha = 1;
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
    CGFloat W = root.view.bounds.size.width;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, root.view.bounds.size.height - kBarH, W, kBarH)];
    bar.backgroundColor = [CBTheme surface];
    UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kBarVideoW, kBarH)];
    slot.backgroundColor = [UIColor blackColor];
    [bar addSubview:slot];
    video.frame = slot.bounds;
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    video.userInteractionEnabled = NO;
    [slot addSubview:video];

    CGFloat textX = kBarVideoW + 10, textW = W - textX - 2 * kBarButtonW - 4;
    gTitle = [[UILabel alloc] initWithFrame:CGRectMake(textX, 13, textW, 19)];
    gTitle.font = [CBTheme bold:14];
    gSubtitle = [[UILabel alloc] initWithFrame:CGRectMake(textX, 33, textW, 17)];
    gSubtitle.font = [CBTheme font:12];
    for (UILabel *l in @[gTitle, gSubtitle]) {
        l.backgroundColor = [UIColor clearColor];
        l.textColor = l == gTitle ? [CBTheme text] : [CBTheme dim];
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [bar addSubview:l];
    }
    gPlayButton = [self barButton:@"pause" action:@selector(playTapped)];
    gPlayButton.frame = CGRectMake(W - 2 * kBarButtonW, 0, kBarButtonW, kBarH);
    UIButton *close = [self barButton:@"close" action:@selector(closeTapped)];
    close.frame = CGRectMake(W - kBarButtonW, 0, kBarButtonW, kBarH);
    for (UIButton *b in @[gPlayButton, close]) {
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [bar addSubview:b];
    }
    // Mép trên: đường kẻ mảnh; phim thì vạch tiến độ màu app đè lên
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 1)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:line];
    gProgress = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 2)];
    gProgress.backgroundColor = [CBTheme brand];
    [bar addSubview:gProgress];

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
    gProgress.hidden = !(p >= 0);
    if (p >= 0) gProgress.frame = CGRectMake(0, 0, round(gBar.bounds.size.width * MIN(1, p)), 2);
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
