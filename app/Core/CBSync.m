#import "CBSync.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"
#import <UIKit/UIKit.h>

NSString *const CBSyncDataChanged = @"CBSyncDataChanged";
NSString *const CBSyncStateChanged = @"CBSyncStateChanged";

static BOOL gPlaying;
static long long gLastActive;

@implementation CBSync

+ (void)start {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(coreEvent:) name:@"CBCoreEvent" object:nil];
    [nc addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(foreground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [CBCore sync:@"sync.appStarted" args:nil];
    gLastActive = CBNowMs();
    [NSTimer scheduledTimerWithTimeInterval:180 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    id peers = [CBCore sync:@"sync.peers" args:nil];
    CBLog(@"Đồng bộ: %lu máy đã ghép (cổng %@)", (unsigned long)(CBIsArr(peers) ? [peers count] : 0),
          [CBCore sync:@"sync.port" args:nil]);
}

+ (void)coreEvent:(NSNotification *)n {
    NSString *name = n.userInfo[@"event"];
    if ([name isEqualToString:@"sync.dataChanged"]) {
        CBLog(@"Đồng bộ: có dữ liệu mới từ máy khác");
        [CBPrefs invalidateCaches];
        [[NSNotificationCenter defaultCenter] postNotificationName:CBSyncDataChanged object:nil];
    } else if ([name isEqualToString:@"sync.stateChanged"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:CBSyncStateChanged object:nil];
    } else if ([name isEqualToString:@"sync.message"]) {
        id m = n.userInfo[@"data"];
        if (CBIsStr(m) && [m length]) {
            CBLog(@"Đồng bộ: %@", m);
            [CBTheme toast:m];
        }
    }
}

+ (void)soon:(double)seconds {
    [CBCore sync:@"sync.soon" args:@{@"seconds": @(seconds)}];
}

+ (void)setPlaying:(BOOL)playing {
    gPlaying = playing;
    if (!playing) [self soon:1];  // thoát phim: gửi chỗ đang xem / tập đã xem sang máy kia
}

+ (void)tick {
    if (gPlaying || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    [self soon:1];
}

/// iOS treo app ở nền (cổng nghe bị hệ thống thu lại): đóng cổng, quay lại thì mở lại và đồng bộ (tối đa 1 phút một lần)
+ (void)background {
    [CBCore sync:@"sync.stop" args:nil];
}

+ (void)foreground {
    [CBCore sync:@"sync.appStarted" args:nil];
    if (CBNowMs() - gLastActive > 60000) {
        gLastActive = CBNowMs();
        [self soon:1];
    }
}

@end
