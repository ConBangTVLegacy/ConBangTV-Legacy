#import "CBImages.h"
#import "CBPrefs.h"
#import "CBCore.h"
#import "CBLog.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#include "webp/decode.h"

static const void *kUrlKey = &kUrlKey;
static const NSInteger kMaxActive = 4;

@class CBImageJob;
static NSCache *gMemory;
static NSMutableArray *gQueue;      // việc chờ (mới nhất ở cuối — ô vừa hiện lên tải trước)
static NSMutableDictionary *gActive;  // url → CBImageJob đang tải
static NSString *gDiskDir;
static NSInteger gFailed, gDone;  // đếm để gỡ lỗi (lệnh status)
/// Trang ảnh mà iOS 6 không bắt tay TLS được (vd phimmoi.courses: lỗi SSL -1200) — ảnh của trang đó tải thẳng bằng lõi (rustls)
static NSMutableSet *gCoreHosts;

/// Giải mã base64 (NSData initWithBase64EncodedString chỉ có từ iOS 7)
static NSData *CBBase64Decode(NSString *s) {
    static int8_t table[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        memset(table, -1, sizeof(table));
        const char *abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (int i = 0; i < 64; i++) table[(unsigned char)abc[i]] = (int8_t)i;
    });
    NSData *in = [s dataUsingEncoding:NSASCIIStringEncoding];
    const unsigned char *p = in.bytes;
    NSMutableData *out = [NSMutableData dataWithCapacity:in.length * 3 / 4];
    uint32_t acc = 0;
    int bits = 0;
    for (NSUInteger i = 0; i < in.length; i++) {
        int8_t v = table[p[i]];
        if (v < 0) continue;
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            unsigned char b = (unsigned char)((acc >> bits) & 0xFF);
            [out appendBytes:&b length:1];
        }
    }
    return out;
}

static NSString *CBMd5(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_MD5_DIGEST_LENGTH];
    CC_MD5(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *out = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", h[i]];
    return out;
}

/// Ảnh WebP (iOS 6 không đọc được): libwebp giải mã thẳng ra cỡ nhỏ (use_scaling) — đỡ RAM, đỡ CPU
static UIImage *CBDecodeWebP(NSData *data, CGFloat maxPx) {
    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) return nil;
    if (WebPGetFeatures(data.bytes, data.length, &config.input) != VP8_STATUS_OK) return nil;
    int w = config.input.width, h = config.input.height;
    if (w <= 0 || h <= 0) return nil;
    double scale = MIN(1.0, MAX(maxPx, 32) / MAX(w, h));
    if (scale < 1) {
        config.options.use_scaling = 1;
        config.options.scaled_width = MAX(1, (int)lround(w * scale));
        config.options.scaled_height = MAX(1, (int)lround(h * scale));
    }
    config.output.colorspace = MODE_bgrA;  // BGRA nhân trước alpha = kCGImageAlphaPremultipliedFirst | ByteOrder32Little
    if (WebPDecode(data.bytes, data.length, &config) != VP8_STATUS_OK) return nil;
    int ow = config.output.width, oh = config.output.height;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(config.output.u.RGBA.rgba, ow, oh, 8, config.output.u.RGBA.stride, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    UIImage *out = nil;
    if (ctx) {
        CGImageRef img = CGBitmapContextCreateImage(ctx);  // chép điểm ảnh ra — rồi trả bộ nhớ của libwebp
        CGContextRelease(ctx);
        out = [UIImage imageWithCGImage:img scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
        CGImageRelease(img);
    }
    WebPFreeDecBuffer(&config.output);
    return out;
}

static BOOL CBIsWebP(NSData *data) {
    const unsigned char *b = data.bytes;
    return data.length > 12 && !memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4);
}

/// Giải mã ảnh thu nhỏ: cạnh dài tối đa maxPx điểm ảnh (không giải mã cả ảnh 1000 px vào RAM)
static UIImage *CBDecode(NSData *data, CGFloat maxPx) {
    if (CBIsWebP(data)) return CBDecodeWebP(data, maxPx);
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                           (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                           (id)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxPx, 32))};
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!img) return nil;
    // Vẽ lại một lần trên luồng nền để luồng chính khỏi giải nén lúc cuộn
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    UIImage *out = nil;
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
        CGImageRef drawn = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        out = [UIImage imageWithCGImage:drawn scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
        CGImageRelease(drawn);
    }
    CGImageRelease(img);
    return out;
}

