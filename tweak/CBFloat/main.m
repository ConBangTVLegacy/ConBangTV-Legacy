// CBFloat — «Hình nổi» của Côn Bằng TV Legacy, chạy trong SpringBoard iOS 8 (MobileSubstrate nạp theo CBFloat.plist).
// Không móc hàm nào của SpringBoard: chỉ nghe thông báo Darwin, tự thêm một cửa sổ nhỏ.
//
// App (nút «Hình nổi» ở trình phát):
//   1. ghi /var/mobile/Documents/ConBangTV-float.json {url (cổng phát nội bộ của app), time (giây), title, live, fill}
//   2. bật âm thanh câm (app chạy nền — giữ cổng phát nội bộ), gửi vn.conbangtv.float.show, tự về màn hình chính
// CBFloat: khung video nổi trên mọi màn (cửa sổ mức 1050 — như băng thông báo), AVPlayer riêng phát địa chỉ đó.
//   chạm khung → ghi ConBangTV-float-back.json {action: open, time} + vn.conbangtv.float.back, mở app (app tua tới đó, phát tiếp)
//   ✕          → {action: close, time} (app lưu chỗ xem); khoá máy cũng vậy
//   nút phát / tạm dừng; kéo → bám góc gần nhất
// App tự mở lại (bấm biểu tượng) khi khung đang hiện → vn.conbangtv.float.reclaim → trả chỗ xem như chạm khung, không mở app.
// Gỡ lỗi: vn.conbangtv.float.shot → ảnh toàn màn hình (cả lớp video) /var/mobile/Documents/CBFloat-shot.png; vn.conbangtv.float.tap
// → như chạm khung (thử tự động — iOS 8 không giả được cú chạm); nhật ký CBFloat.log.
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>

static NSString *const kShowFile = @"/var/mobile/Documents/ConBangTV-float.json";
static NSString *const kBackFile = @"/var/mobile/Documents/ConBangTV-float-back.json";
static NSString *const kLogFile = @"/var/mobile/Documents/CBFloat.log";
static NSString *const kShotFile = @"/var/mobile/Documents/CBFloat-shot.png";
static NSString *const kAppId = @"vn.conbangtv.legacy";

static void CBFLog(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    NSLog(@"CBFloat: %@", msg);
    static NSDateFormatter *fmt;
    if (!fmt) {
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd HH:mm:ss.SSS";
    }
    NSData *line = [[NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLogFile];
    if (!h) {
        [line writeToFile:kLogFile atomically:NO];
        return;
    }
    [h seekToEndOfFile];
    [h writeData:line];
    [h closeFile];
}

/// Biểu tượng vẽ bằng CoreGraphics (như khung thu nhỏ trong app)
static UIImage *CBFIcon(NSString *kind) {
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

static UIImage *CBFCircle(UIColor *color, CGFloat d) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

/// Hướng giao diện đang dùng (app đang mở, không thì màn hình chính) — hàm riêng của SpringBoard iOS 8, thiếu thì thanh trạng thái
static UIInterfaceOrientation CBFOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (NSString *name in @[@"_frontMostAppOrientation", @"activeInterfaceOrientation"]) {
        SEL s = NSSelectorFromString(name);
        if ([app respondsToSelector:s]) {
            NSInteger o = ((NSInteger (*)(id, SEL))objc_msgSend)(app, s);
            if (o >= 1 && o <= 4) return (UIInterfaceOrientation)o;
        }
    }
    return app.statusBarOrientation;
}

@interface CBFloat : NSObject <UIGestureRecognizerDelegate>
@end

@implementation CBFloat {
    UIWindow *_window;
    UIView *_box;
    AVPlayer *_player;
    AVPlayerLayer *_layer;
    UIButton *_closeButton, *_playButton;
    UILabel *_message;
    NSTimer *_timer;
    NSDictionary *_info;
    BOOL _live, _seeked, _failed;
    double _startTime;
    NSInteger _corner;                   // 0 dưới phải, 1 dưới trái, 2 trên phải, 3 trên trái
    CGPoint _center;                     // tâm khung theo toạ độ giao diện
    BOOL _dragging;
    UIInterfaceOrientation _orientation;
    NSString *_prevCategory;
    AVAudioSessionCategoryOptions _prevOptions;
}

+ (instancetype)shared {
    static CBFloat *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CBFloat alloc] init]; });
    return s;
}

