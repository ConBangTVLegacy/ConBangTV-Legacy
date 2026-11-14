#import "CBDebug.h"
#import "CBAppDelegate.h"
#import "CBDetailViewController.h"
#import "CBGridViewController.h"
#import "CBHomeViewController.h"
#import "CBLog.h"
#import "CBNavController.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBProfilesViewController.h"
#import "CBSettingsViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

@implementation CBDebug

+ (void)start {
    CBLog(@"[gỡ lỗi] nhận lệnh qua %@", [self cmdPath]);
    [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

+ (NSString *)cmdPath {
    return [CBDocumentsDir() stringByAppendingPathComponent:@"ConBangTV-cmd.txt"];
}

+ (void)poll {
    NSString *path = [self cmdPath];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *cmd = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (cmd.length) [self run:cmd];
    }
}

+ (CBNavController *)nav {
    return [(CBAppDelegate *)[UIApplication sharedApplication].delegate nav];
}

+ (UIViewController *)top {
    UIViewController *vc = [self nav];
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (CBPlayerViewController *)player {
    UIViewController *vc = [self top];
    return [vc isKindOfClass:[CBPlayerViewController class]] ? (CBPlayerViewController *)vc : nil;
}

+ (void)run:(NSString *)cmd {
    CBLog(@"[gỡ lỗi] %@", cmd);
    NSRange sp = [cmd rangeOfString:@" "];
    NSString *verb = sp.location == NSNotFound ? cmd : [cmd substringToIndex:sp.location];
    NSString *arg = sp.location == NSNotFound ? @"" : [[cmd substringFromIndex:sp.location + 1]
                                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *args = [arg componentsSeparatedByString:@" "];
    CBNavController *nav = [self nav];
    CBPlayerViewController *player = [self player];
    if ([verb isEqualToString:@"shot"]) {
        [self shot:arg.length ? arg : @"shot"];
    } else if ([verb isEqualToString:@"film"]) {
        [nav pushViewController:[[CBDetailViewController alloc] initWithItem:@{@"url": arg}] animated:YES];
    } else if ([verb isEqualToString:@"play"]) {
        NSString *film = args.count ? args[0] : @"";
        NSString *ep = args.count > 1 ? args[1] : ([CBPrefs historyFor:film][@"epUrl"] ?: @"");
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:film detail:nil episode:ep resume:YES];
        [[self top] presentViewController:p animated:YES completion:nil];
    } else if ([verb isEqualToString:@"search"]) {
        CBGridViewController *g = [[CBGridViewController alloc] initSearch];
        [nav pushViewController:g animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [g search:arg]; });
    } else if ([verb isEqualToString:@"home"]) {
        if (player) [player close];
        [nav popToRootViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"back"]) {
        if (player) [player close];
        else if (nav.presentedViewController) [nav dismissViewControllerAnimated:YES completion:nil];
        else [nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"settings"]) {
        [nav pushViewController:[[CBSettingsViewController alloc] init] animated:YES];
    } else if ([verb isEqualToString:@"profiles"]) {
        [[self top] presentViewController:[[CBProfilesViewController alloc] init] animated:YES completion:nil];
    } else if ([verb isEqualToString:@"reload"]) {
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        if ([root isKindOfClass:[CBHomeViewController class]]) [(CBHomeViewController *)root reload];
    } else if ([verb isEqualToString:@"seek"]) {
        [player seekTo:[arg doubleValue]];
    } else if ([verb isEqualToString:@"fwd"]) {
        [player seekBy:[arg doubleValue]];
    } else if ([verb isEqualToString:@"toggle"]) {
        [player togglePlay];
    } else if ([verb isEqualToString:@"next"]) {
        [player nextEpisode];
    } else if ([verb isEqualToString:@"prev"]) {
        [player previousEpisode];
    } else if ([verb isEqualToString:@"server"]) {
        [player selectServer:[arg integerValue]];
    } else if ([verb isEqualToString:@"close"]) {
        [player close];
    } else if ([verb isEqualToString:@"status"]) {
        CBLog(@"[trạng thái] màn %@ | RAM %.1f MB%@", NSStringFromClass([[self top] class]), CBResidentMB(),
              player ? [@" | " stringByAppendingString:[player statusLine]] : @"");
    } else {
        CBLog(@"[gỡ lỗi] lệnh không hiểu: %@", cmd);
    }
}

/// Chụp màn hình: UIGetScreenImage (API riêng, chụp được cả hình video) — không có thì vẽ lại cửa sổ
+ (void)shot:(NSString *)name {
    NSString *dir = [CBDocumentsDir() stringByAppendingPathComponent:@"shots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage *img = nil;
    CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
    if (grab) {
        CGImageRef cg = grab();
        if (cg) {
            img = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
        }
    }
    if (!img) {
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0);
        [w.layer renderInContext:UIGraphicsGetCurrentContext()];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    CBLog(@"[gỡ lỗi] ảnh màn hình %@ (%.0fx%.0f)", path, img.size.width * img.scale, img.size.height * img.scale);
}

@end
