#import "CBCore.h"
#import "CBLog.h"
#include <stdint.h>
#include <stdlib.h>

// linux/ffi/src/lib.rs
typedef void (*cbtv_callback)(uint64_t id, const char *json);
extern int cbtv_init(const char *data_dir, cbtv_callback cb);
extern void cbtv_call(uint64_t id, const char *method, const char *args);
extern char *cbtv_call_sync(const char *method, const char *args);
extern void cbtv_free(char *p);

typedef void (^CBPart)(id part);
typedef void (^CBDone)(id ok, NSString *err);

static NSMutableDictionary *gPending;  // id → @[part, done]
static uint64_t gNextId = 1;

static NSString *CBJSON(id obj) {
    if (!obj) return @"null";
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
}

static id CBParse(const char *json) {
    if (!json) return nil;
    NSData *d = [NSData dataWithBytes:json length:strlen(json)];
    return [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingAllowFragments error:NULL];
}

// Gọi từ luồng của lõi (tokio); chuỗi chỉ dùng được trong lúc gọi → phân tích ngay rồi chuyển sang luồng chính.
static void CBCallback(uint64_t cid, const char *json) {
    NSDictionary *msg = CBParse(json);
    if (![msg isKindOfClass:[NSDictionary class]]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cid == 0) {
            CBLog(@"[lõi] sự kiện %@", msg[@"event"]);
            return;
        }
        NSNumber *key = @(cid);
        NSArray *handlers = gPending[key];
        if (!handlers) return;
        if (msg[@"part"]) {
            CBPart part = handlers[0] == [NSNull null] ? nil : handlers[0];
            if (part) part(msg[@"part"]);
            return;
        }
        [gPending removeObjectForKey:key];
        CBDone done = handlers[1];
        id err = msg[@"err"];
        done(msg[@"ok"], [err isKindOfClass:[NSString class]] ? err : nil);
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
    NSString *dir = [[CBLogPath() stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"cbtv-core"];
    NSDate *t = [NSDate date];
    result = cbtv_init(dir.fileSystemRepresentation, CBCallback);
    CBLog(@"[lõi] cbtv_init → %d sau %.0f ms (dữ liệu: %@, chứng chỉ: %@)", result, -[t timeIntervalSinceNow] * 1000, dir,
          certs ? @"cacert.pem" : @"KHÔNG CÓ");
    return result == 0;
}

+ (NSDictionary *)callSync:(NSString *)method args:(NSDictionary *)args {
    char *r = cbtv_call_sync(method.UTF8String, CBJSON(args ?: @{}).UTF8String);
    id v = CBParse(r);
    cbtv_free(r);
    return [v isKindOfClass:[NSDictionary class]] ? v : @{@"err": @"kết quả không phải JSON"};
}

+ (void)call:(NSString *)method args:(NSDictionary *)args part:(void (^)(id))part done:(void (^)(id, NSString *))done {
    uint64_t cid = gNextId++;
    gPending[@(cid)] = @[part ? [part copy] : [NSNull null], [done copy]];
    cbtv_call(cid, method.UTF8String, CBJSON(args ?: @{}).UTF8String);
}

@end
