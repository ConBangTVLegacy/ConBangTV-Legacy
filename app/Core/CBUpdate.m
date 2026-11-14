#import "CBUpdate.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBTheme.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

extern char **environ;

static NSString *const kReleasesApi = @"https://api.github.com/repos/ConBangTVLegacy/ConBangTV-Legacy/releases/latest";
static NSString *const kHelper = @"/usr/libexec/conbangtv/cbupdate";
static const NSTimeInterval kCheckEvery = 6 * 3600;
static const NSTimeInterval kSnooze = 24 * 3600;

static NSDate *gLastCheck;
static BOOL gBusy;

@implementation CBUpdate

+ (NSString *)currentVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
}

/// "v0.4.1" / "0.4.1" → so từng số: a > b?
+ (BOOL)version:(NSString *)a newerThan:(NSString *)b {
    NSArray *x = [[a stringByReplacingOccurrencesOfString:@"v" withString:@""] componentsSeparatedByString:@"."];
    NSArray *y = [[b stringByReplacingOccurrencesOfString:@"v" withString:@""] componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p > q;
    }
    return NO;
}

+ (void)start {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self check:NO];
    });
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
}

+ (void)foreground {
    if (!gLastCheck || -[gLastCheck timeIntervalSinceNow] > kCheckEvery) [self check:NO];
}

+ (void)checkManual {
    [CBTheme toast:@"Đang kiểm tra bản mới…"];
    [self check:YES];
}

/// Đang xem phim thì không hỏi (thử lại sau 10 phút)
+ (BOOL)playing {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return [NSStringFromClass([vc class]) isEqualToString:@"CBPlayerViewController"];
}

+ (void)check:(BOOL)manual {
    if (gBusy) return;
    gLastCheck = [NSDate date];
    id override = [CBPrefs get:@"update_api"];  // thử: trỏ tới danh sách release khác
    NSString *api = CBIsStr(override) && [override length] ? override : kReleasesApi;
    long long t0 = CBNowMs();
    [CBCore call:@"http.get" args:@{@"url": api, @"headers": @{@"Accept": @"application/vnd.github+json",
                                                                @"User-Agent": @"ConBangTVLegacy"}}
            done:^(id ok, NSString *err) {
        NSDictionary *rel = nil;
        if (CBIsDict(ok) && CBNum(ok, @"code", 0) == 200) {
            id j = [NSJSONSerialization JSONObjectWithData:[CBStr(ok, @"text") ?: @"" dataUsingEncoding:NSUTF8StringEncoding]
                                                   options:0 error:NULL];
            if (CBIsDict(j)) rel = j;
        }
        if (!rel) {
            CBLog(@"Cập nhật: không đọc được danh sách bản (%@) sau %lld ms", err ?: [NSString stringWithFormat:@"HTTP %@", CBVal(ok, @"code")],
                  CBNowMs() - t0);
            if (manual) [CBTheme toast:@"Không kiểm tra được bản mới — thử lại sau."];
            return;
        }
        [self found:rel manual:manual];
    }];
}

+ (void)found:(NSDictionary *)rel manual:(BOOL)manual {
    NSString *tag = CBStr(rel, @"tag_name") ?: @"";
    NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    NSDictionary *asset = nil;
    for (id a in CBArr(rel, @"assets") ?: @[]) {
        NSString *name = CBStr(a, @"name") ?: @"";
        if ([name hasSuffix:@"_iphoneos-arm.deb"] && [name hasPrefix:@"vn.conbangtv.legacy_"]) asset = a;
    }
    NSString *cur = [self currentVersion];
    BOOL newer = asset && [self version:version newerThan:cur];
    CBLog(@"Cập nhật: bản mới nhất %@ (đang dùng %@)%@", version, cur, newer ? @" — có bản mới" : @"");
    if (!newer) {
        if (manual) [CBTheme toast:[NSString stringWithFormat:@"Đang dùng bản mới nhất (%@).", cur]];
        return;
    }
    // «Để sau»: không hỏi lại bản này trong 24 giờ (trừ khi bấm kiểm tra tay)
    id snoozed = [CBPrefs get:@"update_snooze"];
    if (!manual && CBIsDict(snoozed) && [CBStr(snoozed, @"version") isEqualToString:version] &&
        CBNum(snoozed, @"until", 0) > CBNowMs()) {
        return;
    }
    if (!manual && [self playing]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self check:NO];
        });
        return;
    }
    NSString *notes = CBStr(rel, @"body") ?: @"";
    if (notes.length > 500) notes = [[notes substringToIndex:500] stringByAppendingString:@"…"];
    NSString *msg = [NSString stringWithFormat:@"Đang dùng bản %@.%@%@", cur, notes.length ? @"\n\n" : @"", notes];
    [[CBAlert title:[NSString stringWithFormat:@"Có bản mới %@", version] message:msg cancel:@"Để sau" others:@[@"Cập nhật"]
               done:^(CBAlert *a, NSInteger index) {
        if (index == a.cancelButtonIndex) {
            [CBPrefs set:@"update_snooze" value:@{@"version": version, @"until": @(CBNowMs() + (long long)(kSnooze * 1000))}];
            return;
        }
        [self download:asset version:version];
    }] show];
}

