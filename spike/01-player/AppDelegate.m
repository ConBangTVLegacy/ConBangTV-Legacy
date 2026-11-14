#import "AppDelegate.h"
#import "TestsViewController.h"
#import "CBLog.h"
#import <AVFoundation/AVFoundation.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    CBLog(@"=== Khởi động: %@ iOS %@, RAM %.0f MB, log: %@", CBDeviceModel(), [UIDevice currentDevice].systemVersion,
          [NSProcessInfo processInfo].physicalMemory / 1048576.0, CBLogPath());

    NSError *err = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err]) {
        CBLog(@"AVAudioSession lỗi: %@", err);
    }

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[TestsViewController alloc] init]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *n) {
        CBLog(@"Âm thanh bị ngắt: %@", n.userInfo);
    }];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    CBLog(@"App: sắp mất quyền điều khiển (khoá màn hình / có cuộc gọi…)");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    CBLog(@"App: vào nền");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    CBLog(@"App: trở lại");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    CBLog(@"App: đang mở");
}

@end