- (CGSize)boxSize {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? CGSizeMake(320, 180) : CGSizeMake(224, 126);
}

/// Khổ màn theo giao diện hiện tại (ngang / dọc) và khổ dọc cố định
- (CGSize)interfaceSize:(UIInterfaceOrientation)o portrait:(CGSize *)portrait {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGSize p = CGSizeMake(MIN(scr.width, scr.height), MAX(scr.width, scr.height));
    if (portrait) *portrait = p;
    return UIInterfaceOrientationIsLandscape(o) ? CGSizeMake(p.height, p.width) : p;
}

- (CGPoint)cornerCenter:(NSInteger)corner in:(CGSize)I {
    CGSize S = [self boxSize];
    CGFloat m = 12, top = 28;   // dưới thanh trạng thái
    CGFloat cx = corner == 1 || corner == 3 ? m + S.width / 2 : I.width - m - S.width / 2;
    CGFloat cy = corner >= 2 ? top + S.height / 2 : I.height - m - S.height / 2;
    return CGPointMake(cx, cy);
}

/// Đặt cửa sổ: tâm theo toạ độ giao diện → toạ độ dọc cố định của màn + xoay theo hướng giao diện (cửa sổ không có màn gốc
/// nên iOS không tự xoay nó)
- (void)place {
    if (!_window) return;
    CGSize P;
    CGSize I = [self interfaceSize:_orientation portrait:&P];
    CGPoint c = _center;
    CGPoint f;
    CGFloat angle;
    switch (_orientation) {
        case UIInterfaceOrientationLandscapeRight: f = CGPointMake(P.width - c.y, c.x); angle = M_PI_2; break;
        case UIInterfaceOrientationLandscapeLeft: f = CGPointMake(c.y, P.height - c.x); angle = -M_PI_2; break;
        case UIInterfaceOrientationPortraitUpsideDown: f = CGPointMake(P.width - c.x, P.height - c.y); angle = M_PI; break;
        default: f = c; angle = 0; break;
    }
    (void)I;
    CGSize S = [self boxSize];
    _window.transform = CGAffineTransformMakeRotation(angle);
    _window.bounds = CGRectMake(0, 0, S.width, S.height);
    _window.center = f;
}

- (void)layoutForOrientation {
    _orientation = CBFOrientation();
    CGSize I = [self interfaceSize:_orientation portrait:NULL];
    _center = [self cornerCenter:_corner in:I];
    [self place];
}