+ (NSString *)updateDir {
    return [CBDocumentsDir() stringByAppendingPathComponent:@"ConBangTV-update"];
}

+ (void)download:(NSDictionary *)asset version:(NSString *)version {
    if (![self helperReady]) {
        [[CBAlert title:@"Không tự cập nhật được" message:@"Thiếu công cụ cài (cbupdate) — bản đang dùng cài từ trước khi có cập nhật "
                                                          @"tự động. Cài bản mới một lần bằng tay (xem trang conbangtvlegacy.github.io), "
                                                          @"các bản sau sẽ tự cập nhật."
                 cancel:@"OK" others:nil done:^(CBAlert *a, NSInteger i) {}] show];
        return;
    }
    gBusy = YES;
    NSString *dir = [self updateDir];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dir error:NULL];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *name = [CBStr(asset, @"name") lastPathComponent];
    NSString *path = [dir stringByAppendingPathComponent:name];
    UIAlertView *progress = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Đang tải bản %@…", version] message:@"0%"
                                                      delegate:nil cancelButtonTitle:nil otherButtonTitles:nil];
    [progress show];
    long long t0 = CBNowMs();
    CBLog(@"Cập nhật: tải %@", CBStr(asset, @"browser_download_url"));
    [CBCore call:@"http.download" args:@{@"url": CBStr(asset, @"browser_download_url") ?: @"", @"path": path}
            part:^(id p) {
        if ([p respondsToSelector:@selector(doubleValue)]) progress.message = [NSString stringWithFormat:@"%.0f%%", [p doubleValue] * 100];
    }
            done:^(id ok, NSString *err) {
        [progress dismissWithClickedButtonIndex:0 animated:YES];
        NSString *problem = err ? [@"Không tải được: " stringByAppendingString:err] : [self verify:path asset:asset];
        CBLog(@"Cập nhật: tải xong sau %lld ms%@", CBNowMs() - t0, problem ? [@" — " stringByAppendingString:problem] : @"");
        if (problem) {
            gBusy = NO;
            [fm removeItemAtPath:path error:NULL];
            [[CBAlert title:@"Cập nhật không thành công" message:problem cancel:@"OK" others:nil done:^(CBAlert *a, NSInteger i) {}] show];
            return;
        }
        [self install:path version:version];
    }];
}

/// Kích thước + SHA-256 (GitHub ghi «digest»: "sha256:…" cho từng tệp đính kèm); nil = đúng
+ (NSString *)verify:(NSString *)path asset:(NSDictionary *)asset {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d.length) return @"Tệp tải về trống.";
    long long size = (long long)CBNum(asset, @"size", 0);
    if (size > 0 && (long long)d.length != size) return @"Tệp tải về không đủ (sai kích thước).";
    NSString *digest = CBStr(asset, @"digest");
    if ([digest hasPrefix:@"sha256:"]) {
        unsigned char h[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(d.bytes, (CC_LONG)d.length, h);
        NSMutableString *hex = [NSMutableString string];
        for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", h[i]];
        if (![[digest substringFromIndex:7].lowercaseString isEqualToString:hex]) return @"Tệp tải về bị sai (SHA-256 không khớp).";
    }
    return nil;
}

/// Có công cụ cài root chưa (gói từ bản có OTA trở đi): chủ root + bit setuid
+ (BOOL)helperReady {
    struct stat st;
    return stat(kHelper.fileSystemRepresentation, &st) == 0 && st.st_uid == 0 && (st.st_mode & S_ISUID);
}

+ (void)install:(NSString *)path version:(NSString *)version {
    [CBCore sync:@"prefs.flush" args:nil];
    NSString *pid = [NSString stringWithFormat:@"%d", getpid()];
    char *argv[] = {(char *)kHelper.fileSystemRepresentation, (char *)path.fileSystemRepresentation, (char *)pid.UTF8String, NULL};
    pid_t child;
    int rc = posix_spawn(&child, argv[0], NULL, NULL, argv, environ);
    int status = 0;
    if (rc == 0) waitpid(child, &status, 0);
    int code = rc == 0 && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    CBLog(@"Cập nhật: cbupdate → %d (spawn %d)", code, rc);
    if (code != 0) {
        gBusy = NO;
        NSString *why = code == 66 ? @"công cụ cài thiếu quyền root" : code == 68 ? @"tệp không phải gói của app" : @"lỗi khi kiểm tệp";
        [[CBAlert title:@"Cập nhật không thành công" message:[NSString stringWithFormat:@"Không cài được (%@, mã %d).", why, code]
                 cancel:@"OK" others:nil done:^(CBAlert *a, NSInteger i) {}] show];
        return;
    }
    // cbupdate đã tách nền: sắp đóng app, cài, rồi mở lại
    [[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Đang cài bản %@…", version]
                                message:@"App sẽ tự đóng rồi mở lại sau vài giây." delegate:nil cancelButtonTitle:nil
                      otherButtonTitles:nil] show];
}

@end
