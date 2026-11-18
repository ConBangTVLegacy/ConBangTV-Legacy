// CBTouch — chỉ có trong bản thử: giả lập chạm / nhấn giữ / vuốt đi đúng đường xử lý chạm của UIKit (UIApplication sendEvent →
// cửa sổ → hitTest → bộ nhận dạng cử chỉ, UIScrollView, chuỗi responder), để thử từ SSH những chỗ người dùng bấm thật (ô của
// CBCollectionView, nút, kéo để tải lại…). Cách làm như KIF 2.0 cho iOS 5 / 6: UITouch + UIEvent dựng bằng hàm riêng của UIKit,
// kèm một «GSEvent» giả (iOS 5 / 6 đọc toạ độ từ GSEvent của sự kiện). Toạ độ: điểm trong cửa sổ (hệ dọc của màn hình).
#import "CBTouch.h"
#import "CBLog.h"
#import <objc/message.h>

@interface CBEventProxy : NSObject {
@public
    unsigned int flags;
    unsigned int type;
    unsigned int ignored1;
    float x1, y1, x2, y2;
    unsigned int ignored2[10];
    unsigned int ignored3[7];
    float sizeX, sizeY, x3, y3;
    unsigned int ignored4[3];
}
@end

@implementation CBEventProxy
@end

static BOOL cbCall(id obj, NSString *name) {
    if ([obj respondsToSelector:NSSelectorFromString(name)]) return YES;
    CBLog(@"[chạm] thiếu %@ trên %@", name, NSStringFromClass([obj class]));
    return NO;
}

static void cbSetObj(id obj, NSString *name, id value) {
    if (cbCall(obj, name)) ((void (*)(id, SEL, id))objc_msgSend)(obj, NSSelectorFromString(name), value);
}

static void cbSetInt(id obj, NSString *name, NSInteger value) {
    if (cbCall(obj, name)) ((void (*)(id, SEL, NSInteger))objc_msgSend)(obj, NSSelectorFromString(name), value);
}

static void cbSetBool(id obj, NSString *name, BOOL value) {
    if (cbCall(obj, name)) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, NSSelectorFromString(name), value);
}

static void cbSetTime(id obj, NSString *name) {
    if (cbCall(obj, name)) {
        ((void (*)(id, SEL, double))objc_msgSend)(obj, NSSelectorFromString(name), [NSProcessInfo processInfo].systemUptime);
    }
}

static void cbSetPoint(UITouch *t, CGPoint p, BOOL reset) {
    if (cbCall(t, @"_setLocationInWindow:resetPrevious:")) {
        ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(t, NSSelectorFromString(@"_setLocationInWindow:resetPrevious:"), p, reset);
    }
}

static CBEventProxy *gProxy;
static NSMutableArray *gProxies;  // giữ mọi sự kiện giả (UIKit có thể còn trỏ tới sự kiện cũ khi chạm bị hoãn) — chỉ bản thử
static UITouch *gTouch;

@implementation CBTouch

+ (UITouch *)touchAt:(CGPoint)p {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UITouch *t = [[UITouch alloc] init];
    cbSetObj(t, @"setWindow:", w);  // phải đặt trước: xoá vài giá trị khác
    cbSetInt(t, @"setTapCount:", 1);
    cbSetPoint(t, p, YES);
    UIView *hit = [w hitTest:p withEvent:nil];
    cbSetObj(t, @"setView:", hit);
    cbSetInt(t, @"setPhase:", UITouchPhaseBegan);
    cbSetBool(t, @"_setIsFirstTouchForView:", YES);
    cbSetBool(t, @"setIsTap:", YES);
    cbSetTime(t, @"setTimestamp:");
    if ([t respondsToSelector:NSSelectorFromString(@"setGestureView:")]) cbSetObj(t, @"setGestureView:", hit);
    CBLog(@"[chạm] (%.0f, %.0f) → %@", p.x, p.y, NSStringFromClass([hit class]));
    return t;
}

