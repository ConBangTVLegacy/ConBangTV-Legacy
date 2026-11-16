#import "CBAppDelegate.h"
#import "CBCompat.h"
#import "CBCore.h"
#import "CBDisclaimer.h"
#import "CBDisclaimerViewController.h"
#import "CBHomeViewController.h"
#import "CBLog.h"
#import "CBNavController.h"
#import "CBJSON.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBTVViewController.h"
#import "CBProfilesViewController.h"
#import "CBSync.h"
#import "CBUpdate.h"
#import "CBWaitPlayable.h"
#import "CBTheme.h"
#import <AVFoundation/AVFoundation.h>
#ifdef DEBUG
#import "CBDebug.h"
#endif

@implementation CBAppDelegate {
    CBHomeViewController *_home;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    CBLog(@"=== Côn Bằng TV Legacy %@ (dựng cho iOS 5 / 6%@) — %@ iOS %@, RAM %.0f MB", version, CBOldIOS() ? @", đang chạy kiểu iOS 5" : @"", CBDeviceModel(),
          [UIDevice currentDevice].systemVersion, [NSProcessInfo processInfo].physicalMemory / 1048576.0);
    [CBCore start];
    [CBPrefs repairStoredFlags];
    [CBCore sync:@"app.setVersion" args:@{@"version": [(CBOldIOS() ? @"ios5-" : @"ios6-") stringByAppendingString:version ?: @"0"]}];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [CBTheme apply];
    [CBSync start];
    [CBUpdate start];
    [CBWaitPlayable start];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [CBTheme bg];
    _home = [[CBHomeViewController alloc] init];
    self.nav = [[CBNavController alloc] initWithRootViewController:_home];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [self gates]; });
    // Mở app bằng thông báo «Nhắc tôi» của lịch phát sóng: phát kênh đó (sau màn miễn trừ / chọn người xem)
    UILocalNotification *ln = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    NSString *tvKey = CBIsStr(ln.userInfo[@"iptv"]) ? ln.userInfo[@"iptv"] : nil;
    if (tvKey.length) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.nav.presentedViewController) [CBTVViewController playKey:tvKey from:self.nav];
        });
    }
#ifdef DEBUG
    [CBDebug start];
#endif
    return YES;
}

/// Lần đầu: bấm «Đồng ý» miễn trừ trách nhiệm; nhiều người xem: hỏi «Ai đang xem?»
- (void)gates {
    if ([CBPrefs disclaimerVersion] < CBDisclaimerVersion) {
        CBDisclaimerViewController *d = [[CBDisclaimerViewController alloc] initGate:YES];
        __weak CBAppDelegate *weakSelf = self;
        d.onAccept = ^{ [weakSelf askProfile]; };
        [self.nav presentViewController:d animated:NO completion:nil];
        return;
    }
    [self askProfile];
}

- (void)askProfile {
    if ([CBPrefs profiles].count < 2 || ![CBPrefs askProfile]) return;
    // Chọn xong: trang chủ tự tải lại ở viewWillAppear nếu người xem đổi (trước đây tải thêm một lần nữa ở đây)
    CBProfilesViewController *p = [[CBProfilesViewController alloc] init];
    [self.nav presentViewController:p animated:NO completion:nil];
}

/// Thông báo «Nhắc tôi» (lịch phát sóng): app đang mở thì hỏi; chạm thông báo khi app nằm nền thì phát luôn
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)n {
    NSString *key = CBIsStr(n.userInfo[@"iptv"]) ? n.userInfo[@"iptv"] : nil;
    if (!key.length) return;
    CBLog(@"Truyền hình: thông báo nhắc %@ (%@)", key, n.alertBody);
    if (application.applicationState == UIApplicationStateActive) {
        NSString *title = CBIsStr(n.userInfo[@"title"]) ? n.userInfo[@"title"] : @"Sắp phát";   // «Bóng lăn» (nhắc trận đấu)
        [[CBAlert title:title message:n.alertBody cancel:@"Để sau" others:@[@"Xem ngay"] done:^(CBAlert *a, NSInteger i) {
            if (i != a.cancelButtonIndex) [CBTVViewController playKey:key from:self.nav];
        }] show];
    } else {
        [CBTVViewController playKey:key from:self.nav];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Nằm nền lâu / khoá màn hình: iOS thu hồi cổng nghe của app → mở lại trước khi trang / trình phát gọi mạng
    [CBCore reviveLocalPorts];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [CBCore sync:@"prefs.flush" args:nil];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [CBCore sync:@"prefs.flush" args:nil];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    CBLog(@"Cảnh báo thiếu bộ nhớ (RAM app %.0f MB)", CBResidentMB());
}

@end
