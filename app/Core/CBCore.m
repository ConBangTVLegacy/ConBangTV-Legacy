#import "CBCore.h"
#import "CBLog.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// linux/ffi/src/lib.rs
typedef void (*cbtv_callback)(uint64_t id, const char *json);
extern int cbtv_init(const char *data_dir, cbtv_callback cb);
extern void cbtv_call(uint64_t id, const char *method, const char *args);
extern char *cbtv_call_sync(const char *method, const char *args);
extern void cbtv_free(char *p);

typedef void (^CBPart)(id part);
typedef void (^CBDone)(id ok, NSString *err);

static NSMutableDictionary *gPending;  // mã → @[part | NSNull, done, tên hàm, lúc gọi]
static uint64_t gNextId = 1;

static NSString *CBJSONString(id obj) {
    if (!obj) return @"null";
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
}

static id CBParse(const char *json) {
    if (!json) return nil;
    NSData *d = [NSData dataWithBytesNoCopy:(void *)json length:strlen(json) freeWhenDone:NO];
    return [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingAllowFragments error:NULL];
}

static id CBUnNull(id v) {
    return v == [NSNull null] ? nil : v;
}

// Gọi từ luồng của lõi (tokio); chuỗi chỉ dùng được trong lúc gọi → phân tích ngay rồi chuyển sang luồng chính.
static void CBCallback(uint64_t cid, const char *json) {
    NSDictionary *msg = CBParse(json);
    if (![msg isKindOfClass:[NSDictionary class]]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cid == 0) {
            CBLog(@"[lõi] sự kiện %@", msg[@"event"]);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CBCoreEvent" object:nil userInfo:msg];
            return;
        }
        NSNumber *key = @(cid);
        NSArray *h = gPending[key];
        if (!h) return;
        if (msg[@"part"]) {
            CBPart part = h[0] == [NSNull null] ? nil : h[0];
            if (part) part(msg[@"part"]);
            return;
        }
        [gPending removeObjectForKey:key];
        CBDone done = h[1];
        id err = msg[@"err"];
        if ([err isKindOfClass:[NSString class]]) {
            CBLog(@"[lõi] %@ lỗi sau %lld ms: %@", h[2], CBNowMs() - [h[3] longLongValue], err);
            done(nil, err);
        } else {
            done(CBUnNull(msg[@"ok"]), nil);
        }
    });
}

@implementation CBCore

+ (BOOL)start {
    static BOOL started;
    static int result = -1;
    if (started) return result == 0;
    started = YES;
    gPending = [NSMutableDictionary dictionary];
    NSString *certs = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (certs) setenv("SSL_CERT_FILE", certs.fileSystemRepresentation, 1);
    NSString *dir = [CBDocumentsDir() stringByAppendingPathComponent:@"cbtv-core"];
    long long t = CBNowMs();
    result = cbtv_init(dir.fileSystemRepresentation, CBCallback);
    CBLog(@"[lõi] cbtv_init → %d sau %lld ms (dữ liệu %@)", result, CBNowMs() - t, dir);
    return result == 0;
}

+ (id)sync:(NSString *)method args:(NSDictionary *)args error:(NSString **)error {
    char *r = cbtv_call_sync(method.UTF8String, CBJSONString(args ?: @{}).UTF8String);
    id v = CBParse(r);
    cbtv_free(r);
    if (![v isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"Lõi trả kết quả không đọc được";
        return nil;
    }
    id err = v[@"err"];
    if ([err isKindOfClass:[NSString class]]) {
        CBLog(@"[lõi] %@ lỗi: %@", method, err);
        if (error) *error = err;
        return nil;
    }
    return CBUnNull(v[@"ok"]);
}

+ (id)sync:(NSString *)method args:(NSDictionary *)args {
    return [self sync:method args:args error:NULL];
}

+ (void)call:(NSString *)method args:(NSDictionary *)args part:(void (^)(id))part done:(void (^)(id, NSString *))done {
    uint64_t cid = gNextId++;
    gPending[@(cid)] = @[part ? [part copy] : [NSNull null], done ? [done copy] : [^(id ok, NSString *err) {} copy], method,
                         @(CBNowMs())];
    cbtv_call(cid, method.UTF8String, CBJSONString(args ?: @{}).UTF8String);
}

+ (void)call:(NSString *)method args:(NSDictionary *)args done:(void (^)(id, NSString *))done {
    [self call:method args:args part:nil done:done];
}

+ (void)networkSettingsChanged {
    [self sync:@"net.settingsChanged" args:nil];
}

@end
