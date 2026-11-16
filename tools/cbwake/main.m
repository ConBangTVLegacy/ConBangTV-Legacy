// CBWake — chạy trong SpringBoard (MobileSubstrate nạp theo CBWake.plist). Nhận thông báo Darwin từ SSH:
//   vn.conbangtv.legacy.unlock   bật sáng màn hình rồi mở khoá (máy không đặt mật khẩu)
// Dùng lớp riêng của SpringBoard iOS 5 / 6 (SBAwayController) — tra lúc chạy, thiếu hàm nào thì bỏ qua, ghi nhật ký.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void cbwake_call(id obj, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    if (![obj respondsToSelector:s]) {
        NSLog(@"CBWake: không có %@", sel);
        return;
    }
    NSMethodSignature *sig = [obj methodSignatureForSelector:s];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj;
    inv.selector = s;
    BOOL no = NO;
    for (NSUInteger i = 2; i < sig.numberOfArguments; i++) [inv setArgument:&no atIndex:(NSInteger)i];  // unlockWithSound:NO
    [inv invoke];
    NSLog(@"CBWake: %@", sel);
}

static void cbwake_unlock(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("SBAwayController");
        id away = [cls respondsToSelector:@selector(sharedAwayController)] ? [cls performSelector:@selector(sharedAwayController)] : nil;
        if (!away) {
            NSLog(@"CBWake: không có SBAwayController");
            return;
        }
        cbwake_call(away, @"undimScreen");
        cbwake_call(away, @"unlockWithSound:");
    });
}

__attribute__((constructor)) static void cbwake_init(void) {
    if (!objc_getClass("SpringBoard")) return;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, cbwake_unlock,
                                    CFSTR("vn.conbangtv.legacy.unlock"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    NSLog(@"CBWake: sẵn sàng");
}
