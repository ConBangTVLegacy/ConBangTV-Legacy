#import "CBAppDelegate.h"
#import "CBCore.h"
#import "CBDisclaimer.h"
#import "CBDisclaimerViewController.h"
#import "CBHomeViewController.h"
#import "CBLog.h"
#import "CBNavController.h"
#import "CBPrefs.h"
#import "CBProfilesViewController.h"
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
    CBLog(@"=== Côn Bằng TV Legacy %@ (iOS 6) — %@ iOS %@, RAM %.0f MB", version, CBDeviceModel(),
          [UIDevice currentDevice].systemVersion, [NSProcessInfo processInfo].physicalMemory / 1048576.0);
    [CBCore start];
    [CBCore sync:@"app.setVersion" args:@{@"version": [@"ios6-" stringByAppendingString:version ?: @"0"]}];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [CBTheme apply];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [CBTheme bg];
    _home = [[CBHomeViewController alloc] init];
    self.nav = [[CBNavController alloc] initWithRootViewController:_home];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [self gates]; });
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
    CBProfilesViewController *p = [[CBProfilesViewController alloc] init];
    CBHomeViewController *home = _home;
    p.onDone = ^{ [home reload]; };
    [self.nav presentViewController:p animated:NO completion:nil];
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
