#import "CBDebug.h"
#import "CBAppDelegate.h"
#import "CBCore.h"
#import "CBImages.h"
#import "CBDetailViewController.h"
#import "CBFilterViewController.h"
#import "CBGridViewController.h"
#import "CBHomeViewController.h"
#import "CBLog.h"
#import "CBNavController.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBTheme.h"
#import "CBWaitPlayable.h"
#import "CBUpdate.h"
#import "CBProfilesViewController.h"
#import "CBSettingsViewController.h"
#import "CBSyncViewController.h"
#import "CBTouch.h"
#import "CBAlert.h"
#import "CBFPS.h"
#import "CBMiniPlayer.h"
#import "CBLatency.h"
#import "CBJSON.h"
#import "CBIPTV.h"
#import "CBListImport.h"
#import "CBLivePlayerViewController.h"
#import "CBTVSettingsViewController.h"
#import "CBTVViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#import <objc/message.h>

@interface CBIPTV (CBDebug)
+ (void)updateList:(NSString *)listId with:(NSDictionary *)changes;   // riêng của CBIPTV.m (lệnh tvage)
@end

@implementation CBDebug

+ (void)start {
    CBLog(@"[gỡ lỗi] nhận lệnh qua %@", [self cmdPath]);
    [CBLatency start];
    [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

+ (NSString *)cmdPath {
    return [CBDocumentsDir() stringByAppendingPathComponent:@"ConBangTV-cmd.txt"];
}

+ (void)poll {
    // Bản thử: app đang mở thì máy không tự khoá (khoá lâu → máy tắt Wi-Fi, mất SSH)
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSString *path = [self cmdPath];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    NSMutableArray *cmds = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *cmd = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (cmd.length) [cmds addObject:cmd];
    }
    [self runAll:cmds];
}

/// Chạy lần lượt; «wait <giây>» hoãn các lệnh sau (chờ hiệu ứng chuyển màn trước khi chụp)
+ (void)runAll:(NSArray *)cmds {
    for (NSUInteger i = 0; i < cmds.count; i++) {
        NSString *cmd = cmds[i];
        if ([cmd hasPrefix:@"wait"]) {
            double s = [[cmd substringFromIndex:4] doubleValue];
            NSArray *rest = [cmds subarrayWithRange:NSMakeRange(i + 1, cmds.count - i - 1)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((s > 0 ? s : 1) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self runAll:rest]; });
            return;
        }
        [self run:cmd];
    }
}

/// Bảng / khung cuộn đầu tiên (theo chiều sâu) của màn đang hiện
+ (UIScrollView *)scrollIn:(UIView *)v {
    if ([v isKindOfClass:[UIScrollView class]] && ![v isKindOfClass:[UITextView class]]) return (UIScrollView *)v;
    for (UIView *s in v.subviews) {
        UIScrollView *f = [self scrollIn:s];
        if (f) return f;
    }
    return nil;
}

/// Danh sách cuộn ngang (hàng phim ở trang chủ…) / dọc (bảng trang chủ, lưới kênh…) đầu tiên đang hiện
+ (UIScrollView *)scrollIn:(UIView *)v horizontal:(BOOL)h {
    if ([v isKindOfClass:[UIScrollView class]] && !v.hidden && v.window) {
        UIScrollView *s = (UIScrollView *)v;
        CGRect onScreen = [s convertRect:s.bounds toView:nil];
        BOOL more = h ? s.contentSize.width > s.bounds.size.width + 50 : s.contentSize.height > s.bounds.size.height + 50;
        if (more && CGRectIntersectsRect(onScreen, s.window.bounds)) return s;
    }
    for (UIView *s in v.subviews) {
        UIScrollView *f = [self scrollIn:s horizontal:h];
        if (f) return f;
    }
    return nil;
}

/// Hộp thoại UIAlertView đang hiện (iOS 6 đặt trong cửa sổ riêng)
+ (UIAlertView *)visibleAlert {
    CBAlert *own = [CBAlert visibleOwnAlert];   // iOS 7+: hộp tự vẽ (không nằm trong cây view của cửa sổ app)
    if (own) return own;
    for (UIWindow *w in [[UIApplication sharedApplication].windows reverseObjectEnumerator]) {
        UIAlertView *a = [self alertIn:w];
        if (a) return a;
    }
    return nil;
}

+ (UIButton *)buttonIn:(UIView *)v prefix:(NSString *)prefix {
    if ([v isKindOfClass:[UIButton class]] && !v.hidden && [[(UIButton *)v titleForState:UIControlStateNormal] hasPrefix:prefix]) {
        return (UIButton *)v;
    }
    for (UIView *s in v.subviews) {
        UIButton *b = [self buttonIn:s prefix:prefix];
        if (b) return b;
    }
    return nil;
}

+ (UIActionSheet *)visibleSheet {
    for (UIWindow *w in [[UIApplication sharedApplication].windows reverseObjectEnumerator]) {
        UIActionSheet *s = [self sheetIn:w];
        if (s) return s;
    }
    return nil;
}

+ (UIActionSheet *)sheetIn:(UIView *)v {
    if ([v isKindOfClass:[UIActionSheet class]]) return (UIActionSheet *)v;
    for (UIView *s in v.subviews) {
        UIActionSheet *a = [self sheetIn:s];
        if (a) return a;
    }
    return nil;
}

