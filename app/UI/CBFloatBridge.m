#import "CBFloatBridge.h"
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"
#import "CBWatchLimit.h"

static NSString *const kShowFile = @"/var/mobile/Documents/ConBangTV-float.json";
static NSString *const kBackFile = @"/var/mobile/Documents/ConBangTV-float-back.json";
static NSString *const kTweak = @"/Library/MobileSubstrate/DynamicLibraries/CBFloat.dylib";

static __weak UIViewController<CBFloatPlayable> *gPlayer;   // trình phát đang trao cho khung nổi
static BOOL gFloating;
static double gHandoffTime;
static NSUInteger gGen;                                     // lần trao — bỏ hẹn giờ của lần trước
static AVAudioPlayer *gSilence;                             // âm thanh câm giữ app chạy nền (cổng phát nội bộ)
static NSDictionary *gPending;                              // khung trả lại lúc app còn nằm nền: làm khi app mở lên

@implementation CBFloatBridge

+ (BOOL)available {
    if ([[UIDevice currentDevice].systemVersion floatValue] < 7) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:kTweak]) return NO;
    // Người xem có giới hạn giờ xem: không cho ra ngoài app (khung nổi không đếm giờ xem, không dừng lúc tới giờ ngủ)
    NSString *pid = CBStr([CBPrefs currentProfile], @"id") ?: @"";
    return [CBWatchLimit dailyLimitFor:pid] <= 0 && [CBWatchLimit bedtimeFor:pid] < 0;
}

+ (BOOL)isFloating:(UIViewController *)player {
    return gFloating && player && gPlayer == player;
}

/// WAV 8 kHz mono 16 bit, 1 giây im lặng
+ (NSData *)silentWav {
    uint32_t rate = 8000, bytes = rate * 2;
    NSMutableData *d = [NSMutableData dataWithLength:44 + bytes];
    uint8_t *p = d.mutableBytes;
    uint32_t riff = 36 + bytes, fmtLen = 16, byteRate = rate * 2;
    uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
    memcpy(p, "RIFF", 4); memcpy(p + 4, &riff, 4); memcpy(p + 8, "WAVEfmt ", 8);
    memcpy(p + 16, &fmtLen, 4); memcpy(p + 20, &pcm, 2); memcpy(p + 22, &ch, 2); memcpy(p + 24, &rate, 4);
    memcpy(p + 28, &byteRate, 4); memcpy(p + 32, &align, 2); memcpy(p + 34, &bits, 2);
    memcpy(p + 36, "data", 4); memcpy(p + 40, &bytes, 4);
    return d;
}

static void CBFloatBack(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ [CBFloatBridge backFromFloat]; });
}