- (UIButton *)roundButton:(NSString *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 34, 34);
    [b setBackgroundImage:CBFCircle([UIColor colorWithWhite:0 alpha:0.6], 34) forState:UIControlStateNormal];
    [b setBackgroundImage:CBFCircle([UIColor colorWithWhite:0.25 alpha:0.85], 34) forState:UIControlStateHighlighted];
    [b setImage:CBFIcon(icon) forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)show {
    NSData *d = [NSData dataWithContentsOfFile:kShowFile];
    id info = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    NSString *url = [info isKindOfClass:[NSDictionary class]] ? info[@"url"] : nil;
    if (![url isKindOfClass:[NSString class]] || !url.length) {
        CBFLog(@"không có địa chỉ phát trong %@", kShowFile);
        return;
    }
    [self teardown];
    _info = info;
    _live = [info[@"live"] boolValue];
    _startTime = [info[@"time"] doubleValue];
    _seeked = _live || _startTime < 1;
    _failed = NO;

    // Âm thanh: phát được cả khi gạt im lặng, trộn với tiếng khác (không cắt tiếng app khác / âm thanh câm của Côn Bằng TV)
    AVAudioSession *s = [AVAudioSession sharedInstance];
    _prevCategory = s.category;
    _prevOptions = s.categoryOptions;
    [s setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
    [s setActive:YES error:NULL];

    _player = [AVPlayer playerWithURL:[NSURL URLWithString:url]];
    CGSize S = [self boxSize];
    _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, S.width, S.height)];
    _window.windowLevel = 1050;   // trên app đang mở, như băng thông báo
    _window.backgroundColor = [UIColor blackColor];
    _box = [[UIView alloc] initWithFrame:_window.bounds];
    _box.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _box.backgroundColor = [UIColor blackColor];
    _box.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    _box.layer.borderWidth = 1;
    [_window addSubview:_box];
    _layer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _layer.frame = _box.bounds;
    _layer.videoGravity = [info[@"fill"] boolValue] ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
    [_box.layer insertSublayer:_layer atIndex:0];

    _message = [[UILabel alloc] initWithFrame:CGRectInset(_box.bounds, 12, 0)];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _message.font = [UIFont systemFontOfSize:14];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 2;
    NSString *title = [info[@"title"] isKindOfClass:[NSString class]] ? info[@"title"] : @"";
    _message.text = title.length ? [NSString stringWithFormat:@"Đang tải…\n%@", title] : @"Đang tải…";
    [_box addSubview:_message];

    _closeButton = [self roundButton:@"close" action:@selector(closeTapped)];
    _closeButton.center = CGPointMake(S.width - 22, 22);
    [_box addSubview:_closeButton];
    _playButton = [self roundButton:@"pause" action:@selector(playTapped)];
    _playButton.center = CGPointMake(22, S.height - 22);
    [_box addSubview:_playButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    tap.delegate = self;
    [_box addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    pan.delegate = self;
    [_box addGestureRecognizer:pan];

    [self layoutForOrientation];
    _window.hidden = NO;   // không làm cửa sổ chính (không lấy bàn phím của app đang mở)
    if (_seeked) [_player play];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CBFLog(@"hiện «%@» %@ từ %.0f s — hướng %ld, màn %.0fx%.0f, cửa sổ %@", title, _live ? @"(trực tiếp)" : @"", _startTime,
           (long)_orientation, scr.width, scr.height, NSStringFromCGRect(_window.frame));
}

- (void)tick {
    if (!_player) return;
    UIInterfaceOrientation o = CBFOrientation();
    if (o != _orientation && !_dragging) {
        CBFLog(@"đổi hướng %ld → %ld", (long)_orientation, (long)o);
        [self layoutForOrientation];
    }
    AVPlayerItem *it = _player.currentItem;
    if (!_seeked && it.status == AVPlayerItemStatusReadyToPlay) {
        _seeked = YES;
        __weak CBFloat *weakSelf = self;
        [_player seekToTime:CMTimeMakeWithSeconds(_startTime, 600) completionHandler:^(BOOL finished) {
            CBFloat *s = weakSelf;
            [s->_player play];
        }];
    }
    if (it.status == AVPlayerItemStatusFailed && !_failed) {
        _failed = YES;
        CBFLog(@"không phát được: %@", it.error.localizedDescription ?: @"?");
        _message.text = @"Không phát được — chạm để mở app";
        _message.hidden = NO;
    }
    if (_layer.readyForDisplay && _player.rate > 0) _message.hidden = YES;
    [_playButton setImage:CBFIcon(_player.rate > 0 ? @"pause" : @"play") forState:UIControlStateNormal];
}

- (double)currentTime {
    if (!_seeked) return _startTime;
    double t = CMTimeGetSeconds(_player.currentTime);
    return isfinite(t) && t > 0 ? t : _startTime;
}

/// Trả chỗ xem cho app ({action, time, playing}) rồi bỏ khung; launch = mở app
- (void)finish:(NSString *)action launch:(BOOL)launch {
    if (!_window) return;
    NSDictionary *back = @{@"action": action, @"time": @([self currentTime]), @"playing": @(_player.rate > 0 || !_seeked),
                           @"url": _info[@"url"] ?: @""};
    [[NSJSONSerialization dataWithJSONObject:back options:0 error:NULL] writeToFile:kBackFile atomically:YES];
    notify_post("vn.conbangtv.float.back");
    CBFLog(@"%@ (%.0f s)%@", action, [self currentTime], launch ? @" — mở app" : @"");
    [self teardown];
    if (!launch) return;
    UIApplication *app = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([app respondsToSelector:s]) ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(app, s, kAppId, NO);
    else CBFLog(@"SpringBoard thiếu launchApplicationWithIdentifier:suspended:");
}

- (void)teardown {
    [_timer invalidate];
    _timer = nil;
    if (!_window) return;
    [_player pause];
    [_layer removeFromSuperlayer];
    _layer.player = nil;
    _player = nil;
    _layer = nil;
    _window.hidden = YES;
    _window = nil;
    _box = nil;
    _closeButton = _playButton = nil;
    _message = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:NULL];
    if (_prevCategory) [s setCategory:_prevCategory withOptions:_prevOptions error:NULL];
}

