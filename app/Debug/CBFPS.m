#import "CBFPS.h"
#import "CBLog.h"
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>

// SDK iOS không kèm <servers/bootstrap.h>
extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);

// Bộ đếm khung hình của render server (backboardd trên iOS 6) — hàm riêng của QuartzCore mà Instruments › Core Animation dùng.
// Đếm cả khung GPU vẽ chậm (vẽ ngoài màn hình, hoà trộn) — CADisplayLink của app thì không thấy phần đó.
typedef uint32_t (*CBFrameCounterFn)(mach_port_t);

static CBFrameCounterFn CBFrameCounter(void) {
    static CBFrameCounterFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
        fn = qc ? (CBFrameCounterFn)dlsym(qc, "CARenderServerGetFrameCounter") : NULL;
    });
    return fn;
}

static mach_port_t CBRenderPort(void) {
    static mach_port_t port;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (bootstrap_look_up(bootstrap_port, "com.apple.CARenderServer", &port) != KERN_SUCCESS) port = MACH_PORT_NULL;
    });
    return port;
}

static uint32_t CBFrames(void) {
    CBFrameCounterFn fn = CBFrameCounter();
    return fn ? fn(CBRenderPort()) : 0;
}

uint32_t CBRenderFrames(void) {
    return CBFrames();
}

// ---- Lấy mẫu ngăn xếp luồng chính (fps … p): luồng phụ tạm dừng luồng chính vài ms một lần, đi theo chuỗi khung (r7 = con trỏ
// khung trên armv7), ghi địa chỉ vào bộ đệm cấp sẵn — lúc luồng chính đang dừng KHÔNG được cấp phát / gọi dladdr (luồng chính có thể
// đang giữ khoá malloc / dyld). Đổi địa chỉ ra tên hàm sau khi xong, trên luồng chính.
enum { kMaxSamples = 4000, kMaxDepth = 40 };
static uintptr_t gStacks[kMaxSamples][kMaxDepth];
static uint8_t gDepth[kMaxSamples];
static volatile int gSamples;
static volatile BOOL gSampling;
static thread_act_t gMainThread;
static uintptr_t gStackLo, gStackHi;   // ngăn xếp luồng chính (lấy trên luồng chính lúc bắt đầu)

int CBCaptureStack(thread_act_t thread, uintptr_t lo, uintptr_t hi, uintptr_t *out, int max) {
    if (thread_suspend(thread) != KERN_SUCCESS) return 0;
    int d = 0;
#if defined(__arm__)
    arm_thread_state_t st;
    mach_msg_type_number_t n = ARM_THREAD_STATE_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE, (thread_state_t)&st, &n) == KERN_SUCCESS) {
        out[d++] = st.__pc;
        if (d < max) out[d++] = st.__lr;   // hàm lá chưa đẩy khung: lr là nơi gọi
        uintptr_t fp = st.__r[7];
        while (d < max && fp >= lo && fp + 8 <= hi && !(fp & 3)) {
            uintptr_t next = ((uintptr_t *)fp)[0], ret = ((uintptr_t *)fp)[1];
            if (!ret) break;
            out[d++] = ret;
            if (next <= fp) break;
            fp = next;
        }
    }
#endif
    thread_resume(thread);
    return d;
}

static void *CBSampler(void *arg) {
    while (gSampling && gSamples < kMaxSamples) {
        usleep(2500);
        int i = gSamples, d = CBCaptureStack(gMainThread, gStackLo, gStackHi, gStacks[i], kMaxDepth);
        if (!d) continue;
        gDepth[i] = (uint8_t)d;
        gSamples = i + 1;
    }
    return NULL;
}

/// Tên hàm (bỏ phần lặp của vòng chạy / khung chung) — dladdr thấy cả ký hiệu cục bộ của app (bản thử không bỏ ký hiệu)
NSString *CBSymbol(uintptr_t addr, NSMutableDictionary *cache) {
    NSNumber *key = @(addr);
    NSString *s = cache[key];
    if (s) return s;
    Dl_info info;
    memset(&info, 0, sizeof info);
    BOOL found = dladdr((void *)(addr - 1), &info) != 0;
    if (found && info.dli_sname) {
        s = @(info.dli_sname);
    } else if (found && info.dli_fname) {
        const char *slash = strrchr(info.dli_fname, '/');
        s = [NSString stringWithFormat:@"%s+0x%lx", slash ? slash + 1 : info.dli_fname, (unsigned long)(addr - (uintptr_t)info.dli_fbase)];
    } else {
        s = [NSString stringWithFormat:@"0x%lx", (unsigned long)addr];
    }
    cache[key] = s;
    return s;
}