@interface CBImageJob : NSObject <NSURLConnectionDataDelegate>
@property (nonatomic, copy) NSString *url;
@property (nonatomic) CGFloat maxPx;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSURLConnection *conn;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL viaCore;  // đang / đã tải bằng lõi (không thử lại lần nữa)
@end

@implementation CBImages

+ (void)setup {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gMemory = [[NSCache alloc] init];
        // Ảnh đã giải mã: 12 MB chỉ giữ ~30 ảnh bìa — cuộn qua lại là ảnh tải / mờ dần lại. Máy 1 GB RAM (iPhone 5) giữ nhiều hơn;
        // iPad mini 1 chỉ có 512 MB
        BOOL bigRam = [NSProcessInfo processInfo].physicalMemory >= 900ull * 1024 * 1024;
        gMemory.totalCostLimit = (bigRam ? 28 : 16) * 1024 * 1024;
        // Trang lỗi TLS đã biết từ lần trước: khỏi chờ lỗi (lần đầu mất tới 15–20 giây) mỗi lần mở app
        NSArray *known = [[NSUserDefaults standardUserDefaults] arrayForKey:@"CBCoreImageHosts"];
        gCoreHosts = [NSMutableSet setWithArray:[known isKindOfClass:[NSArray class]] ? known : @[]];
        gQueue = [NSMutableArray array];
        gActive = [NSMutableDictionary dictionary];
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        gDiskDir = [(dirs.count ? dirs[0] : NSTemporaryDirectory()) stringByAppendingPathComponent:@"img"];
        [[NSFileManager defaultManager] createDirectoryAtPath:gDiskDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *n) { [gMemory removeAllObjects]; }];
    });
}

+ (NSArray *)anchors {
    static NSArray *anchors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        NSString *path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        NSString *pem = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSArray *parts = [pem componentsSeparatedByString:@"-----BEGIN CERTIFICATE-----"];
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *b64 = [parts[i] componentsSeparatedByString:@"-----END CERTIFICATE-----"][0];
            NSData *der = CBBase64Decode(b64);
            SecCertificateRef c = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der);
            if (c) [list addObject:(__bridge_transfer id)c];
        }
        anchors = [list copy];
        CBLog(@"Nạp %lu chứng chỉ gốc Mozilla", (unsigned long)anchors.count);
    });
    return anchors;
}

+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (![space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
        return;
    }
    SecTrustRef trust = space.serverTrust;
    SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)[self anchors]);
    SecTrustSetAnchorCertificatesOnly(trust, false);  // vẫn tin gốc của máy
    SecTrustResultType result = kSecTrustResultInvalid;
    if (SecTrustEvaluate(trust, &result) == errSecSuccess &&
        (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed)) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:trust] forAuthenticationChallenge:challenge];
    } else {
        CBLog(@"Chứng chỉ %@ không hợp lệ (%d)", space.host, (int)result);
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
}

+ (NSString *)debugStatus {
    return [NSString stringWithFormat:@"ảnh: đang tải %lu, chờ %lu, xong %ld, hỏng %ld", (unsigned long)gActive.count,
            (unsigned long)gQueue.count, (long)gDone, (long)gFailed];
}

+ (void)clearMemory {
    [gMemory removeAllObjects];
}

+ (NSString *)memKey:(NSString *)url px:(CGFloat)px {
    return [NSString stringWithFormat:@"%.0f|%@", px, url];
}