+ (UIAlertView *)alertIn:(UIView *)v {
    if ([v isKindOfClass:[UIAlertView class]]) return (UIAlertView *)v;
    for (UIView *s in v.subviews) {
        UIAlertView *a = [self alertIn:s];
        if (a) return a;
    }
    return nil;
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

+ (CBLivePlayerViewController *)live {
    UIViewController *vc = [self top];
    return [vc isKindOfClass:[CBLivePlayerViewController class]] ? (CBLivePlayerViewController *)vc : nil;
}

/// Màn «Truyền hình» trên cùng của thanh điều hướng (mở nếu chưa có)
+ (CBTVViewController *)tvScreen:(BOOL)open {
    CBNavController *nav = [self nav];
    for (UIViewController *vc in nav.viewControllers.reverseObjectEnumerator) {
        if ([vc isKindOfClass:[CBTVViewController class]]) {
            if (nav.topViewController != vc) [nav popToViewController:vc animated:NO];
            return (CBTVViewController *)vc;
        }
    }
    if (!open) return nil;
    CBTVViewController *tv = [[CBTVViewController alloc] init];
    [nav pushViewController:tv animated:NO];
    return tv;
}

/// Lệnh truyền hình (IPTV): tv, tvadd <url>, tvlists, tvuse <số>, tvrefresh, tvepg, tvgroup <số>, tvq <chữ>, tvplay <số>,
/// tvguide <số>, tvnext / tvprev / tvch <số> / tvpanel / tvpause / tvlive / tvsrc / tvclose (trình phát), tvstatus, tvsettings
+ (BOOL)runTV:(NSString *)verb arg:(NSString *)arg {
    if (![verb hasPrefix:@"tv"]) return NO;
    CBLivePlayerViewController *live = [self live];
    if ([verb isEqualToString:@"tv"]) {
        [self tvScreen:YES];
    } else if ([verb isEqualToString:@"tvadd"]) {
        NSDictionary *l = [CBIPTV addList:arg name:nil];
        CBLog(@"[gỡ lỗi] thêm danh sách %@ (%@)", CBStr(l, @"name"), CBStr(l, @"id"));
        [CBIPTV refresh:YES done:^(NSString *err) {
            CBLog(@"[gỡ lỗi] tải danh sách: %@", err ?: [NSString stringWithFormat:@"%lu kênh", (unsigned long)[CBIPTV channels].count]);
        }];
    } else if ([verb isEqualToString:@"tvlists"]) {
        for (NSDictionary *l in [CBIPTV lists]) {
            CBLog(@"[gỡ lỗi] danh sách %@ «%@» %@ — %@ kênh, lịch %@, lỗi %@", CBStr(l, @"id"), CBStr(l, @"name"), CBStr(l, @"url"),
                  l[@"count"], CBStr(l, @"epg"), CBStr(l, @"err"));
        }
    } else if ([verb isEqualToString:@"tvuse"]) {
        NSArray *lists = [CBIPTV lists];
        NSInteger i = arg.integerValue;
        if (i >= 0 && i < (NSInteger)lists.count) [CBIPTV setActive:CBStr(lists[i], @"id")];
    } else if ([verb isEqualToString:@"tvremove"]) {
        // tvremove <số> — xoá danh sách (số như tvlists)
        NSArray *lists = [CBIPTV lists];
        NSInteger i = arg.integerValue;
        if (i >= 0 && i < (NSInteger)lists.count) {
            CBLog(@"[gỡ lỗi] xoá danh sách «%@»", CBStr(lists[i], @"name"));
            [CBIPTV removeList:CBStr(lists[i], @"id")];
        }
    } else if ([verb isEqualToString:@"tvrefresh"]) {
        [CBIPTV refresh:YES done:^(NSString *err) { CBLog(@"[gỡ lỗi] tải lại danh sách: %@", err ?: @"xong"); }];
    } else if ([verb isEqualToString:@"tvepg"]) {
        [CBIPTV refreshGuide:YES done:^(NSString *err) {
            CBLog(@"[gỡ lỗi] tải lịch: %@ — %lu kênh có lịch", err ?: @"xong", (unsigned long)[CBIPTV guideChannelCount]);
        }];
    } else if ([verb isEqualToString:@"tvepgurl"]) {
        // tvepgurl <url> — đặt địa chỉ lịch phát sóng (trống = lấy từ danh sách) rồi tải
        [CBIPTV setEpgOverride:arg];
        [CBIPTV refreshGuide:YES done:^(NSString *err) {
            CBLog(@"[gỡ lỗi] tải lịch %@: %@ — %lu kênh có lịch", [CBIPTV epgUrl], err ?: @"xong", (unsigned long)[CBIPTV guideChannelCount]);
        }];
    } else if ([verb isEqualToString:@"tvgroup"]) {
        [[self tvScreen:YES] selectGroupAt:arg.integerValue];
    } else if ([verb isEqualToString:@"tvq"]) {
        [[self tvScreen:YES] setQuery:arg];
    } else if ([verb isEqualToString:@"tvplay"]) {
        [[self tvScreen:YES] openChannelAt:arg.integerValue];
    } else if ([verb isEqualToString:@"tvguide"]) {
        [[self tvScreen:YES] showGuideAt:arg.integerValue];
    } else if ([verb isEqualToString:@"tvsettings"]) {
        [[self nav] pushViewController:[[CBTVSettingsViewController alloc] init] animated:NO];
    } else if ([verb isEqualToString:@"tvnext"]) {
        [live nextChannel];
    } else if ([verb isEqualToString:@"tvprev"]) {
        [live previousChannel];
    } else if ([verb isEqualToString:@"tvch"]) {
        [live playChannelAt:arg.integerValue];
    } else if ([verb isEqualToString:@"tvpanel"]) {
        [live toggleChannels];
    } else if ([verb isEqualToString:@"tvpause"]) {
        [live togglePlay];
    } else if ([verb isEqualToString:@"tvlive"]) {
        [live goLive];
    } else if ([verb isEqualToString:@"tvsrc"]) {
        [live nextSource];
    } else if ([verb isEqualToString:@"tvclose"]) {
        [live close];
    } else if ([verb isEqualToString:@"tvstatus"]) {
        if (live) CBLog(@"[gỡ lỗi] [truyền hình] %@", [live statusLine]);
        CBTVViewController *tv = [self tvScreen:NO];
        NSArray *vis = tv.visibleChannels;
        CBLog(@"[gỡ lỗi] [truyền hình] danh sách %@ · %lu kênh · đang hiện %lu · lịch %lu kênh (%@) · %@",
              CBStr([CBIPTV activeList], @"name"), (unsigned long)[CBIPTV channels].count, (unsigned long)vis.count,
              (unsigned long)[CBIPTV guideChannelCount], [CBIPTV epgUrl], [CBIPTV status] ?: @"rảnh");
        for (NSUInteger i = 0; i < MIN(vis.count, 8u); i++) {
            NSDictionary *c = vis[i];
            NSDictionary *p = [CBIPTV nowFor:c at:[[NSDate date] timeIntervalSince1970]];
            CBLog(@"[gỡ lỗi]   %lu. %@ [%@] %lu nguồn — %@%@", (unsigned long)i, CBStr(c, @"n"), CBStr(c, @"g"),
                  (unsigned long)CBArr(c, @"urls").count, p ? CBStr(p, @"t") : @"(không lịch)",
                  [CBIPTV channelBadReason:c] ? [@" — LỖI: " stringByAppendingString:[CBIPTV channelBadReason:c]] : @"");
        }
    } else if ([verb isEqualToString:@"tvmatches"]) {
        // tvmatches [từ] — 12 ô đang hiện từ vị trí «từ»: trạng thái trận, nguồn (HLS / FLV), tiêu đề riêng
        NSArray *vis = [self tvScreen:NO].visibleChannels;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSUInteger from = (NSUInteger)MAX(0, arg.integerValue);
        for (NSUInteger i = from; i < MIN(vis.count, from + 12); i++) {
            NSDictionary *c = vis[i];
            NSMutableArray *kinds = [NSMutableArray array];
            for (NSString *u in CBArr(c, @"urls")) [kinds addObject:[[[NSURL URLWithString:u] path] hasSuffix:@".flv"] ? @"flv" : @"hls"];
            CBLog(@"[gỡ lỗi]   %lu. %@ [%@] — %@ · nguồn %@%@%@", (unsigned long)i, CBStr(c, @"n"), CBStr(c, @"g"),
                  [CBIPTV matchLine:c at:now] ?: @"(kênh thường)", [kinds componentsJoinedByString:@","],
                  CBStr(c, @"ua") ? @" · UA riêng" : @"", [CBIPTV hasKickReminder:c] ? @" · 🔔" : @"");
        }
    } else if ([verb isEqualToString:@"tvask"]) {
        [CBListImport ask:nil];   // hộp «Thêm danh sách kênh» như bấm «+ Thêm danh sách»
    } else if ([verb isEqualToString:@"tvupload"]) {
        // tvupload — hộp «Gửi tệp từ máy tính» (mở trang nhận tệp trên Wi-Fi)
        [CBListImport showUpload:nil];
        CBLog(@"[gỡ lỗi] [truyền hình] trang nhận tệp: %@", [CBListImport uploadAddress] ?: @"(không mở được)");
    } else if ([verb isEqualToString:@"tvfiles"]) {
        // tvfiles — tệp .m3u / .m3u8 tìm thấy trên máy (như «Chọn tệp .m3u trên máy này»)
        for (NSDictionary *f in [CBListImport localFiles]) CBLog(@"[gỡ lỗi] [truyền hình] tệp %@ (%@ byte)", f[@"path"], f[@"size"]);
    } else if ([verb isEqualToString:@"tvimport"]) {
        // tvimport <đường dẫn> — thêm danh sách từ tệp trên máy
        [CBListImport importFile:arg done:nil];
    } else if ([verb isEqualToString:@"tvage"]) {
        // tvage <phút> — lùi giờ «cập nhật» của danh sách đang chọn để thử tự làm mới (màn Truyền hình tải lại trong ≤ 30 giây)
        NSDictionary *l = [CBIPTV activeList];
        long long updated = CBNowMs() - (long long)(arg.doubleValue * 60000);
        if (l) [CBIPTV updateList:CBStr(l, @"id") with:@{@"updated": @(updated)}];
        CBLog(@"[gỡ lỗi] [truyền hình] danh sách «%@» coi như cập nhật lúc %@", CBStr(l, @"name"), [CBIPTV clock:updated / 1000]);
    } else if ([verb isEqualToString:@"tvremind"]) {
        // tvremind <ô> — bật / tắt «Nhắc lúc bóng lăn»
        NSArray *vis = [self tvScreen:NO].visibleChannels;
        NSInteger i = arg.integerValue;
        if (i >= 0 && i < (NSInteger)vis.count) {
            BOOL on = [CBIPTV toggleKickReminder:vis[i]];
            CBLog(@"[gỡ lỗi] [truyền hình] nhắc %@: %@", CBStr(vis[i], @"n"), on ? @"bật" : @"tắt");
        }
    } else {
        return NO;
    }
    return YES;
}

+ (void)run:(NSString *)cmd {
    // Không ghi khoá trong link ss:// (lệnh «alert 1 ss://…» khi thử Shadowsocks) vào nhật ký
    static NSRegularExpression *secret;
    if (!secret) secret = [NSRegularExpression regularExpressionWithPattern:@"ss://[^@ ]*@" options:0 error:NULL];
    CBLog(@"[gỡ lỗi] %@", [secret stringByReplacingMatchesInString:cmd options:0 range:NSMakeRange(0, cmd.length)
                                                      withTemplate:@"ss://***@"]);
    NSRange sp = [cmd rangeOfString:@" "];
    NSString *verb = sp.location == NSNotFound ? cmd : [cmd substringToIndex:sp.location];
    NSString *arg = sp.location == NSNotFound ? @"" : [[cmd substringFromIndex:sp.location + 1]
                                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *args = [arg componentsSeparatedByString:@" "];
    CBNavController *nav = [self nav];
    CBPlayerViewController *player = [self player];
    if ([self runTV:verb arg:arg]) return;
    if ([verb isEqualToString:@"shot"]) {
        [self shot:arg.length ? arg : @"shot"];
    } else if ([verb isEqualToString:@"film"]) {
        [nav pushViewController:[[CBDetailViewController alloc] initWithItem:@{@"url": arg}] animated:YES];
    } else if ([verb isEqualToString:@"play"]) {
        NSString *film = args.count ? args[0] : @"";
        NSString *ep = args.count > 1 ? args[1] : ([CBPrefs historyFor:film][@"epUrl"] ?: @"");
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:film detail:nil episode:ep resume:YES];
        // Đang có trình phát thì đóng trước (không chồng hai trình phát). Trình phát còn đang đóng dở (lệnh «close» ngay trước):
        // iOS 5 ném lỗi nếu mở màn mới lúc đó → cũng chờ
        double delay = player || nav.presentedViewController ? 1.0 : 0;
        [player close];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[self top] presentViewController:p animated:YES completion:nil];
        });
    } else if ([verb isEqualToString:@"search"]) {
        CBGridViewController *g = [[CBGridViewController alloc] initSearch];
        [nav pushViewController:g animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [g search:arg]; });
    } else if ([verb isEqualToString:@"home"]) {
        if (player) [player close];
        [nav popToRootViewControllerAnimated:NO];  // không hiệu ứng: lệnh sau mở màn mới ngay được (đẩy màn lúc đang lùi làm rối thanh tiêu đề iOS 6)
    } else if ([verb isEqualToString:@"back"]) {
        if (player) [player close];
        else if (nav.presentedViewController) [nav dismissViewControllerAnimated:YES completion:nil];
        else [nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"settings"]) {
        [nav pushViewController:[[CBSettingsViewController alloc] init] animated:YES];
    } else if ([verb isEqualToString:@"profiles"]) {
        CBProfilesViewController *p = [[CBProfilesViewController alloc] init];
        p.closable = YES;  // như bấm ảnh người xem ở trang chủ
        [[self top] presentViewController:p animated:YES completion:nil];
    } else if ([verb isEqualToString:@"rows"] || [verb isEqualToString:@"row"]) {
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        if (![root isKindOfClass:[CBHomeViewController class]]) return;
        CBHomeViewController *home = (CBHomeViewController *)root;
        if ([verb isEqualToString:@"row"]) {
            [nav popToRootViewControllerAnimated:NO];
            [home openRow:[args[0] integerValue] item:args.count > 1 ? [args[1] integerValue] : 0];
            return;
        }
        NSArray *rows = [home rows];
        for (NSUInteger r = 0; r < rows.count; r++) {
            NSArray *items = rows[r][@"items"];
            NSMutableArray *urls = [NSMutableArray array], *multi = [NSMutableArray array];
            for (NSUInteger i = 0; i < items.count; i++) {
                NSDictionary *it = items[i];
                [urls addObject:[NSString stringWithFormat:@"%@ <%@>", it[@"title"], it[@"url"]]];
                // phim có ở nhiều trang (nút «⇄» ở trang phim): «mục:số nguồn»
                if ([it[@"links"] count] > 1) [multi addObject:[NSString stringWithFormat:@"%lu:%lu", (unsigned long)i,
                                                                                         (unsigned long)[it[@"links"] count]]];
            }
            CBLog(@"[hàng %lu] %@ (%lu phim; nhiều nguồn: %@): %@", (unsigned long)r, rows[r][@"title"], (unsigned long)items.count,
                  multi.count ? [multi componentsJoinedByString:@" "] : @"không",
                  [[urls subarrayWithRange:NSMakeRange(0, MIN(urls.count, 6u))] componentsJoinedByString:@" | "]);
        }
    } else if ([verb isEqualToString:@"core"]) {
        // core <hàm> [json tham số] — gọi thẳng lõi, ghi thời gian
        NSString *method = args.count ? args[0] : @"";
        NSString *json = arg.length > method.length ? [arg substringFromIndex:method.length + 1] : @"{}";
        id a = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        long long t0 = CBNowMs();
        [CBCore call:method args:[a isKindOfClass:[NSDictionary class]] ? a : @{} done:^(id ok, NSString *err) {
            NSString *res = err ? [@"LỖI " stringByAppendingString:err] : nil;
            if (!res && [ok isKindOfClass:[NSDictionary class]] && ok[@"code"]) {
                res = [NSString stringWithFormat:@"HTTP %@, %lu ký tự", ok[@"code"], (unsigned long)[ok[@"text"] length]];
            }
            if (!res) res = [[ok description] substringToIndex:MIN([[ok description] length], 200u)];
            CBLog(@"[core] %@ %@ → %@ sau %lld ms", method, json, res, CBNowMs() - t0);
        }];
    } else if ([verb isEqualToString:@"pref"]) {
        // pref <khoá> <giá trị json> — đổi cài đặt rồi báo lõi mạng đổi
        NSString *key = args.count ? args[0] : @"";
        NSString *json = arg.length > key.length ? [arg substringFromIndex:key.length + 1] : @"null";
        id v = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                               options:NSJSONReadingAllowFragments error:NULL];
        [CBPrefs set:key value:v];
        [CBCore networkSettingsChanged];
        CBLog(@"[gỡ lỗi] %@ = %@", key, v);
    } else if ([verb isEqualToString:@"rawplay"] || [verb isEqualToString:@"rawmedia"]) {
        // rawplay <url>: AVPlayer phát thẳng; rawmedia <url>: qua cổng phát nội bộ của lõi (media.open) — ghi trạng thái 10 giây
        NSString *url = arg;
        if ([verb isEqualToString:@"rawmedia"]) {
            id o = [CBCore sync:@"media.open" args:@{@"src": arg, @"hls": @NO}];
            url = [o isKindOfClass:[NSDictionary class]] ? o[@"url"] : nil;
            CBLog(@"[raw] media.open → %@", url);
            if (!url) return;
        }
        [self rawPlay:url];
    } else if ([verb isEqualToString:@"crash"]) {
        // Dừng app có chủ đích: iOS ghi báo cáo crash kèm ngăn xếp của mọi luồng (xem lõi đang kẹt ở đâu)
        CBLog(@"[gỡ lỗi] tự dừng để lấy ngăn xếp các luồng");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ abort(); });
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
    } else if ([verb isEqualToString:@"eps"]) {
        [player toggleEpisodes];
    } else if ([verb isEqualToString:@"ep"]) {
        [player selectEpisode:[arg integerValue]];
    } else if ([verb isEqualToString:@"close"]) {
        [player close];
    } else if ([verb isEqualToString:@"alert"]) {
        // alert <số nút> [chữ] — điền ô nhập (nếu có) rồi bấm nút của hộp thoại đang hiện (0 = Huỷ / nút huỷ)
        UIAlertView *found = [self visibleAlert];
        if (!found) {
            CBLog(@"[gỡ lỗi] không có hộp thoại nào");
            return;
        }
        NSInteger idx = args.count ? [args[0] integerValue] : 0;
        if (found.alertViewStyle != UIAlertViewStyleDefault && args.count > 1) {
            [found textFieldAtIndex:0].text = args[1];
            if (args.count > 2 && found.alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) [found textFieldAtIndex:1].text = args[2];
        }
        CBLog(@"[gỡ lỗi] hộp «%@»: bấm nút %ld «%@»", found.title, (long)idx, [found buttonTitleAtIndex:idx]);
        id<UIAlertViewDelegate> d = found.delegate;
        if ([d respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [d alertView:found clickedButtonAtIndex:idx];
        [found dismissWithClickedButtonIndex:idx animated:YES];
    } else if ([verb isEqualToString:@"follow"]) {
        // follow <url phim> — theo dõi như bấm nút «Theo dõi» ở trang phim
        [CBCore call:@"site.detail" args:@{@"url": arg} done:^(id ok, NSString *err) {
            if (CBIsDict(ok)) [CBPrefs follow:ok];
            CBLog(@"[gỡ lỗi] theo dõi %@: %@", arg, CBIsDict(ok) ? @"được" : err);
        }];
    } else if ([verb isEqualToString:@"unfollow"]) {
        [CBPrefs unfollow:arg];
        CBLog(@"[gỡ lỗi] bỏ theo dõi %@", arg);
    } else if ([verb isEqualToString:@"more"]) {
        // more <hàng> — bấm «Xem thêm ›» của hàng trang chủ
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        [nav popToRootViewControllerAnimated:NO];
        if ([root isKindOfClass:[CBHomeViewController class]]) [(CBHomeViewController *)root openMore:[arg integerValue]];
    } else if ([verb isEqualToString:@"web"] || [verb isEqualToString:@"webframe"]) {
        // web <url> [referer] — mở trang trong UIWebView (WebKit của máy, hay WebKit mới của Web Port nếu đã bật cho app) để
        // xem trang hiển thị ra sao; referer: gửi kèm trang gốc (trang nhúng chặn yêu cầu không có trang gốc). webframe <url>
        // <trang gốc> — nạp trang trong khung iframe của một trang thuộc trang gốc (như trang web nhúng trình phát). «home» để đóng
        UIViewController *vc = [[UIViewController alloc] init];
        UIWebView *wv = [[UIWebView alloc] initWithFrame:nav.view.bounds];
        wv.scalesPageToFit = YES;
        wv.allowsInlineMediaPlayback = YES;
        wv.mediaPlaybackRequiresUserAction = NO;
        wv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view = wv;
        vc.title = @"Trang web";
        NSString *url = args.count ? args[0] : @"";
        NSString *ref = args.count > 1 ? args[1] : nil;
        if ([verb isEqualToString:@"webframe"] && ref) {
            NSString *html = [NSString stringWithFormat:@"<!doctype html><meta name=viewport content=\"width=device-width,"
                              "initial-scale=1\"><style>html,body{margin:0;height:100%%;background:#000}iframe{border:0;"
                              "width:100%%;height:100%%}</style><iframe src=\"%@\" allowfullscreen allow=\"autoplay;"
                              "fullscreen\"></iframe>", url];
            [wv loadHTMLString:html baseURL:[NSURL URLWithString:ref]];
        } else {
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
            if (ref) [req setValue:ref forHTTPHeaderField:@"Referer"];
            [wv loadRequest:req];
        }
        [nav pushViewController:vc animated:NO];
    } else if ([verb isEqualToString:@"browserpage"]) {
        // browserpage — trang nút «Mở trong Venetium» sẽ mở cho tập đang phát (nút chỉ hiện khi máy có Venetium)
        SEL s = NSSelectorFromString(@"browserPageURL");
        if ([player respondsToSelector:s]) {
            CBLog(@"[gỡ lỗi] trang mở trong trình duyệt: %@", ((id (*)(id, SEL))objc_msgSend)(player, s));
        }
    } else if ([verb isEqualToString:@"venetium"]) {
        // venetium — bấm «Mở trong Venetium» của trình phát (kể cả khi máy không có Venetium — để thử hộp nhắc NguonC)
        SEL s = NSSelectorFromString(@"openInVenetium");
        if ([player respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(player, s);
    } else if ([verb isEqualToString:@"wkinfo"]) {
        // wkinfo — WebKit nào đang nạp trong app (Web Port: thư viện ở /var/wkd), tính năng của trang đang mở trong UIWebView
        // (MediaSource, WebAssembly…) và trạng thái thẻ <video> đầu tiên của trang
        uint32_t n = _dyld_image_count(), wk = 0;
        for (uint32_t i = 0; i < n; i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && strstr(name, "/var/wkd/")) wk++;
        }
        CBLog(@"[gỡ lỗi] WebKit: %@ (%u thư viện /var/wkd)", wk ? @"Web Port" : @"của máy", wk);
        UIWebView *wv = nil;
        UIViewController *top = nav.topViewController;
        if ([top.view isKindOfClass:[UIWebView class]]) wv = (UIWebView *)top.view;
        if (wv) {
            NSString *js = @"(function(){var v=document.querySelector('video');var r='UA='+navigator.userAgent+' MSE='+"
                "(!!window.MediaSource)+' MMS='+(!!window.ManagedMediaSource)+' WASM='+(typeof WebAssembly)+' subtle='+"
                "(!!(window.crypto&&crypto.subtle))+' url='+location.href.slice(0,80);if(v){r+=' video: paused='+v.paused+"
                "' t='+v.currentTime.toFixed(1)+' rs='+v.readyState+' ns='+v.networkState+' err='+(v.error&&v.error.code)+"
                "' size='+v.videoWidth+'x'+v.videoHeight+' src='+(v.currentSrc||v.src||'').slice(0,90)}else{r+=' video=0 "
                "iframe='+document.getElementsByTagName('iframe').length}return r})()";
            CBLog(@"[gỡ lỗi] trang: %@", [wv stringByEvaluatingJavaScriptFromString:js]);
        }
    } else if ([verb isEqualToString:@"js"]) {
        // js <biểu thức> — chạy JavaScript trong UIWebView đang mở (lệnh web), ghi kết quả vào nhật ký
        UIViewController *top = nav.topViewController;
        if ([top.view isKindOfClass:[UIWebView class]]) {
            CBLog(@"[gỡ lỗi] js → %@", [(UIWebView *)top.view stringByEvaluatingJavaScriptFromString:arg]);
        }
    } else if ([verb isEqualToString:@"unhist"]) {
        // unhist <url phim> — xoá khỏi lịch sử / Xem tiếp (có dấu xoá — máy đã ghép cũng xoá)
        [CBPrefs removeHistory:arg];
        CBLog(@"[gỡ lỗi] đã xoá khỏi lịch sử: %@", arg);
    } else if ([verb isEqualToString:@"chip"]) {
        // chip <số> — bấm nút danh mục ở đầu trang chủ (0 = ★ Điểm IMDb cao)
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        [nav popToRootViewControllerAnimated:NO];
        if ([root isKindOfClass:[CBHomeViewController class]]) [(CBHomeViewController *)root openCategoryAt:[arg integerValue]];
    } else if ([verb isEqualToString:@"sync"]) {
        [nav pushViewController:[[CBSyncViewController alloc] init] animated:YES];
    } else if ([verb isEqualToString:@"syncpair"]) {
        // syncpair <địa chỉ[:cổng]> <mã> — ghép như bấm trên màn Đồng bộ (mở màn nếu chưa mở)
        UIViewController *vc = nav.topViewController;
        if (![vc isKindOfClass:[CBSyncViewController class]]) {
            vc = [[CBSyncViewController alloc] init];
            [nav pushViewController:vc animated:NO];
        }
        id hp = [CBCore sync:@"sync.parseAddress" args:@{@"input": args.count ? args[0] : @""}];
        if (CBIsDict(hp)) {
            [(CBSyncViewController *)vc pairHost:CBStr(hp, @"host") port:(NSInteger)CBNum(hp, @"port", 8791)
                                            code:args.count > 1 ? args[1] : @""];
        }
    } else if ([verb isEqualToString:@"pick"]) {
        // pick <hàng> [mục] — chọn một dòng của bảng đang hiện (mục âm = mục cuối, vd danh mục cuối trang chủ)
        UIViewController *top = [self top];
        if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
        if ([top respondsToSelector:@selector(openAt:)]) {  // lưới nút (Thể loại / Quốc gia)
            CBLog(@"[gỡ lỗi] chọn nút %@ của %@", args[0], NSStringFromClass([top class]));
            [(id)top openAt:[args[0] integerValue]];
            return;
        }
        if (![top isKindOfClass:[UITableViewController class]]) {
            CBLog(@"[gỡ lỗi] màn %@ không phải bảng", NSStringFromClass([top class]));
            return;
        }
        UITableViewController *tvc = (UITableViewController *)top;
        NSInteger sec = args.count > 1 ? [args[1] integerValue] : 0;
        if (sec < 0) sec += [tvc.tableView numberOfSections];
        NSInteger row = [args[0] integerValue];
        if (row < 0) row += [tvc.tableView numberOfRowsInSection:sec];  // âm = đếm từ cuối
        NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
        UITableViewCell *cell = [tvc tableView:tvc.tableView cellForRowAtIndexPath:ip];
        CBLog(@"[gỡ lỗi] chọn dòng %ld mục %ld: %@", (long)ip.row, (long)ip.section, cell.textLabel.text);
        if ([cell.accessoryView isKindOfClass:[UISegmentedControl class]]) {  // dòng có ô chọn: chọn ô kế tiếp
            UISegmentedControl *seg = (UISegmentedControl *)cell.accessoryView;
            seg.selectedSegmentIndex = (seg.selectedSegmentIndex + 1) % (NSInteger)seg.numberOfSegments;
            [seg sendActionsForControlEvents:UIControlEventValueChanged];
            return;
        }
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {  // dòng có công tắc: gạt công tắc
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            sw.on = !sw.on;
            [sw sendActionsForControlEvents:UIControlEventValueChanged];
            return;
        }
        [tvc tableView:tvc.tableView didSelectRowAtIndexPath:ip];
    } else if ([verb isEqualToString:@"scroll"]) {
        // scroll <y> — cuộn tới y điểm (âm = cuối danh sách)
        UIViewController *top = [self top];
        if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
        UIScrollView *sv = [self scrollIn:top.view];
        CGFloat maxY = MAX(0, sv.contentSize.height - sv.bounds.size.height + sv.contentInset.bottom);
        CGFloat y = [arg doubleValue] < 0 ? maxY : MIN(maxY, [arg doubleValue]);
        [sv setContentOffset:CGPointMake(sv.contentOffset.x, y) animated:NO];
        CBLog(@"[gỡ lỗi] cuộn %@ tới %.0f / %.0f", NSStringFromClass([sv class]), y, maxY);
    } else if ([verb isEqualToString:@"fps"]) {
        // fps <điểm/giây> <giây> [h] [p] — cuộn đều danh sách của màn đang thấy (h = hàng ngang đầu tiên đang thấy) và đo độ mượt;
        // p = lấy mẫu ngăn xếp luồng chính, ghi các hàm tốn thời gian nhất
        UIViewController *top = [self top];
        if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
        NSArray *flags = args.count > 2 ? [args subarrayWithRange:NSMakeRange(2, args.count - 2)] : @[];
        BOOL h = [flags containsObject:@"h"], p = [flags containsObject:@"p"];
        UIScrollView *sv = [self scrollIn:top.view horizontal:h];
        double speed = [args[0] doubleValue], secs = args.count > 1 ? [args[1] doubleValue] : 0;
        [CBFPS scroll:sv speed:speed > 0 ? speed : 1500 seconds:secs > 0 ? secs : 5 horizontal:h profile:p
                label:[NSString stringWithFormat:@"%@ › %@ %@", NSStringFromClass([top class]), NSStringFromClass([sv class]),
                                                 h ? @"ngang" : @"dọc"]];
    } else if ([verb isEqualToString:@"flat"]) {
        // flat — bỏ mọi bo góc (cornerRadius) trên màn đang thấy, kể cả ô đang nằm kho chờ: thử A/B xem bo góc tốn bao nhiêu
        UIViewController *top = [self top];
        if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
        __block NSUInteger n = 0;
        __block void (^walk)(UIView *) = nil;
        void (^w)(UIView *) = ^(UIView *v) {
            if (v.layer.cornerRadius > 0) {
                v.layer.cornerRadius = 0;
                n++;
            }
            for (UIView *s in v.subviews) walk(s);
        };
        walk = w;
        walk(top.view);
        walk = nil;
        CBLog(@"[gỡ lỗi] bỏ bo góc của %lu lớp", (unsigned long)n);
    } else if ([verb isEqualToString:@"dlg"]) {
        // dlg long|login|pin|none|many — mở thử từng kiểu hộp thoại (bấm bằng lệnh «alert …»)
        if ([arg isEqualToString:@"pin"]) {
            [CBAlert askPin:@"Mã PIN (thử)" message:@"Hộp thử — bấm Huỷ" done:^(NSString *pin) { CBLog(@"[gỡ lỗi] dlg pin → %@", pin); }];
            return;
        }
        NSMutableString *longText = [NSMutableString string];
        for (int i = 1; i <= 30; i++) [longText appendFormat:@"• Dòng %d của ghi chú dài — hộp phải cuộn được khi chữ dài hơn màn hình.\n", i];
        BOOL many = [arg isEqualToString:@"many"], none = [arg isEqualToString:@"none"];
        CBAlert *a = [CBAlert title:@"Hộp thử" message:[arg isEqualToString:@"long"] ? longText : @"Nội dung ngắn."
                             cancel:none ? nil : @"Huỷ" others:none ? nil : (many ? @[@"Một", @"Hai", @"Ba"] : @[@"OK"])
                               done:^(CBAlert *x, NSInteger i) { CBLog(@"[gỡ lỗi] dlg %@ → nút %ld", arg, (long)i); }];
        if ([arg isEqualToString:@"login"]) a.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
        [a show];
        if (none) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [a dismissWithClickedButtonIndex:0 animated:YES];
            });
        }
    } else if ([verb isEqualToString:@"mini"]) {
        // mini — thu nhỏ trình phát đang mở (phim / kênh); mini open — mở lại toàn màn hình; mini close — đóng khung nhỏ
        if ([arg isEqualToString:@"status"]) {
            // lớp hình đã hiện khung đầu chưa (readyForDisplay), đang phát không, nằm ở đâu
            UIView *v = nil;
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count && !v) {
                    UIView *x = stack.lastObject;
                    [stack removeLastObject];
                    if ([x.layer isKindOfClass:[AVPlayerLayer class]] && x.window) v = x;
                    [stack addObjectsFromArray:x.subviews];
                }
                if (v) break;
            }
            AVPlayerLayer *pl = (AVPlayerLayer *)v.layer;
            CBLog(@"[gỡ lỗi] mini: lớp hình %@ — readyForDisplay %d, rate %.2f, khung %@ trong %@", v ? @"có" : @"không thấy",
                  pl.readyForDisplay, pl.player.rate, NSStringFromCGRect([v convertRect:v.bounds toView:nil]),
                  NSStringFromClass([v.superview class]));
        } else if ([arg isEqualToString:@"open"]) {
            [CBMiniPlayer expand];
        } else if ([arg isEqualToString:@"close"]) {
            [CBMiniPlayer closeCurrent];
        } else {
            UIViewController *p = player ?: (UIViewController *)[self live];
            if ([p conformsToProtocol:@protocol(CBMiniPlayable)]) [CBMiniPlayer minimize:(UIViewController<CBMiniPlayable> *)p];
            else CBLog(@"[gỡ lỗi] không có trình phát nào đang mở");
        }
    } else if ([verb isEqualToString:@"minitest"]) {
        // minitest 1|0 — bật thu nhỏ cả trên máy RAM thấp (iPad 1) để thử; có hiệu lực ngay (nút ẩn / hiện ở lần mở trình phát sau)
        [[NSUserDefaults standardUserDefaults] setBool:[arg boolValue] forKey:@"CBMiniTest"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        CBLog(@"[gỡ lỗi] thu nhỏ trên máy RAM thấp: %@", [arg boolValue] ? @"bật (thử)" : @"tắt");
    } else if ([verb isEqualToString:@"owndialogs"]) {
        // owndialogs 1|0 — iOS 5 / 6 cũng dùng hộp thoại tự vẽ (có hiệu lực khi mở lại app)
        [[NSUserDefaults standardUserDefaults] setBool:[arg boolValue] forKey:@"CBOwnDialogs"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        CBLog(@"[gỡ lỗi] hộp thoại tự vẽ trên mọi iOS: %@ (mở lại app)", [arg boolValue] ? @"bật" : @"tắt");
    } else if ([verb isEqualToString:@"update"]) {
        [CBUpdate checkManual];  // như chạm «Phiên bản» trong Cài đặt
    } else if ([verb isEqualToString:@"sheet"]) {
        // sheet <số nút> — bấm nút của bảng chọn đang hiện (bảng tự vẽ của trình phát, hoặc UIActionSheet); số âm = nút Huỷ
        if (player && [player pressMenuItem:[arg integerValue]]) {
            CBLog(@"[gỡ lỗi] bảng chọn của trình phát: bấm mục %@", arg);
            return;
        }
        UIActionSheet *s = [self visibleSheet];
        if (!s) {
            CBLog(@"[gỡ lỗi] không có bảng chọn nào");
            return;
        }
        NSInteger i = [arg integerValue] < 0 ? s.cancelButtonIndex : [arg integerValue];
        CBLog(@"[gỡ lỗi] bảng chọn «%@»: bấm nút %ld «%@»", s.title, (long)i, [s buttonTitleAtIndex:i]);
        [s.delegate actionSheet:s clickedButtonAtIndex:i];
        [s dismissWithClickedButtonIndex:i animated:NO];
    } else if ([verb isEqualToString:@"tap"]) {
        // tap <chữ đầu> — bấm nút đang hiện có tên bắt đầu bằng chữ đó (màn trên cùng)
        UIViewController *top = [self top];
        if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
        UIButton *b = [self buttonIn:top.view prefix:arg];
        CBLog(@"[gỡ lỗi] tap «%@» → %@", arg, b ? [b titleForState:UIControlStateNormal] : @"không thấy nút");
        [b sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else if ([verb isEqualToString:@"menu"]) {
        [player showMenu];
    } else if ([verb isEqualToString:@"speed"]) {
        [player setSpeed:[arg floatValue]];
    } else if ([verb isEqualToString:@"sleep"]) {
        // sleep <giây> | sleep ep | sleep 0 — hẹn giờ tắt (giây để thử nhanh)
        [player setSleepAfter:[arg isEqualToString:@"ep"] ? 0 : [arg doubleValue] endOfEpisode:[arg isEqualToString:@"ep"]];
    } else if ([verb isEqualToString:@"notifyadd"]) {
        // notifyadd <url phim> <url tập> — như bấm «Báo khi xem được» ở trình phát (thử)
        NSString *ep = args.count > 1 ? args[1] : @"";
        [CBCore call:@"site.detail" args:@{@"url": args.count ? args[0] : @""} done:^(id d, NSString *err) {
            for (id g in CBArr(d, @"groups") ?: @[]) {
                for (id e in CBArr(g, @"episodes") ?: @[]) {
                    if ([CBStr(e, @"url") isEqualToString:ep]) [CBWaitPlayable add:d episode:e group:g];
                }
            }
            CBLog(@"[gỡ lỗi] chờ xem được: %lu tập", (unsigned long)[CBWaitPlayable list].count);
        }];
    } else if ([verb isEqualToString:@"notifycheck"]) {
        [CBWaitPlayable checkNow];
    } else if ([verb isEqualToString:@"notifylist"]) {
        for (NSDictionary *e in [CBWaitPlayable list]) CBLog(@"[gỡ lỗi] chờ: %@ — %@ (%@) %@", e[@"title"], e[@"epTitle"], e[@"group"], e[@"ep"]);
        CBLog(@"[gỡ lỗi] chờ xem được: %lu tập", (unsigned long)[CBWaitPlayable list].count);
    } else if ([verb isEqualToString:@"notifydel"]) {
        [CBWaitPlayable remove:arg];
    } else if ([verb isEqualToString:@"toast"]) {
        [CBTheme toast:arg.length ? arg : @"Thông báo thử"];
    } else if ([verb isEqualToString:@"fail"]) {
        [player debugStreamFailed];
    } else if ([verb isEqualToString:@"end"]) {
        [player debugPlayedToEnd];
    } else if ([verb isEqualToString:@"sub"]) {
        [player loadSubtitles:arg];
    } else if ([verb isEqualToString:@"touch"] || [verb isEqualToString:@"hold"]) {
        // touch <x> <y> — chạm (điểm trong cửa sổ, hệ dọc); hold <x> <y> [giây] — nhấn giữ (mặc định 1 giây)
        CGPoint p = CGPointMake([args[0] doubleValue], args.count > 1 ? [args[1] doubleValue] : 0);
        if ([verb isEqualToString:@"touch"]) [CBTouch tapAt:p];
        else [CBTouch holdAt:p seconds:args.count > 2 ? [args[2] doubleValue] : 1];
    } else if ([verb isEqualToString:@"drag"]) {
        // drag <x1> <y1> <x2> <y2> [giây] — vuốt (cuộn, kéo xuống để tải lại…)
        if (args.count >= 4) {
            [CBTouch dragFrom:CGPointMake([args[0] doubleValue], [args[1] doubleValue])
                           to:CGPointMake([args[2] doubleValue], [args[3] doubleValue])
                      seconds:args.count > 4 ? [args[4] doubleValue] : 0.5];
        }
    } else if ([verb isEqualToString:@"pull"]) {
        // pull — giả kéo trang chủ xuống rồi thả (thử «kéo xuống để tải lại» tự vẽ của iOS 5; UIRefreshControl iOS 6 cần kéo thật)
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        [nav popToRootViewControllerAnimated:NO];
        if ([root isKindOfClass:[UITableViewController class]]) {
            UITableView *tv = ((UITableViewController *)root).tableView;
            tv.contentOffset = CGPointMake(0, -80);
            id<UIScrollViewDelegate> d = (id<UIScrollViewDelegate>)root;
            if ([d respondsToSelector:@selector(scrollViewDidScroll:)]) [d scrollViewDidScroll:tv];
            if ([d respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
                [d scrollViewDidEndDragging:tv willDecelerate:NO];
            }
        }
    } else if ([verb isEqualToString:@"rawstop"]) {
        [self rawStop];
    } else if ([verb isEqualToString:@"orient"]) {
        // orient <1 dọc | 2 dọc ngược | 3 ngang phải | 4 ngang trái> — giả xoay máy (API riêng của UIDevice, chỉ để thử)
        SEL s = NSSelectorFromString(@"setOrientation:animated:");
        UIDevice *d = [UIDevice currentDevice];
        if ([d respondsToSelector:s]) {
            NSInteger o = [arg integerValue];
            BOOL animated = YES;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[d methodSignatureForSelector:s]];
            inv.target = d;
            inv.selector = s;
            [inv setArgument:&o atIndex:2];
            [inv setArgument:&animated atIndex:3];
            [inv invoke];
        }
        CBLog(@"[gỡ lỗi] xoay %@ → thanh trạng thái %ld", arg, (long)[UIApplication sharedApplication].statusBarOrientation);
    } else if ([verb isEqualToString:@"memwarn"]) {
        // memwarn — giả cảnh báo thiếu bộ nhớ (iOS 5: các màn của app phải giữ view, xem CBCompat.m)
        SEL s = NSSelectorFromString(@"_performMemoryWarning");
        UIApplication *app = [UIApplication sharedApplication];
        if ([app respondsToSelector:s]) ((void (*)(id, SEL))[app methodForSelector:s])(app, s);
        UIViewController *root = nav.viewControllers.count ? nav.viewControllers[0] : nil;
        CBLog(@"[gỡ lỗi] đã giả thiếu bộ nhớ — trang chủ còn view: %d", root.isViewLoaded);
    } else if ([verb isEqualToString:@"status"]) {
        CBLog(@"[trạng thái] %@", [CBImages debugStatus]);
        CBLog(@"[trạng thái] màn %@ | RAM %.1f MB%@", NSStringFromClass([[self top] class]), CBResidentMB(),
              player ? [@" | " stringByAppendingString:[player statusLine]] : @"");
    } else {
        CBLog(@"[gỡ lỗi] lệnh không hiểu: %@", cmd);
    }
}

static AVPlayer *gRawPlayer;
static AVPlayerLayer *gRawLayer;

+ (void)rawStop {
    [gRawPlayer pause];
    gRawPlayer = nil;
    [gRawLayer removeFromSuperlayer];
    gRawLayer = nil;
}

+ (void)rawPlay:(NSString *)url {
    [self rawStop];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    gRawPlayer = [AVPlayer playerWithPlayerItem:item];
    [gRawPlayer play];
    // Có khung hình (giải mã hình thật — so bộ nhớ với trình phát của app); «rawstop» để dừng
    gRawLayer = [AVPlayerLayer playerLayerWithPlayer:gRawPlayer];
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    gRawLayer.frame = w.bounds;
    gRawLayer.backgroundColor = [UIColor blackColor].CGColor;
    [w.layer addSublayer:gRawLayer];
    CBLog(@"[raw] phát %@", url);
    for (int i = 1; i <= 10; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AVPlayerItem *it = gRawPlayer.currentItem;
            if (it != item) return;
            NSError *e = it.error;
            NSError *u = e.userInfo[NSUnderlyingErrorKey];
            AVPlayerItemAccessLogEvent *a = it.accessLog.events.lastObject;
            AVPlayerItemErrorLogEvent *el = it.errorLog.events.lastObject;
            CBLog(@"[raw] %ds: status %ld, t=%.1f, dài %.0f, rate %.1f, đệm %@ | lỗi %@ %ld (gốc %@ %ld) %@ | access %@ %.0f byte | errorLog %ld %@ %@",
                  i, (long)it.status, CMTimeGetSeconds(gRawPlayer.currentTime),
                  it.status == AVPlayerItemStatusReadyToPlay && CMTIME_IS_NUMERIC(it.duration) ? CMTimeGetSeconds(it.duration) : -1, gRawPlayer.rate,
                  it.playbackLikelyToKeepUp ? @"đủ" : @"thiếu", e.domain, (long)e.code, u.domain, (long)u.code,
                  e.localizedFailureReason, a.URI, (double)a.numberOfBytesTransferred, (long)el.errorStatusCode, el.errorDomain,
                  el.errorComment);
        });
    }
}

/// Chụp màn hình: UIGetScreenImage (API riêng, chụp được cả hình video) — không có thì vẽ lại cửa sổ
+ (void)shot:(NSString *)name {
    NSString *dir = [CBDocumentsDir() stringByAppendingPathComponent:@"shots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage *img = nil;
    UIWindow *key = [UIApplication sharedApplication].keyWindow;
    CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
    // (iOS 7+: lớp video — AVPlayerLayer — không vào ảnh; xem hình có hiện không bằng «mini status» → readyForDisplay)
    if ([key respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
        // iOS 7+: UIGetScreenImage trả ảnh trắng (iOS 8) — vẽ lại các cửa sổ của app (cả cửa sổ hộp thoại)
        UIGraphicsBeginImageContextWithOptions(key.bounds.size, YES, 0);
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden) [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO];
        }
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    } else if (grab) {
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
