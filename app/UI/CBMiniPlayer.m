#import "CBMiniPlayer.h"
#import "CBLog.h"
#import "CBTheme.h"

@interface CBMiniPlayer () <UIGestureRecognizerDelegate>
@end

static CBMiniPlayer *gMini;                              // nhận chạm / nút / nhịp của khung
static UIViewController<CBMiniPlayable> *gPlayer;       // trình phát đang thu nhỏ (giữ sống tới khi mở lại / đóng)
static UIView *gBox, *gVideo;
static UIButton *gPlayButton;
static NSTimer *gTimer;
static NSInteger gCorner;                                // 0 dưới phải, 1 dưới trái, 2 trên phải, 3 trên trái

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
    // iPad RAM ≥ 400 MB (iPad mini 1…). iPhone: trình phát xoay ngang, app dọc — chưa thử trên máy thật, chưa bật.
    // CBMiniTest (lệnh gỡ lỗi «minitest 1»): bật cả trên máy RAM thấp / iPhone để thử chức năng
    return ([CBTheme isPad] && [NSProcessInfo processInfo].physicalMemory >= 400ull * 1024 * 1024) ||
           [[NSUserDefaults standardUserDefaults] boolForKey:@"CBMiniTest"];
}

+ (BOOL)isMini:(UIViewController *)player {
    return player && player == gPlayer;
}

+ (UIViewController *)hostFor:(UIViewController *)player {
    return player.presentingViewController ?: CBTopVC();
}

+ (CGRect)frameForCorner:(NSInteger)corner in:(CGRect)b {
    CGSize s = [CBTheme isPad] ? CGSizeMake(320, 180) : CGSizeMake(224, 126);
    CGFloat m = 12, top = 64 + m;   // dưới thanh trạng thái + thanh điều hướng
    CGFloat x = corner == 1 || corner == 3 ? m : b.size.width - s.width - m;
    CGFloat y = corner >= 2 ? top : b.size.height - s.height - m;
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

+ (void)minimize:(UIViewController<CBMiniPlayable> *)player {
    if (![self available] || !player || player == gPlayer) return;
    UIViewController *presenting = player.presentingViewController;
    if (!presenting) return;
    if (gPlayer) [self closeCurrent];
    if (!gMini) gMini = [[CBMiniPlayer alloc] init];
    gPlayer = player;
    UIView *video = [player miniVideoView];
    [video removeFromSuperview];
    CBLog(@"Thu nhỏ trình phát (%@)", NSStringFromClass([player class]));
    // Đóng màn phát không hiệu ứng (iPhone: app xoay lại dọc) rồi khung tự thu từ giữa màn hình về góc
    [presenting dismissViewControllerAnimated:NO completion:^{
        if (gPlayer == player) [self showBoxWithVideo:video];
    }];
}

+ (void)showBoxWithVideo:(UIView *)video {
    UIView *host = CBMainWin().rootViewController.view;
    if (!host) {
        [self closeCurrent];
        return;
    }
    CGRect b = host.bounds;
    CGRect start = [CBTheme isPad] ? b : CGRectMake(0, round((b.size.height - b.size.width * 9 / 16) / 2), b.size.width, round(b.size.width * 9 / 16));
    gBox = [[UIView alloc] initWithFrame:start];
    gBox.backgroundColor = [UIColor blackColor];
    gBox.autoresizingMask = [self maskForCorner:gCorner];
    gVideo = video;
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
    close.alpha = gPlayButton.alpha = 0;
    [gBox addSubview:close];
    [gBox addSubview:gPlayButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gMini action:@selector(tapped)];
    tap.delegate = gMini;
    [gBox addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gMini action:@selector(panned:)];
    pan.delegate = gMini;
    [gBox addGestureRecognizer:pan];
    [host addSubview:gBox];

    [UIApplication sharedApplication].idleTimerDisabled = YES;   // đang xem: máy không tự tắt màn hình
    [gMini refreshPlayButton];
    gTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:gMini selector:@selector(refreshPlayButton) userInfo:nil repeats:YES];
    CGRect end = [self frameForCorner:gCorner in:b];
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

/// Bỏ khung; trả view hình (cho trình phát gắn lại)
+ (UIView *)removeBox {
    [gTimer invalidate];
    gTimer = nil;
    UIView *video = gVideo;
    video.userInteractionEnabled = YES;
    [gBox removeFromSuperview];
    gBox = nil;
    gVideo = nil;
    gPlayButton = nil;
    gPlayer = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    return video;
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
    [self refreshPlayButton];
}

- (void)refreshPlayButton {
    if (!gPlayButton) return;
    BOOL playing = [gPlayer miniPlaying];
    [gPlayButton setImage:CBMiniIcon(playing ? @"pause" : @"play") forState:UIControlStateNormal];
    [UIApplication sharedApplication].idleTimerDisabled = playing;   // tạm dừng thì máy được tự tắt màn hình
}

/// Kéo khung; thả ra thì bám vào góc gần nhất
- (void)panned:(UIPanGestureRecognizer *)g {
    UIView *host = gBox.superview;
    if (!host) return;
    CGPoint t = [g translationInView:host];
    gBox.center = CGPointMake(gBox.center.x + t.x, gBox.center.y + t.y);
    [g setTranslation:CGPointZero inView:host];
    if (g.state != UIGestureRecognizerStateEnded && g.state != UIGestureRecognizerStateCancelled) return;
    CGPoint c = gBox.center;
    BOOL left = c.x < host.bounds.size.width / 2, top = c.y < host.bounds.size.height / 2;
    gCorner = (top ? 2 : 0) + (left ? 1 : 0);
    gBox.autoresizingMask = [CBMiniPlayer maskForCorner:gCorner];
    CGRect end = [CBMiniPlayer frameForCorner:gCorner in:host.bounds];
    UIView *box = gBox;
    [UIView animateWithDuration:0.2 animations:^{ box.frame = end; }];
}

@end