+ (void)load:(NSString *)url size:(CGSize)size into:(UIImageView *)iv {
    [self setup];
    // AVIF (vd ảnh bìa yanhh3d — WordPress sinh kèm bản .webp cùng chỗ): iOS 6 không giải mã được AVIF → lấy bản WebP
    NSRange q = [url rangeOfString:@"?"];
    NSString *path = q.location == NSNotFound ? url : [url substringToIndex:q.location];
    if ([path.lowercaseString hasSuffix:@".avif"]) {
        url = [[path substringToIndex:path.length - 5] stringByAppendingFormat:@".webp%@",
                                                                              q.location == NSNotFound ? @"" : [url substringFromIndex:q.location]];
    }
    // Đang hiện đúng ảnh này (quay lại màn, bấm Theo dõi, đổi bản…): giữ nguyên, không xoá rồi mờ dần lại
    if (iv.image && url.length && [objc_getAssociatedObject(iv, kUrlKey) isEqualToString:url]) return;
    objc_setAssociatedObject(iv, kUrlKey, url, OBJC_ASSOCIATION_COPY_NONATOMIC);
    iv.image = nil;
    if (!url.length) return;
    CGFloat maxPx = MAX(size.width, size.height) * [UIScreen mainScreen].scale;
    UIImage *hit = [gMemory objectForKey:[self memKey:url px:maxPx]];
    if (hit) {
        iv.image = hit;
        return;
    }
    __weak UIImageView *weakIv = iv;
    void (^deliver)(UIImage *) = ^(UIImage *img) {
        UIImageView *v = weakIv;
        if (v && img && [objc_getAssociatedObject(v, kUrlKey) isEqualToString:url]) {
            v.image = img;
            v.alpha = 0;
            [UIView animateWithDuration:0.2 animations:^{ v.alpha = 1; }];
        }
    };
    NSString *file = [gDiskDir stringByAppendingPathComponent:CBMd5(url)];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:file];
        UIImage *img = data ? CBDecode(data, maxPx) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (img) {
                [gMemory setObject:img forKey:[self memKey:url px:maxPx] cost:(NSUInteger)(img.size.width * img.size.height * 4 *
                                                                                         img.scale * img.scale)];
                // Ảnh có sẵn trên máy: hiện ngay, không mờ dần (mờ dần chỉ cho ảnh vừa tải về)
                UIImageView *v = weakIv;
                if (v && [objc_getAssociatedObject(v, kUrlKey) isEqualToString:url]) v.image = img;
                return;
            }
            [self enqueue:url maxPx:maxPx file:file deliver:deliver];
        });
    });
}

+ (void)cancel:(UIImageView *)iv {
    objc_setAssociatedObject(iv, kUrlKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// ---- Hàng đợi tải mạng ----

static NSMutableDictionary *gWaiters;  // url → mảng khối deliver

+ (void)enqueue:(NSString *)url maxPx:(CGFloat)maxPx file:(NSString *)file deliver:(void (^)(UIImage *))deliver {
    if (!gWaiters) gWaiters = [NSMutableDictionary dictionary];
    NSMutableArray *w = gWaiters[url];
    if (w) {
        [w addObject:[deliver copy]];
        return;
    }
    gWaiters[url] = [NSMutableArray arrayWithObject:[deliver copy]];
    CBImageJob *job = [[CBImageJob alloc] init];
    job.url = url;
    job.maxPx = maxPx;
    [gQueue addObject:job];
    [self pump];
}

/// Proxy đang bật cho cả app (không phải «chỉ trang phim»): ảnh cũng phải đi qua proxy → tải bằng lõi (http.download)
+ (BOOL)viaCore {
    id on = [CBPrefs get:@"proxy_on"], sitesOnly = [CBPrefs get:@"proxy_sites_only"];
    return [on respondsToSelector:@selector(boolValue)] && [on boolValue] &&
           !([sitesOnly respondsToSelector:@selector(boolValue)] && [sitesOnly boolValue]);
}

/// Tải bằng lõi (http.download): proxy cho cả app, hoặc trang ảnh iOS 6 không bắt tay TLS được
+ (void)fetchViaCore:(CBImageJob *)job {
    job.viaCore = YES;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"img-" stringByAppendingString:CBMd5(job.url)]];
    [CBCore call:@"http.download" args:@{@"url": job.url, @"path": tmp} done:^(id ok, NSString *err) {
        NSData *d = err ? nil : [NSData dataWithContentsOfFile:tmp];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
        if (err) CBLog(@"Ảnh lỗi (qua lõi): %@ — %@", err, job.url);
        else gDone++;
        [self finish:job data:d];
    }];
}

/// iOS 6 tải ảnh lỗi: lỗi TLS / chứng chỉ (máy cũ thiếu bộ mã / gốc mới) hay hết thời gian chờ (bắt tay TLS treo) → thử bằng lõi
+ (BOOL)shouldRetryViaCore:(NSError *)error {
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    NSInteger c = error.code;
    return c == NSURLErrorTimedOut || c == NSURLErrorUserCancelledAuthentication || c == NSURLErrorCancelled ||
           (c <= NSURLErrorSecureConnectionFailed && c >= NSURLErrorClientCertificateRequired);
}

