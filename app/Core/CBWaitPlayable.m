#import "CBWaitPlayable.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBAlert.h"
#import <UIKit/UIKit.h>

static NSString *const kKey = @"wait_playable";
static const long long kEveryMs = 30 * 60 * 1000;       // kiểm lại mỗi tập tối đa 30 phút một lần
static const long long kExpireMs = 14LL * 24 * 3600 * 1000;
static const NSUInteger kMax = 20;

static BOOL gChecking;
static NSMutableArray *gReady;   // [{detail, ep, title}] đã xem được — chờ hiện hộp (đang xem phim / đang hiện hộp khác)
static BOOL gPrompting;

@interface CBWaitPlayable ()
- (void)promptClosed:(BOOL)watch;
@end

@implementation CBWaitPlayable

+ (instancetype)shared {
    static CBWaitPlayable *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CBWaitPlayable alloc] init]; });
    return s;
}

+ (void)start {
    gReady = [NSMutableArray array];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self check:NO];
    });
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    [NSTimer scheduledTimerWithTimeInterval:kEveryMs / 1000.0 target:self selector:@selector(timer) userInfo:nil repeats:YES];
}

+ (void)foreground {
    // Chờ cổng nội bộ mở lại (applicationDidBecomeActive) và trang chủ tải xong
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self check:NO];
    });
}

+ (void)timer {
    [self check:NO];
}

#pragma mark - Danh sách

+ (NSArray *)list {
    NSMutableArray *out = [NSMutableArray array];
    id v = [CBPrefs get:[CBPrefs k:kKey]];
    for (id e in CBIsArr(v) ? v : @[]) {
        if (CBStr(e, @"film") && CBStr(e, @"ep")) [out addObject:e];
    }
    return out;
}

+ (void)save:(NSArray *)list {
    [CBPrefs set:[CBPrefs k:kKey] value:list];
}

+ (BOOL)has:(NSString *)epUrl {
    for (NSDictionary *e in [self list]) {
        if ([CBStr(e, @"ep") isEqualToString:epUrl]) return YES;
    }
    return NO;
}

+ (void)add:(NSDictionary *)detail episode:(NSDictionary *)ep group:(NSDictionary *)group {
    NSString *film = CBStr(detail, @"url"), *epUrl = CBStr(ep, @"url");
    if (!film || !epUrl) return;
    NSMutableArray *list = [[self list] mutableCopy];
    NSIndexSet *dup = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
        return [CBStr(e, @"ep") isEqualToString:epUrl];
    }];
    [list removeObjectsAtIndexes:dup];
    [list addObject:@{@"film": film, @"title": CBStr(detail, @"title") ?: @"", @"ep": epUrl, @"epTitle": CBStr(ep, @"title") ?: @"",
                      @"group": CBStr(group, @"name") ?: @"", @"added": @(CBNowMs()), @"checked": @(CBNowMs())}];
    while (list.count > kMax) [list removeObjectAtIndex:0];
    [self save:list];
    CBLog(@"Báo khi xem được: nhớ %@ — %@ (%@)", CBStr(detail, @"title"), CBStr(ep, @"title"), CBStr(group, @"name"));
}

+ (void)remove:(NSString *)epUrl {
    NSMutableArray *list = [[self list] mutableCopy];
    NSIndexSet *found = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
        return [CBStr(e, @"ep") isEqualToString:epUrl];
    }];
    if (!found.count) return;
    [list removeObjectsAtIndexes:found];
    [self save:list];
}

/// Ghi lại thời điểm kiểm của một tập (không kiểm lại trong 30 phút)
+ (void)touch:(NSString *)epUrl {
    NSMutableArray *list = [[self list] mutableCopy];
    for (NSUInteger i = 0; i < list.count; i++) {
        if (![CBStr(list[i], @"ep") isEqualToString:epUrl]) continue;
        NSMutableDictionary *e = [list[i] mutableCopy];
        e[@"checked"] = @(CBNowMs());
        list[i] = e;
    }
    [self save:list];
}

#pragma mark - Kiểm lại

