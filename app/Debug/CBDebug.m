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
#import "CBProfilesViewController.h"
#import "CBSettingsViewController.h"
#import "CBSyncViewController.h"
#import "CBJSON.h"
#import <AVFoundation/AVFoundation.h>
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

/// Hộp thoại UIAlertView đang hiện (iOS 6 đặt trong cửa sổ riêng)
+ (UIAlertView *)visibleAlert {
    for (UIWindow *w in [[UIApplication sharedApplication].windows reverseObjectEnumerator]) {
        UIAlertView *a = [self alertIn:w];
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
    if ([verb isEqualToString:@"shot"]) {
        [self shot:arg.length ? arg : @"shot"];
    } else if ([verb isEqualToString:@"film"]) {
        [nav pushViewController:[[CBDetailViewController alloc] initWithItem:@{@"url": arg}] animated:YES];
    } else if ([verb isEqualToString:@"play"]) {
        NSString *film = args.count ? args[0] : @"";
        NSString *ep = args.count > 1 ? args[1] : ([CBPrefs historyFor:film][@"epUrl"] ?: @"");
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:film detail:nil episode:ep resume:YES];
        // Đang có trình phát thì đóng trước (không chồng hai trình phát)
        double delay = player ? 0.8 : 0;
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
        [[self top] presentViewController:[[CBProfilesViewController alloc] init] animated:YES completion:nil];
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
            NSMutableArray *urls = [NSMutableArray array];
            for (NSDictionary *it in items) [urls addObject:[NSString stringWithFormat:@"%@ <%@>", it[@"title"], it[@"url"]]];
            CBLog(@"[hàng %lu] %@ (%lu phim): %@", (unsigned long)r, rows[r][@"title"], (unsigned long)items.count,
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
    } else if ([verb isEqualToString:@"status"]) {
        CBLog(@"[trạng thái] %@", [CBImages debugStatus]);
        CBLog(@"[trạng thái] màn %@ | RAM %.1f MB%@", NSStringFromClass([[self top] class]), CBResidentMB(),
              player ? [@" | " stringByAppendingString:[player statusLine]] : @"");
    } else {
        CBLog(@"[gỡ lỗi] lệnh không hiểu: %@", cmd);
    }
}

static AVPlayer *gRawPlayer;

+ (void)rawPlay:(NSString *)url {
    [gRawPlayer pause];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    gRawPlayer = [AVPlayer playerWithPlayerItem:item];
    [gRawPlayer play];
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
            if (i == 10) [gRawPlayer pause];
        });
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