+ (void)retryViaCore:(CBImageJob *)job error:(NSError *)error {
    NSString *host = [NSURL URLWithString:job.url].host;
    // Cả trang đó tải qua lõi từ giờ (khỏi chờ lỗi từng ảnh — bắt tay TLS treo thì mỗi ảnh mất 15 giây mới báo hết giờ).
    // Lỗi TLS thì nhớ sang lần mở app sau; hết thời gian chờ (có thể chỉ do mạng chập chờn) thì chỉ trong lần này
    if (host && ![gCoreHosts containsObject:host]) {
        [gCoreHosts addObject:host];
        BOOL tls = error.code != NSURLErrorTimedOut;
        CBLog(@"Ảnh của %@: iOS 6 %@ — tải qua lõi", host, tls ? @"không kết nối TLS được" : @"chờ quá lâu");
        if (tls) {
            NSMutableArray *keep = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"CBCoreImageHosts"] ?: @[] mutableCopy];
            if (![keep containsObject:host]) [keep addObject:host];
            [[NSUserDefaults standardUserDefaults] setObject:keep forKey:@"CBCoreImageHosts"];
        }
    }
    job.conn = nil;
    [self fetchViaCore:job];
}

+ (void)pump {
    BOOL viaCore = gQueue.count ? [self viaCore] : NO;
    while (gActive.count < kMaxActive && gQueue.count) {
        CBImageJob *job = gQueue.lastObject;
        [gQueue removeLastObject];
        gActive[job.url] = job;
        NSString *host = gCoreHosts.count ? [NSURL URLWithString:job.url].host : nil;
        if (viaCore || (host && [gCoreHosts containsObject:host])) {
            [self fetchViaCore:job];
            continue;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:job.url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15];
        if (!req.URL) {
            [self finish:job data:nil];
            continue;
        }
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 6_1 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Mobile/10B141"
            forHTTPHeaderField:@"User-Agent"];
        job.data = [NSMutableData data];
        job.conn = [[NSURLConnection alloc] initWithRequest:req delegate:job startImmediately:YES];
    }
}

+ (void)finish:(CBImageJob *)job data:(NSData *)data {
    [gActive removeObjectForKey:job.url];
    job.conn = nil;
    NSArray *waiters = gWaiters[job.url] ?: @[];
    [gWaiters removeObjectForKey:job.url];
    NSString *file = [gDiskDir stringByAppendingPathComponent:CBMd5(job.url)];
    CGFloat maxPx = job.maxPx;
    NSString *url = job.url;
    if (!data.length) {
        gFailed++;
        CBLog(@"Ảnh hỏng (HTTP %ld): %@", (long)job.status, url);
    }
    if (data.length) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *img = CBDecode(data, maxPx);
            if (img) [data writeToFile:file atomically:YES];
            if (!img) {
                const unsigned char *b = data.bytes;
                CBLog(@"Ảnh không giải mã được (%lu byte, đầu %02x%02x%02x%02x…%02x%02x%02x%02x): %@", (unsigned long)data.length,
                      b[0], b[1], b[2], b[3], data.length > 11 ? b[8] : 0, data.length > 11 ? b[9] : 0, data.length > 11 ? b[10] : 0,
                      data.length > 11 ? b[11] : 0, url);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) {
                    [gMemory setObject:img forKey:[self memKey:url px:maxPx]
                                  cost:(NSUInteger)(img.size.width * img.size.height * 4 * img.scale * img.scale)];
                }
                for (void (^d)(UIImage *) in waiters) d(img);
            });
        });
    }
    [self pump];
}

@end

@implementation CBImageJob

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)c {
    [CBImages handleChallenge:c];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    [self.data setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    gDone++;
    [CBImages finish:self data:self.status < 400 ? self.data : nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    CBLog(@"Ảnh lỗi mạng %ld (%@): %@", (long)error.code, error.localizedDescription, self.url);
    if (!self.viaCore && [CBImages shouldRetryViaCore:error]) {
        [CBImages retryViaCore:self error:error];
        return;
    }
    [CBImages finish:self data:nil];
}

@end