/// Màn trên cùng của cửa sổ chính (không dùng keyWindow — lúc hộp thoại đang hiện, keyWindow là cửa sổ của hộp thoại)
+ (UIViewController *)top {
    UIViewController *vc = [[UIApplication sharedApplication].delegate window].rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (BOOL)playing {
    return [[self top] isKindOfClass:[CBPlayerViewController class]];
}

+ (void)checkNow {
    [self check:YES];
}

+ (void)check:(BOOL)force {
    if (gChecking || (!force && [self playing])) return;  // đang xem phim: không tranh mạng với video — lần sau kiểm
    NSMutableArray *list = [[self list] mutableCopy];
    NSIndexSet *old = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
        return CBNowMs() - (long long)CBNum(e, @"added", 0) > kExpireMs;
    }];
    if (old.count) {
        CBLog(@"Báo khi xem được: bỏ %lu tập đã chờ quá 14 ngày", (unsigned long)old.count);
        [list removeObjectsAtIndexes:old];
        [self save:list];
    }
    NSMutableArray *due = [NSMutableArray array];
    for (NSDictionary *e in list) {
        if (force || CBNowMs() - (long long)CBNum(e, @"checked", 0) >= kEveryMs) [due addObject:e];
    }
    if (!due.count) return;
    gChecking = YES;
    CBLog(@"Báo khi xem được: kiểm lại %lu tập", (unsigned long)due.count);
    [self checkEntries:due index:0];
}

+ (void)checkEntries:(NSArray *)due index:(NSUInteger)i {
    if (i >= due.count) {
        gChecking = NO;
        [self showReady];
        return;
    }
    NSDictionary *e = due[i];
    [self touch:CBStr(e, @"ep")];
    [CBCore call:@"site.detail" args:@{@"url": CBStr(e, @"film")} done:^(id detail, NSString *err) {
        if (!CBIsDict(detail)) {
            CBLog(@"Báo khi xem được: %@ — không tải được trang phim (%@)", CBStr(e, @"title"), err ?: @"?");
            [self checkEntries:due index:i + 1];
            return;
        }
        [self tryCandidates:[self candidates:e detail:detail] detail:detail index:0 done:^(NSDictionary *ep, NSDictionary *group,
                                                                                            NSString *server) {
            if (ep) {
                CBLog(@"Báo khi xem được: %@ — %@ (%@) đã phát được (server %@)", CBStr(e, @"title"), CBStr(ep, @"title"),
                      CBStr(group, @"name"), server);
                [self remove:CBStr(e, @"ep")];
                [gReady addObject:@{@"detail": detail, @"ep": ep, @"group": CBStr(group, @"name") ?: @""}];
            } else {
                CBLog(@"Báo khi xem được: %@ — %@ vẫn chưa có server phát được", CBStr(e, @"title"), CBStr(e, @"epTitle"));
            }
            [self checkEntries:due index:i + 1];
        }];
    }];
}

/// [(nhóm, tập)] cần thử: tập đã nhớ (theo địa chỉ, không thấy thì theo số tập trong nhóm cùng tên); phim không chia mùa thì
/// thêm cùng số tập ở các bản khác
+ (NSArray *)candidates:(NSDictionary *)e detail:(NSDictionary *)detail {
    NSArray *groups = CBArr(detail, @"groups") ?: @[];
    NSString *num = CBEpisodeNumberOf(CBStr(e, @"epTitle"));
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *(^find)(NSDictionary *, BOOL) = ^NSDictionary *(NSDictionary *g, BOOL byUrl) {
        for (id ep in CBArr(g, @"episodes") ?: @[]) {
            if (byUrl ? [CBStr(ep, @"url") isEqualToString:CBStr(e, @"ep")]
                      : (num && [CBEpisodeNumberOf(CBStr(ep, @"title")) isEqualToString:num])) return ep;
        }
        return nil;
    };
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (NSUInteger k = 0; k < groups.count; k++) {
        NSDictionary *g = groups[k];
        NSDictionary *ep = find(g, YES);
        if (!ep && [CBStr(g, @"name") ?: @"" isEqualToString:CBStr(e, @"group") ?: @""]) ep = find(g, NO);
        if (!ep) continue;
        [out addObject:@[g, ep]];
        [used addIndex:k];
    }
    if (!CBDetailSeasons(detail)) {
        for (NSUInteger k = 0; k < groups.count; k++) {
            if ([used containsIndex:k]) continue;
            NSDictionary *ep = find(groups[k], NO);
            if (ep) [out addObject:@[groups[k], ep]];
        }
    }
    return out;
}

+ (void)tryCandidates:(NSArray *)list detail:(NSDictionary *)detail index:(NSUInteger)i
                 done:(void (^)(NSDictionary *ep, NSDictionary *group, NSString *server))done {
    if (i >= list.count) {
        done(nil, nil, nil);
        return;
    }
    NSDictionary *g = list[i][0], *ep = list[i][1];
    [self probe:detail group:g ep:ep done:^(NSString *server) {
        if (server) done(ep, g, server);
        else [self tryCandidates:list detail:detail index:i + 1 done:done];
    }];
}

