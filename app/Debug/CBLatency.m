#import "CBLatency.h"
#import "CBCollectionView.h"
#import "CBFPS.h"
#import "CBLog.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <pthread.h>

// Đồng hồ: UITouch.timestamp và CACurrentMediaTime cùng tính từ lúc máy khởi động (mach_absolute_time)
static CFTimeInterval gDownAt, gDownLag, gUpAt, gOpenAt;
static BOOL gLitLogged, gOpenLogged, gShownLogged;
static uint32_t gOpenFrames;

/// Thay cài đặt của phương thức (lớp chưa tự có thì thêm vào lớp đó, cài cũ = của lớp cha); trả cài cũ
static IMP CBSwap(Class c, SEL s, IMP repl) {
    Method m = class_getInstanceMethod(c, s);
    if (!m) return NULL;
    IMP old = method_getImplementation(m);
    if (class_addMethod(c, s, repl, method_getTypeEncoding(m))) return old;
    return method_setImplementation(m, repl);
}

static NSString *CBMs(CFTimeInterval s) {
    return [NSString stringWithFormat:@"%.0f ms", s * 1000];
}

// ---- Sự kiện chạm vào app

static IMP gSendEvent;
static void CBSendEvent(UIApplication *app, SEL cmd, UIEvent *e) {
    if (e.type == UIEventTypeTouches) {
        CFTimeInterval now = CACurrentMediaTime();
        for (UITouch *t in [e allTouches]) {
            if (t.phase == UITouchPhaseBegan) {
                gDownAt = t.timestamp;
                gDownLag = now - t.timestamp;
                gLitLogged = NO;
            } else if (t.phase == UITouchPhaseEnded && gDownAt) {
                gUpAt = t.timestamp;
                gOpenLogged = gShownLogged = NO;
                gOpenAt = 0;
                CBLog(@"[chạm] giữ tay %@ — chạm xuống → app nhận %@, nhấc tay → app nhận %@", CBMs(t.timestamp - gDownAt), CBMs(gDownLag),
                      CBMs(now - t.timestamp));
            }
        }
    }
    ((void (*)(id, SEL, UIEvent *))gSendEvent)(app, cmd, e);
}

// ---- Ô / nút sáng lên

static void CBLit(id view) {
    if (gLitLogged || !gDownAt || CACurrentMediaTime() - gDownAt > 2) return;
    gLitLogged = YES;
    CBLog(@"[chạm] chạm xuống → %@ sáng lên %@", NSStringFromClass([view class]), CBMs(CACurrentMediaTime() - gDownAt));
}

static IMP gControlLit, gTableLit, gGridLit;
static void CBControlLit(id self, SEL cmd, BOOL on) {
    if (on) CBLit(self);
    ((void (*)(id, SEL, BOOL))gControlLit)(self, cmd, on);
}
static void CBTableLit(id self, SEL cmd, BOOL on, BOOL animated) {
    if (on) CBLit(self);
    ((void (*)(id, SEL, BOOL, BOOL))gTableLit)(self, cmd, on, animated);
}
static void CBGridLit(id self, SEL cmd, BOOL on) {
    if (on) CBLit(self);
    ((void (*)(id, SEL, BOOL))gGridLit)(self, cmd, on);
}

// ---- Mở màn mới sau khi chạm

// Mọi lần mở màn đều đo (cả mở bằng lệnh gỡ lỗi); «sau chạm» khi vừa nhấc tay < 3 s
static BOOL gAfterTap;
static void CBOpening(id vc) {
    CFTimeInterval now = CACurrentMediaTime();
    if (gOpenAt && now - gOpenAt < 0.5) return;   // màn con của màn vừa mở
    gAfterTap = !gOpenLogged && gUpAt && now - gUpAt < 3;
    if (gAfterTap) {
        gOpenLogged = YES;
        CBLog(@"[chạm] nhấc tay → bắt đầu mở %@: %@", NSStringFromClass([vc class]), CBMs(now - gUpAt));
    }
    gOpenAt = now;
    gShownLogged = NO;
    gOpenFrames = CBRenderFrames();
}

static IMP gPush, gPop, gPresent, gDidAppear;
static void CBPush(UINavigationController *nav, SEL cmd, UIViewController *vc, BOOL animated) {
    CBOpening(vc);
    ((void (*)(id, SEL, id, BOOL))gPush)(nav, cmd, vc, animated);
}
static UIViewController *CBPop(UINavigationController *nav, SEL cmd, BOOL animated) {
    if (nav.viewControllers.count > 1) CBOpening(nav.viewControllers[nav.viewControllers.count - 2]);
    return ((UIViewController *(*)(id, SEL, BOOL))gPop)(nav, cmd, animated);
}
static void CBPresent(UIViewController *host, SEL cmd, UIViewController *vc, BOOL animated, id completion) {
    CBOpening(vc);
    ((void (*)(id, SEL, id, BOOL, id))gPresent)(host, cmd, vc, animated, completion);
}
static void CBDidAppear(UIViewController *vc, SEL cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))gDidAppear)(vc, cmd, animated);
    if (!gOpenAt || gShownLogged || [vc isKindOfClass:[UINavigationController class]]) return;
    gShownLogged = YES;
    CFTimeInterval now = CACurrentMediaTime(), dur = now - gOpenAt;
    uint32_t frames = CBRenderFrames() - gOpenFrames;
    CBLog(@"[chạm] %@ hiện xong: chuyển màn %@, %.0f khung/s%@", NSStringFromClass([vc class]), CBMs(dur), dur > 0.05 ? frames / dur : 0,
          gAfterTap ? [NSString stringWithFormat:@" (nhấc tay → hiện xong %@)", CBMs(now - gUpAt)] : @"");
    gOpenAt = 0;
}