+ (void)setup {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CBFloatBack, CFSTR("vn.conbangtv.float.back"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // Ra trước (WillEnterForeground) chứ không chờ DidBecomeActive: còn bảng của SpringBoard (vd «Chưa cài đặt Thẻ SIM»),
        // Trung tâm thông báo đang kéo xuống… thì app đã hiện mà chưa «hoạt động» — chờ thì phim đứng tới khi tắt bảng
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(appForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
        [nc addObserver:self selector:@selector(appForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}

+ (void)handoff:(UIViewController<CBFloatPlayable> *)player {
    NSString *url = [player floatURL];
    if (!url.length) {
        [CBTheme toast:@"Chưa phát được — chờ hình lên rồi bấm lại."];
        return;
    }
    [self setup];
    double t = [player floatTime];
    if (!isfinite(t) || t < 0) t = 0;
    NSDictionary *show = @{@"url": url, @"time": @(t), @"title": [player floatTitle] ?: @"", @"live": @([player floatLive]),
                           @"fill": @([player floatFill])};
    if (![[NSJSONSerialization dataWithJSONObject:show options:0 error:NULL] writeToFile:kShowFile atomically:YES]) {
        [CBTheme toast:@"Không ghi được tệp cho khung nổi."];
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:kBackFile error:NULL];
    [player floatPause];
    gPlayer = player;
    gFloating = YES;
    gPending = nil;
    gHandoffTime = t;
    gGen++;
    [self startSilence];
    notify_post("vn.conbangtv.float.show");
    CBLog(@"Hình nổi: trao %@ %.0f s — %@", [player floatLive] ? @"kênh" : @"phim", t, [player floatTitle]);
    // Về màn hình chính (như bấm nút Home) — khung nổi hiện trên đó
    UIApplication *app = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"suspend");
    if ([app respondsToSelector:s]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [app performSelector:s];
#pragma clang diagnostic pop
    }
}

/// Giữ app chạy nền khi khung nổi phát: SpringBoard đọc luồng từ cổng phát nội bộ (127.0.0.1) của app — iOS treo app thì khung
/// nổi đứng hình. App có UIBackgroundModes audio: còn phát âm thanh (câm, trộn được với tiếng của khung nổi) thì iOS không treo.
+ (void)startSilence {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
    [s setActive:YES error:NULL];
    if (!gSilence) {
        gSilence = [[AVAudioPlayer alloc] initWithData:[self silentWav] error:NULL];
        gSilence.numberOfLoops = -1;
        gSilence.volume = 0;
    }
    [gSilence play];
}

+ (void)stopSilence:(BOOL)deactivate {
    [gSilence stop];
    gSilence = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if (deactivate) [s setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:NULL];
    [s setCategory:AVAudioSessionCategoryPlayback error:NULL];
}

/// Khung nổi trả lại (chạm khung → mở app; ✕ / khoá máy → đóng; mở app bằng biểu tượng → reclaim)
+ (void)backFromFloat {
    if (!gFloating) return;
    NSData *d = [NSData dataWithContentsOfFile:kBackFile];
    NSDictionary *back = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![back isKindOfClass:[NSDictionary class]]) back = @{@"action": @"close", @"time": @(gHandoffTime), @"playing": @NO};
    gFloating = NO;
    gGen++;
    BOOL open = [CBStr(back, @"action") isEqualToString:@"open"];
    CBLog(@"Hình nổi: trả lại — %@ %.0f s%@ (app %ld)", CBStr(back, @"action"), [back[@"time"] doubleValue],
          [back[@"playing"] boolValue] ? @" (đang phát)" : @"", (long)[UIApplication sharedApplication].applicationState);
    [self stopSilence:!open];
    // App còn nằm nền (SpringBoard đang mở app; hoặc anh bấm ✕ / khoá máy): để tới lúc app ra trước — AVPlayer có hình không phát
    // trong nền, tua lúc đó thì lỗi. Đóng khung thì ghi chỗ xem ngay (app sắp bị treo, có khi bị tắt hẳn).
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        gPending = back;
        double t = [back[@"time"] doubleValue];
        if (!open && isfinite(t) && t > 0) [gPlayer floatSaveAt:t];
        return;
    }
    [self apply:back];
}

+ (void)apply:(NSDictionary *)back {
    UIViewController<CBFloatPlayable> *p = gPlayer;
    gPending = nil;
    if (!p) return;
    double t = [back[@"time"] doubleValue];
    if (!isfinite(t) || t < 0) t = gHandoffTime;
    BOOL play = [CBStr(back, @"action") isEqualToString:@"open"] && [back[@"playing"] boolValue];
    CBLog(@"Hình nổi: %@ từ %.0f s (app %ld)", play ? @"phát tiếp" : @"lưu chỗ xem", t,
          (long)[UIApplication sharedApplication].applicationState);
    [p floatReturnedAt:t play:play];
}

+ (void)appForeground {
    // Làm sau khi UIKit chuyển xong (lúc WillEnterForeground lớp hình chưa gắn lại)
    dispatch_async(dispatch_get_main_queue(), ^{ [self appShown]; });
}

+ (void)appShown {
    if (gPending) {
        [self apply:gPending];
        return;
    }
    static NSUInteger reclaimed = NSUIntegerMax;   // ra trước + hoạt động: hai tin cho một lần mở — chỉ đòi lại một lần
    if (!gFloating || reclaimed == gGen) return;
    reclaimed = gGen;
    // Anh mở app bằng biểu tượng khi khung nổi còn hiện: lấy lại (SpringBoard trả chỗ xem qua float.back). SpringBoard không trả
    // lời (tinh chỉnh chưa nạp / đã khởi động lại) thì sau 1,5 giây tự phát tiếp từ chỗ lúc trao.
    CBLog(@"Hình nổi: app mở lại khi khung còn nổi — lấy lại");
    notify_post("vn.conbangtv.float.reclaim");
    NSUInteger gen = gGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gFloating || gGen != gen) return;
        CBLog(@"Hình nổi: SpringBoard không trả lại — phát tiếp từ %.0f s", gHandoffTime);
        gFloating = NO;
        gGen++;
        [self stopSilence:NO];
        [self apply:@{@"action": @"open", @"time": @(gHandoffTime), @"playing": @YES}];
    });
}

@end