/// Tập này giờ có server phát thẳng được không — hỏi như trình phát (kk.source có cả server dự phòng KKPhim → site.videoOf)
+ (void)probe:(NSDictionary *)detail group:(NSDictionary *)group ep:(NSDictionary *)ep done:(void (^)(NSString *server))done {
    NSMutableDictionary *args = [@{@"detail": detail, @"ep": ep} mutableCopy];
    if (group) args[@"group"] = group;
    [CBCore call:@"kk.source" args:args done:^(id src, NSString *err) {
        NSMutableArray *servers = [NSMutableArray array];
        for (id s in CBArr(src, @"servers") ?: @[]) {
            if (CBIsDict(s) && ![CBStr(s, @"type") isEqualToString:@"page"]) [servers addObject:s];
        }
        if (!CBIsDict(src) || !servers.count) {
            done(nil);
            return;
        }
        __block NSInteger left = (NSInteger)servers.count;
        __block BOOL finished = NO;
        void (^miss)(void) = ^{
            if (!finished && --left == 0) {
                finished = YES;
                done(nil);
            }
        };
        for (NSDictionary *s in servers) {
            [CBCore call:@"site.videoOf" args:@{@"src": src, @"server": s} done:^(id v, NSString *e) {
                if (finished) return;
                if (!(CBIsDict(v) && CBVideoIsDirect(v))) {
                    miss();
                    return;
                }
                // Có link phát thẳng: tải thử — trang (KKPhim) có lúc đưa tập vào danh sách trước khi đưa video lên (link 404)
                [CBCore call:@"http.get" args:@{@"url": CBStr(v, @"url") ?: @""} done:^(id ok, NSString *err) {
                    if (finished) return;
                    NSInteger code = (NSInteger)CBNum(ok, @"code", 0);
                    if (code == 404 || code == 410) {
                        CBLog(@"Báo khi xem được: server %@ có link nhưng máy chủ phim trả HTTP %ld", CBStr(s, @"label"), (long)code);
                        miss();
                        return;
                    }
                    // Có video nhưng chỉ ở khổ / mức chip máy không giải mã được (KKPhim Tiên Nghịch 166–167: 2542×1080 mức 5.0)
                    NSString *bad = code >= 200 && code < 300 ? CBPlaylistUndecodable(CBStr(ok, @"text")) : nil;
                    if (bad) {
                        CBLog(@"Báo khi xem được: server %@ chỉ có bản %@ — máy này không giải mã được", CBStr(s, @"label"), bad);
                        miss();
                        return;
                    }
                    finished = YES;
                    done(CBStr(s, @"label") ?: @"?");
                }];
            }];
        }
    }];
}

#pragma mark - Báo

+ (void)playerClosed {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showReady];
    });
}

/// Hộp «Đã xem được» cho tập đầu hàng chờ (đang xem phim thì để lúc đóng trình phát)
+ (void)showReady {
    if (gPrompting || !gReady.count || [self playing]) return;
    NSDictionary *r = gReady[0];
    NSString *group = CBStr(r, @"group");
    NSString *msg = [NSString stringWithFormat:@"«%@» — %@%@ đã có server phát được trên iOS 6.", CBStr(r[@"detail"], @"title") ?: @"",
                                               CBStr(r[@"ep"], @"title") ?: @"",
                                               group.length && CBArr(r[@"detail"], @"groups").count > 1
                                                   ? [NSString stringWithFormat:@" (%@)", group] : @""];
    gPrompting = YES;
    // Mở trình phát khi hộp đã đóng hẳn (cửa sổ chính lại là cửa sổ trên cùng)
    [[CBAlert title:@"Đã xem được" message:msg cancel:@"Để sau" others:@[@"Xem ngay"] done:^(CBAlert *a, NSInteger index) {
        BOOL watch = index != a.cancelButtonIndex;
        [a afterDismiss:^{ [[CBWaitPlayable shared] promptClosed:watch]; }];
    }] show];
}

/// Hộp «Đã xem được» đã đóng hẳn: «Xem ngay» thì mở trình phát
- (void)promptClosed:(BOOL)watch {
    gPrompting = NO;
    if (!gReady.count) return;
    NSDictionary *r = gReady[0];
    [gReady removeObjectAtIndex:0];
    if (watch) {
        NSDictionary *detail = r[@"detail"];
        CBLog(@"Báo khi xem được: mở %@ — %@", CBStr(detail, @"title"), CBStr(r[@"ep"], @"title"));
        UIViewController *top = [CBWaitPlayable top];
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:CBStr(detail, @"url") detail:detail
                                                                         episode:CBStr(r[@"ep"], @"url") resume:YES];
        [top presentViewController:p animated:YES completion:nil];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [CBWaitPlayable showReady];
    });
}

@end