// ---- Canh luồng chính: bận liền > 100 ms thì ghi ngăn xếp lúc đang nghẽn

enum { kShots = 3, kDepth = 48 };
static const double kShotAt[kShots] = {0.08, 0.25, 0.6};
static uintptr_t gShot[kShots][kDepth];
static volatile int gShotDepth[kShots];
static volatile int gShots;
static volatile CFTimeInterval gBusyFrom;   // 0 = luồng chính đang chờ sự kiện
static thread_act_t gMain;
static uintptr_t gLo, gHi;

static void *CBWatch(void *arg) {
    // Ưu tiên cao: luồng chính đang nghẽn thì luồng này vẫn phải được chạy để chụp ngăn xếp
    struct sched_param sp = {.sched_priority = 46};
    pthread_setschedparam(pthread_self(), SCHED_RR, &sp);
    for (;;) {
        usleep(20000);
        CFTimeInterval from = gBusyFrom;
        int n = gShots;
        if (!from || n >= kShots || CACurrentMediaTime() - from < kShotAt[n]) continue;
        gShotDepth[n] = CBCaptureStack(gMain, gLo, gHi, gShot[n], kDepth);
        if (gBusyFrom == from) gShots = n + 1;
    }
    return NULL;
}

static void CBReportStall(CFTimeInterval dur) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSArray *skip = @[@"mach_msg_trap", @"mach_msg", @"objc_msgSend", @"main", @"UIApplicationMain", @"GSEventRunModal",
                      @"CFRunLoopRunSpecific", @"CFRunLoopRunInMode", @"__CFRunLoopRun", @"start"];
    NSMutableArray *lines = [NSMutableArray array];
    for (int s = 0; s < gShots; s++) {
        NSMutableArray *names = [NSMutableArray array];
        for (int d = 0; d < gShotDepth[s] && names.count < 14; d++) {
            NSString *n = CBSymbol(gShot[s][d], cache);
            if (![skip containsObject:n] && ![names.lastObject isEqualToString:n]) [names addObject:n];
        }
        [lines addObject:[NSString stringWithFormat:@"  sau %@: %@", CBMs(kShotAt[s]), [names componentsJoinedByString:@" ← "]]];
    }
    CBLog(@"[nghẽn] luồng chính bận liền %@%@%@", CBMs(dur), lines.count ? @"\n" : @"", [lines componentsJoinedByString:@"\n"]);
}

static void CBRunLoop(CFRunLoopObserverRef o, CFRunLoopActivity a, void *info) {
    CFTimeInterval now = CACurrentMediaTime();
    if (a == kCFRunLoopAfterWaiting) {
        gShots = 0;
        gBusyFrom = now;
    } else if (a == kCFRunLoopBeforeWaiting) {
        CFTimeInterval from = gBusyFrom;
        gBusyFrom = 0;
        if (from && now - from > 0.1) CBReportStall(now - from);
        gShots = 0;
    }
}

@implementation CBLatency

+ (void)start {
    gSendEvent = CBSwap([UIApplication class], @selector(sendEvent:), (IMP)CBSendEvent);
    gControlLit = CBSwap([UIControl class], @selector(setHighlighted:), (IMP)CBControlLit);
    gTableLit = CBSwap([UITableViewCell class], @selector(setHighlighted:animated:), (IMP)CBTableLit);
    gGridLit = CBSwap([CBCollectionViewCell class], @selector(setHighlighted:), (IMP)CBGridLit);
    gPush = CBSwap([UINavigationController class], @selector(pushViewController:animated:), (IMP)CBPush);
    gPop = CBSwap([UINavigationController class], @selector(popViewControllerAnimated:), (IMP)CBPop);
    gPresent = CBSwap([UIViewController class], @selector(presentViewController:animated:completion:), (IMP)CBPresent);
    gDidAppear = CBSwap([UIViewController class], @selector(viewDidAppear:), (IMP)CBDidAppear);

    gMain = mach_thread_self();
    gHi = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
    gLo = gHi - pthread_get_stacksize_np(pthread_self());
    CFRunLoopObserverRef obs = CFRunLoopObserverCreate(NULL, kCFRunLoopAfterWaiting | kCFRunLoopBeforeWaiting, true, INT_MAX,
                                                       CBRunLoop, NULL);
    CFRunLoopAddObserver(CFRunLoopGetMain(), obs, kCFRunLoopCommonModes);
    CFRelease(obs);
    pthread_t t;
    pthread_create(&t, NULL, CBWatch, NULL);
    pthread_detach(t);
    CBLog(@"[chạm] đo độ trễ chạm / luồng chính nghẽn (bản thử)");
}

@end
