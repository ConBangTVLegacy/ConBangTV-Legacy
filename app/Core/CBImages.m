#import "CBImages.h"
#import "CBLog.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <Security/Security.h>
#import <objc/runtime.h>

static const void *kUrlKey = &kUrlKey;
static const NSInteger kMaxActive = 4;

@class CBImageJob;
static NSCache *gMemory;
static NSMutableArray *gQueue;      // việc chờ (mới nhất ở cuối — ô vừa hiện lên tải trước)
static NSMutableDictionary *gActive;  // url → CBImageJob đang tải
static NSString *gDiskDir;

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

/// Giải mã ảnh thu nhỏ: cạnh dài tối đa maxPx điểm ảnh (không giải mã cả ảnh 1000 px vào RAM)
static UIImage *CBDecode(NSData *data, CGFloat maxPx) {
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
@end

@implementation CBImages

+ (void)setup {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gMemory = [[NSCache alloc] init];
        gMemory.totalCostLimit = 12 * 1024 * 1024;  // ~12 MB ảnh đã giải mã (iPad mini 1 chỉ có 512 MB RAM)
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

+ (void)clearMemory {
    [gMemory removeAllObjects];
}

+ (NSString *)memKey:(NSString *)url px:(CGFloat)px {
    return [NSString stringWithFormat:@"%.0f|%@", px, url];
}

+ (void)load:(NSString *)url size:(CGSize)size into:(UIImageView *)iv {
    [self setup];
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
                deliver(img);
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

+ (void)pump {
    while (gActive.count < kMaxActive && gQueue.count) {
        CBImageJob *job = gQueue.lastObject;
        [gQueue removeLastObject];
        gActive[job.url] = job;
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:job.url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20];
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
    if (data.length) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *img = CBDecode(data, maxPx);
            if (img) [data writeToFile:file atomically:YES];
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
    [CBImages finish:self data:self.status < 400 ? self.data : nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [CBImages finish:self data:nil];
}

@end