/// Chạm giả chỉ dựng được kiểu GSEvent (iOS 5 / 6). iOS 7+ đọc IOHIDEvent của sự kiện — gửi sự kiện thiếu nó thì UIKit văng
/// (iPad mini 1 iOS 8, 18/11/2026) → không gửi
+ (BOOL)supported {
    static BOOL ok, logged;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ok = [[UIDevice currentDevice].systemVersion floatValue] < 7; });
    if (!ok && !logged) {
        logged = YES;
        CBLog(@"[chạm] chạm giả chưa làm cho iOS 7+ (cần IOHIDEvent) — bỏ qua lệnh");
    }
    return ok;
}

+ (void)send:(UITouch *)t phase:(UITouchPhase)phase at:(CGPoint)p {
    if (![self supported]) return;
    cbSetTime(t, @"setTimestamp:");
    cbSetInt(t, @"setPhase:", phase);
    if (phase != UITouchPhaseBegan) cbSetPoint(t, p, NO);
    UIApplication *app = [UIApplication sharedApplication];
    UIEvent *event = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
    if (!event) return;
    if (cbCall(event, @"_clearTouches")) ((void (*)(id, SEL))objc_msgSend)(event, NSSelectorFromString(@"_clearTouches"));
    gProxy = [[CBEventProxy alloc] init];
    if (!gProxies) gProxies = [NSMutableArray array];
    [gProxies addObject:gProxy];
    gProxy->x1 = gProxy->x2 = gProxy->x3 = p.x;
    gProxy->y1 = gProxy->y2 = gProxy->y3 = p.y;
    gProxy->sizeX = gProxy->sizeY = 1;
    gProxy->flags = phase == UITouchPhaseEnded ? 0x1010180 : 0x3010180;
    gProxy->type = 3001;  // kGSEventHand
    if ([event respondsToSelector:NSSelectorFromString(@"_setGSEvent:")]) {
        ((void (*)(id, SEL, void *))objc_msgSend)(event, NSSelectorFromString(@"_setGSEvent:"), (__bridge void *)gProxy);
    }
    if ([event respondsToSelector:NSSelectorFromString(@"_setTimestamp:")]) {
        ((void (*)(id, SEL, double))objc_msgSend)(event, NSSelectorFromString(@"_setTimestamp:"), [NSProcessInfo processInfo].systemUptime);
    }
    if (cbCall(event, @"_addTouch:forDelayedDelivery:")) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event, NSSelectorFromString(@"_addTouch:forDelayedDelivery:"), t, NO);
    }
    [app sendEvent:event];
}

+ (void)after:(double)s run:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

+ (void)tapAt:(CGPoint)p {
    gTouch = [self touchAt:p];
    [self send:gTouch phase:UITouchPhaseBegan at:p];
    UITouch *t = gTouch;
    [self after:0.08 run:^{ [self send:t phase:UITouchPhaseEnded at:p]; }];
}

+ (void)holdAt:(CGPoint)p seconds:(double)s {
    gTouch = [self touchAt:p];
    [self send:gTouch phase:UITouchPhaseBegan at:p];
    UITouch *t = gTouch;
    [self after:MAX(0.1, s) run:^{ [self send:t phase:UITouchPhaseEnded at:p]; }];
}

+ (void)dragFrom:(CGPoint)a to:(CGPoint)b seconds:(double)s {
    gTouch = [self touchAt:a];
    cbSetBool(gTouch, @"setIsTap:", NO);
    [self send:gTouch phase:UITouchPhaseBegan at:a];
    UITouch *t = gTouch;
    int steps = MAX(4, (int)(MAX(0.1, s) / 0.02));
    for (int i = 1; i <= steps; i++) {
        CGPoint q = CGPointMake(a.x + (b.x - a.x) * i / steps, a.y + (b.y - a.y) * i / steps);
        [self after:0.02 * i run:^{ [self send:t phase:UITouchPhaseMoved at:q]; }];
    }
    // Giữ tay ở cuối một chút rồi mới thả (không «hất» — UIScrollView không trôi theo đà)
    [self after:0.02 * steps + 0.15 run:^{ [self send:t phase:UITouchPhaseEnded at:b]; }];
}

@end