#pragma mark - Chạm

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIButton class]];
}

- (void)tapped {
    [self finish:@"open" launch:YES];
}

- (void)closeTapped {
    [self finish:@"close" launch:NO];
}

- (void)playTapped {
    if (_player.rate > 0) [_player pause];
    else [_player play];
    [self tick];
}

/// Kéo khung (toạ độ trong khung = toạ độ giao diện, vì khung xoay cùng giao diện); thả ra thì bám góc gần nhất
- (void)panned:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:_box];
    [g setTranslation:CGPointZero inView:_box];
    _dragging = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    _center = CGPointMake(_center.x + t.x, _center.y + t.y);
    if (_dragging) {
        [self place];
        return;
    }
    CGSize I = [self interfaceSize:_orientation portrait:NULL];
    BOOL left = _center.x < I.width / 2, top = _center.y < I.height / 2;
    _corner = (top ? 2 : 0) + (left ? 1 : 0);
    _center = [self cornerCenter:_corner in:I];
    [UIView animateWithDuration:0.2 animations:^{ [self place]; }];
}

#pragma mark - Gỡ lỗi

- (void)shot {
    CFTypeRef (*create)(void) = (CFTypeRef (*)(void))dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    UIImage *img = create ? CFBridgingRelease(create()) : nil;
    BOOL ok = [img isKindOfClass:[UIImage class]] && [UIImagePNGRepresentation(img) writeToFile:kShotFile atomically:YES];
    CBFLog(@"ảnh màn hình %@ (%.0fx%.0f)", ok ? kShotFile : @"lỗi", img.size.width, img.size.height);
}

@end

static void CBFNotified(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    NSString *n = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        CBFloat *f = [CBFloat shared];
        if ([n isEqualToString:@"vn.conbangtv.float.show"]) [f show];
        else if ([n isEqualToString:@"vn.conbangtv.float.reclaim"]) [f finish:@"open" launch:NO];
        else if ([n isEqualToString:@"vn.conbangtv.float.close"]) [f finish:@"close" launch:NO];
        else if ([n isEqualToString:@"com.apple.springboard.lockcomplete"]) [f finish:@"close" launch:NO];   // khoá máy: dừng
        else if ([n isEqualToString:@"vn.conbangtv.float.shot"]) [f shot];
        else if ([n isEqualToString:@"vn.conbangtv.float.tap"]) [f tapped];
    });
}

__attribute__((constructor)) static void CBFInit(void) {
    if (!objc_getClass("SpringBoard")) return;
    for (NSString *n in @[@"vn.conbangtv.float.show", @"vn.conbangtv.float.reclaim", @"vn.conbangtv.float.close",
                          @"com.apple.springboard.lockcomplete", @"vn.conbangtv.float.shot", @"vn.conbangtv.float.tap"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CBFNotified, (__bridge CFStringRef)n, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    CBFLog(@"sẵn sàng (SpringBoard)");
}