static void CBReportSamples(void) {
    int total = gSamples;
    if (!total) {
        CBLog(@"[fps] không lấy được mẫu ngăn xếp nào");
        return;
    }
    NSMutableDictionary *cache = [NSMutableDictionary dictionary], *incl = [NSMutableDictionary dictionary],
                        *top = [NSMutableDictionary dictionary];
    NSArray *skip = @[@"main", @"UIApplicationMain", @"GSEventRunModal", @"CFRunLoopRunSpecific", @"CFRunLoopRunInMode", @"start",
                      @"__CFRunLoopRun", @"__CFRunLoopDoObservers", @"__CFRUNLOOP_IS_CALLING_OUT_TO_AN_OBSERVER_CALLBACK_FUNCTION__",
                      @"__CFRunLoopDoSources0", @"__CFRunLoopDoSource1", @"__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__",
                      @"__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE1_PERFORM_FUNCTION__", @"_UIApplicationHandleEvent",
                      @"PurpleEventCallback", @"_ZN2CA7Display11DisplayLink14dispatch_itemsEyyy",
                      @"_ZN2CA7Display15DisplayLinkItem8dispatchEv", @"CA::Display::DisplayLink::dispatch(unsigned long long, unsigned long long)"];
    int idle = 0;
    for (int i = 0; i < total; i++) {
        NSMutableSet *seen = [NSMutableSet set];
        for (int d = 0; d < gDepth[i]; d++) {
            NSString *s = CBSymbol(gStacks[i][d], cache);
            if (d == 0) {
                top[s] = @([top[s] intValue] + 1);
                if ([s hasPrefix:@"mach_msg_trap"]) idle++;
            }
            if ([skip containsObject:s] || [seen containsObject:s]) continue;
            [seen addObject:s];
            incl[s] = @([incl[s] intValue] + 1);
        }
    }
    NSArray *(^best)(NSDictionary *, NSUInteger) = ^NSArray *(NSDictionary *m, NSUInteger n) {
        NSArray *k = [m keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
        return [k subarrayWithRange:NSMakeRange(0, MIN(n, k.count))];
    };
    CBLog(@"[fps] %d mẫu ngăn xếp luồng chính, rảnh (chờ sự kiện) %.0f%%", total, idle * 100.0 / total);
    for (NSString *s in best(incl, 28)) CBLog(@"[fps]   gồm %4.1f%%  %@", [incl[s] intValue] * 100.0 / total, s);
    for (NSString *s in best(top, 12)) CBLog(@"[fps]   đỉnh %4.1f%%  %@", [top[s] intValue] * 100.0 / total, s);
}

@implementation CBFPS {
    UIScrollView *_sv;
    CGFloat _speed;
    BOOL _horizontal, _profile;
    double _seconds;
    NSString *_label;
    CADisplayLink *_link;
    CFTimeInterval _start, _last, _worst;
    NSUInteger _ticks, _slow;  // nhịp luồng chính; nhịp trễ > 1,5 khung (hụt ít nhất một khung)
    uint32_t _frames0;
    pthread_t _sampler;
    CBFPS *_self;
}

+ (void)scroll:(UIScrollView *)sv speed:(CGFloat)speed seconds:(double)seconds horizontal:(BOOL)horizontal label:(NSString *)label {
    [self scroll:sv speed:speed seconds:seconds horizontal:horizontal profile:NO label:label];
}

+ (void)scroll:(UIScrollView *)sv speed:(CGFloat)speed seconds:(double)seconds horizontal:(BOOL)horizontal profile:(BOOL)profile
         label:(NSString *)label {
    if (!sv) {
        CBLog(@"[fps] không thấy danh sách cuộn");
        return;
    }
    CBFPS *f = [[CBFPS alloc] init];
    f->_sv = sv;
    f->_speed = speed;
    f->_seconds = seconds;
    f->_horizontal = horizontal;
    f->_profile = profile && !gSampling;
    f->_label = label;
    f->_self = f;
    f->_link = [CADisplayLink displayLinkWithTarget:f selector:@selector(tick:)];
    [f->_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    if (!_start) {
        _start = _last = now;
        _frames0 = CBFrames();
        if (_profile) {
            gMainThread = mach_thread_self();
            gStackHi = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
            gStackLo = gStackHi - pthread_get_stacksize_np(pthread_self());
            gSamples = 0;
            gSampling = YES;
            pthread_create(&_sampler, NULL, CBSampler, NULL);
        }
        return;
    }
    CFTimeInterval dt = now - _last;
    _last = now;
    _ticks++;
    _worst = MAX(_worst, dt);
    if (dt > 1.5 / 60) _slow++;
    // Cuộn theo thời gian thật (máy chậm thì mỗi nhịp đi xa hơn — như ngón tay)
    CGPoint off = _sv.contentOffset;
    CGFloat maxX = MAX(0, _sv.contentSize.width - _sv.bounds.size.width), maxY = MAX(0, _sv.contentSize.height - _sv.bounds.size.height);
    CGFloat step = _speed * dt;
    if (_horizontal) {
        off.x += step;
        if (off.x > maxX || off.x < 0) {
            _speed = -_speed;
            off.x = MAX(0, MIN(maxX, off.x));
        }
    } else {
        off.y += step;
        if (off.y > maxY || off.y < 0) {
            _speed = -_speed;
            off.y = MAX(0, MIN(maxY, off.y));
        }
    }
    _sv.contentOffset = off;
    if (now - _start < _seconds) return;
    [_link invalidate];
    _link = nil;
    double secs = now - _start;
    uint32_t frames = CBFrames() - _frames0;
    if (_profile) {
        gSampling = NO;
        pthread_join(_sampler, NULL);
        mach_port_deallocate(mach_task_self(), gMainThread);
    }
    CBLog(@"[fps] %@: %.1f s — máy vẽ %@ khung/s; luồng chính %.1f nhịp/s, hụt khung %lu lần, nhịp chậm nhất %.0f ms%@",
          _label, secs, CBFrameCounter() ? [NSString stringWithFormat:@"%.1f", frames / secs] : @"? (không có bộ đếm)",
          _ticks / secs, (unsigned long)_slow, _worst * 1000, _profile ? @" (đang lấy mẫu — số đo chậm hơn thật)" : @"");
    if (_profile) CBReportSamples();
    _sv = nil;
    _self = nil;
}

@end
