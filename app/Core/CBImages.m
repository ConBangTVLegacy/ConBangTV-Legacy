#import "CBImages.h"
#import <malloc/malloc.h>
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
NSString *const CBImagesPurgeNotification = @"CBImagesPurgeNotification";
static NSMutableDictionary *gWants;  // url → [CBImageWant]: ô nào đang chờ ảnh (yếu — ô đã huỷ thì thôi)
static long gSkipped;

/// Một ô chờ ảnh. Ô đã bị huỷ (màn đã đóng) hoặc đã đổi sang ảnh khác (cuộn qua, tái dùng) thì ảnh đang xếp hàng bỏ luôn,
/// không tải — máy chậm (iPad 1) vuốt nhanh qua một danh sách dài từng dồn ~80 ảnh, màn mở sau phải chờ cả phút.
@interface CBImageWant : NSObject
@property (nonatomic, weak) UIImageView *view;
@end
@implementation CBImageWant
@end
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

/// Hàng giải mã ảnh: mỗi nhân CPU một hàng tuần tự (tối đa 2), ưu tiên thấp. Trước đây mỗi ảnh một việc trên hàng đồng thời của GCD:
/// iPad 1 (A4 một nhân) lúc mở app giải mã vài chục ảnh WebP cùng lúc — luồng chính không kịp chạy, iOS tắt app (quá 20 giây
/// chưa mở xong, 0x8badf00d), vuốt nhanh thì RAM app vọt lên ~100 MB.
static dispatch_queue_t CBDecodeQueue(void) {
    static dispatch_queue_t lanes[2];
    static int count;
    static unsigned next;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        count = (int)MAX(1u, MIN(2u, [NSProcessInfo processInfo].activeProcessorCount));
        for (int i = 0; i < count; i++) {
            lanes[i] = dispatch_queue_create("vn.conbangtv.images.decode", NULL);
            dispatch_set_target_queue(lanes[i], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        }
    });
    return lanes[(next++) % count];  // chỉ gọi trên luồng chính
}

/// Khổ ảnh muốn có: maxPx = cạnh dài tối đa (giữ tỉ lệ); hoặc fill (w × h điểm ảnh) = cắt kiểu Aspect Fill đúng khổ ô, bo góc
/// radius điểm ảnh ngay trong ảnh
typedef struct {
    CGFloat maxPx;
    CGSize fill;
    CGFloat radius;
} CBImageSpec;

static BOOL CBSpecFill(CBImageSpec s) {
    return s.fill.width >= 1 && s.fill.height >= 1;
}

/// Khổ gốc của ảnh (đọc phần đầu tệp, chưa giải mã)
static CGSize CBSourceSize(NSData *data) {
    if (CBIsWebP(data)) {
        WebPBitstreamFeatures f;
        return WebPGetFeatures(data.bytes, data.length, &f) == VP8_STATUS_OK ? CGSizeMake(f.width, f.height) : CGSizeZero;
    }
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return CGSizeZero;
    NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    CFRelease(src);
    return CGSizeMake([p[(id)kCGImagePropertyPixelWidth] doubleValue], [p[(id)kCGImagePropertyPixelHeight] doubleValue]);
}

static void CBAddRoundedRect(CGContextRef c, CGRect r, CGFloat rad) {
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    CGContextMoveToPoint(c, x0 + rad, y0);
    CGContextAddArcToPoint(c, x1, y0, x1, y1, rad);
    CGContextAddArcToPoint(c, x1, y1, x0, y1, rad);
    CGContextAddArcToPoint(c, x0, y1, x0, y0, rad);
    CGContextAddArcToPoint(c, x0, y0, x1, y0, rad);
    CGContextClosePath(c);
}

/// Vẽ ảnh đã giải mã ra bitmap cuối cùng (luồng nền — luồng chính khỏi giải nén / co giãn / cắt lúc cuộn): giữ khổ, hoặc cắt kiểu
/// Aspect Fill đúng khổ ô + bo góc (góc trong suốt — ô khỏi cần cornerRadius + clipsToBounds, thứ bắt GPU vẽ ngoài màn hình mỗi khung)
static UIImage *CBRender(CGImageRef img, CBImageSpec spec) {
    size_t sw = CGImageGetWidth(img), sh = CGImageGetHeight(img);
    BOOL fill = CBSpecFill(spec);
    size_t w = fill ? (size_t)spec.fill.width : sw, h = fill ? (size_t)spec.fill.height : sh;
    if (!sw || !sh || !w || !h) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = fill && spec.radius > 0 ? (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)
                                                : (kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, info);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGRect dst = CGRectMake(0, 0, w, h);
    if (fill) {
        CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
        if (spec.radius > 0) {
            CBAddRoundedRect(ctx, dst, MIN(spec.radius, MIN(w, h) / 2.0));
            CGContextClip(ctx);
        }
        CGFloat k = MAX((CGFloat)w / sw, (CGFloat)h / sh);
        dst = CGRectMake(round((w - sw * k) / 2), round((h - sh * k) / 2), round(sw * k), round(sh * k));
    }
    CGContextDrawImage(ctx, dst, img);
    CGImageRef drawn = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    UIImage *out = [UIImage imageWithCGImage:drawn scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    CGImageRelease(drawn);
    return out;
}

/// Giải mã ảnh thu nhỏ (không giải mã cả ảnh 1000 px vào RAM): cạnh dài tối đa spec.maxPx, hoặc vừa đủ phủ khổ spec.fill
static UIImage *CBDecode(NSData *data, CBImageSpec spec) {
    CGFloat maxPx = spec.maxPx;
    if (CBSpecFill(spec)) {
        CGSize s = CBSourceSize(data);
        if (s.width < 1 || s.height < 1) return nil;
        CGFloat k = MIN(1, MAX(spec.fill.width / s.width, spec.fill.height / s.height));
        maxPx = ceil(MAX(s.width, s.height) * k);
    }
    if (CBIsWebP(data)) {
        UIImage *img = CBDecodeWebP(data, maxPx);
        return img && CBSpecFill(spec) ? CBRender(img.CGImage, spec) : img;
    }
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                           (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                           (id)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxPx, 32))};
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!img) return nil;
    UIImage *out = CBRender(img, spec);
    CGImageRelease(img);
    return out;
}

@interface CBImageJob : NSObject <NSURLConnectionDataDelegate>
@property (nonatomic, copy) NSString *url;
@property (nonatomic) CBImageSpec spec;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSURLConnection *conn;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL viaCore;  // đang / đã tải bằng lõi (không thử lại lần nữa)
@end

@implementation CBCoverView

- (void)setImage:(UIImage *)image {
    [super setImage:image];
    self.placeholder.hidden = image != nil;
}

@end

@implementation CBImages

+ (void)setup {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gMemory = [[NSCache alloc] init];
        // Ảnh đã giải mã: 12 MB chỉ giữ ~30 ảnh bìa — cuộn qua lại là ảnh tải / mờ dần lại. Máy 1 GB RAM (iPhone 5) giữ nhiều hơn;
        // iPad mini 1 chỉ có 512 MB
        BOOL bigRam = [NSProcessInfo processInfo].physicalMemory >= 900ull * 1024 * 1024;
        gMemory.totalCostLimit = (bigRam ? 28 : [self lowRam] ? 8 : 16) * 1024 * 1024;  // iPad 1: 256 MB
        // Trang lỗi TLS đã biết từ lần trước: khỏi chờ lỗi (lần đầu mất tới 15–20 giây) mỗi lần mở app
        NSArray *known = [[NSUserDefaults standardUserDefaults] arrayForKey:@"CBCoreImageHosts"];
        gCoreHosts = [NSMutableSet setWithArray:[known isKindOfClass:[NSArray class]] ? known : @[]];
        gQueue = [NSMutableArray array];
        gActive = [NSMutableDictionary dictionary];
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        gDiskDir = [(dirs.count ? dirs[0] : NSTemporaryDirectory()) stringByAppendingPathComponent:@"img"];
        [[NSFileManager defaultManager] createDirectoryAtPath:gDiskDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *n) { [self purgeOffscreen]; }];
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
    // Kiểm trên luồng nền: SecTrustEvaluate chờ tiến trình trustd của iOS (iOS 8 iPad mini 1: ~140 ms mỗi lần bắt tay — ảnh bìa
    // đang tải là chạm / cuộn khựng); lần đầu còn nạp 118 chứng chỉ gốc. Kết nối chờ trả lời, trả lời lại trên luồng chính.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SecTrustRef trust = space.serverTrust;
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)[self anchors]);
        SecTrustSetAnchorCertificatesOnly(trust, false);  // vẫn tin gốc của máy
        SecTrustResultType result = kSecTrustResultInvalid;
        BOOL ok = SecTrustEvaluate(trust, &result) == errSecSuccess &&
                  (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                [challenge.sender useCredential:[NSURLCredential credentialForTrust:trust] forAuthenticationChallenge:challenge];
            } else {
                CBLog(@"Chứng chỉ %@ không hợp lệ (%d)", space.host, (int)result);
                [challenge.sender cancelAuthenticationChallenge:challenge];
            }
        });
    });
}

+ (NSString *)debugStatus {
    return [NSString stringWithFormat:@"ảnh: đang tải %lu, chờ %lu, xong %ld, hỏng %ld, bỏ (ô không còn cần) %ld",
            (unsigned long)gActive.count, (unsigned long)gQueue.count, (long)gDone, (long)gFailed, gSkipped];
}

+ (void)clearMemory {
    [gMemory removeAllObjects];
}

+ (BOOL)lowRam {
    return [NSProcessInfo processInfo].physicalMemory < 300ull * 1024 * 1024;
}

+ (void)purgeOffscreen {
    [gMemory removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:CBImagesPurgeNotification object:nil];
    // Trả các trang nhớ đã giải phóng (của malloc — cả lõi Rust) về cho iOS: jetsam tính theo trang còn giữ, không theo phần đang dùng
    malloc_zone_pressure_relief(NULL, 0);
}

+ (unsigned long long)diskBytes {
    [self setup];
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *f in [fm contentsOfDirectoryAtPath:gDiskDir error:NULL] ?: @[]) {
        total += [[fm attributesOfItemAtPath:[gDiskDir stringByAppendingPathComponent:f] error:NULL] fileSize];
    }
    return total;
}

+ (void)clearDisk {
    [self setup];
    [gMemory removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *f in [fm contentsOfDirectoryAtPath:gDiskDir error:NULL] ?: @[]) {
        [fm removeItemAtPath:[gDiskDir stringByAppendingPathComponent:f] error:NULL];
    }
}

+ (NSString *)memKey:(NSString *)url spec:(CBImageSpec)s {
    if (CBSpecFill(s)) return [NSString stringWithFormat:@"%.0fx%.0f r%.0f %@", s.fill.width, s.fill.height, s.radius, url];
    return [NSString stringWithFormat:@"%.0f|%@", s.maxPx, url];
}

+ (void)load:(NSString *)url size:(CGSize)size into:(UIImageView *)iv {
    [self load:url size:size radius:-1 into:iv];
}

+ (void)load:(NSString *)url size:(CGSize)size radius:(CGFloat)radius into:(UIImageView *)iv {
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
    CGFloat scale = [UIScreen mainScreen].scale;
    CBImageSpec spec = {MAX(size.width, size.height) * scale, CGSizeZero, 0};
    if (radius >= 0 && size.width >= 1 && size.height >= 1) {
        spec.fill = CGSizeMake(round(size.width * scale), round(size.height * scale));
        spec.radius = radius * scale;
    }
    UIImage *hit = [gMemory objectForKey:[self memKey:url spec:spec]];
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
    dispatch_async(CBDecodeQueue(), ^{
        // Tới lượt mà ô đã đổi ảnh / màn đã đóng (vuốt nhanh qua danh sách dài): bỏ, khỏi giải mã — màn đang xem không phải chờ
        UIImageView *still = weakIv;
        if (!still || ![objc_getAssociatedObject(still, kUrlKey) isEqualToString:url]) return;
        still = nil;
        NSData *data = [NSData dataWithContentsOfFile:file];
        UIImage *img = data ? CBDecode(data, spec) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (img) {
                [gMemory setObject:img forKey:[self memKey:url spec:spec] cost:(NSUInteger)(img.size.width * img.size.height * 4 *
                                                                                         img.scale * img.scale)];
                // Ảnh có sẵn trên máy: hiện ngay, không mờ dần (mờ dần chỉ cho ảnh vừa tải về)
                UIImageView *v = weakIv;
                if (v && [objc_getAssociatedObject(v, kUrlKey) isEqualToString:url]) v.image = img;
                return;
            }
            [self enqueue:url spec:spec file:file deliver:deliver view:weakIv];
        });
    });
}

+ (void)cancel:(UIImageView *)iv {
    objc_setAssociatedObject(iv, kUrlKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// ---- Hàng đợi tải mạng ----

static NSMutableDictionary *gWaiters;  // url → mảng khối deliver

+ (void)enqueue:(NSString *)url spec:(CBImageSpec)spec file:(NSString *)file deliver:(void (^)(UIImage *))deliver
           view:(UIImageView *)view {
    if (!gWaiters) gWaiters = [NSMutableDictionary dictionary];
    if (!gWants) gWants = [NSMutableDictionary dictionary];
    CBImageWant *want = [[CBImageWant alloc] init];
    want.view = view;
    if (!gWants[url]) gWants[url] = [NSMutableArray array];
    [gWants[url] addObject:want];
    NSMutableArray *w = gWaiters[url];
    if (w) {
        [w addObject:[deliver copy]];
        return;
    }
    gWaiters[url] = [NSMutableArray arrayWithObject:[deliver copy]];
    CBImageJob *job = [[CBImageJob alloc] init];
    job.url = url;
    job.spec = spec;
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

/// iOS tải ảnh lỗi: lỗi TLS / chứng chỉ (máy cũ thiếu bộ mã / gốc mới), hết thời gian chờ (bắt tay TLS treo), không tìm / không
/// nối được máy chủ (DNS nhà mạng chặn — lõi hỏi DNS mã hoá, có vượt chặn) → thử bằng lõi
+ (BOOL)shouldRetryViaCore:(NSError *)error {
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    NSInteger c = error.code;
    return c == NSURLErrorTimedOut || c == NSURLErrorUserCancelledAuthentication || c == NSURLErrorCancelled ||
           c == NSURLErrorCannotFindHost || c == NSURLErrorCannotConnectToHost ||
           (c <= NSURLErrorSecureConnectionFailed && c >= NSURLErrorClientCertificateRequired);
}

+ (void)retryViaCore:(CBImageJob *)job error:(NSError *)error {
    NSString *host = [NSURL URLWithString:job.url].host;
    // Cả trang đó tải qua lõi từ giờ (khỏi chờ lỗi từng ảnh — bắt tay TLS treo thì mỗi ảnh mất 15 giây mới báo hết giờ).
    // Lỗi TLS / DNS thì nhớ sang lần mở app sau; hết thời gian chờ (có thể chỉ do mạng chập chờn) thì chỉ trong lần này
    if (host && ![gCoreHosts containsObject:host]) {
        [gCoreHosts addObject:host];
        BOOL tls = error.code != NSURLErrorTimedOut;
        CBLog(@"Ảnh của %@: iOS %@ — tải qua lõi", host, tls ? @"không kết nối được (TLS / DNS)" : @"chờ quá lâu");
        if (tls) {
            NSMutableArray *keep = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"CBCoreImageHosts"] ?: @[] mutableCopy];
            if (![keep containsObject:host]) [keep addObject:host];
            [[NSUserDefaults standardUserDefaults] setObject:keep forKey:@"CBCoreImageHosts"];
        }
    }
    job.conn = nil;
    [self fetchViaCore:job];
}

/// Còn ô nào đang hiện / chờ đúng ảnh này?
+ (BOOL)wanted:(NSString *)url {
    for (CBImageWant *w in gWants[url]) {
        UIImageView *v = w.view;
        if (v && [objc_getAssociatedObject(v, kUrlKey) isEqualToString:url]) return YES;
    }
    return NO;
}

+ (void)pump {
    BOOL viaCore = gQueue.count ? [self viaCore] : NO;
    while (gActive.count < kMaxActive && gQueue.count) {
        CBImageJob *job = gQueue.lastObject;
        [gQueue removeLastObject];
        if (![self wanted:job.url]) {
            [gWaiters removeObjectForKey:job.url];
            [gWants removeObjectForKey:job.url];
            gSkipped++;
            continue;
        }
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
    BOOL wanted = [self wanted:job.url];
    [gWants removeObjectForKey:job.url];
    job.conn = nil;
    NSArray *waiters = gWaiters[job.url] ?: @[];
    [gWaiters removeObjectForKey:job.url];
    NSString *file = [gDiskDir stringByAppendingPathComponent:CBMd5(job.url)];
    CBImageSpec spec = job.spec;
    NSString *url = job.url;
    if (!data.length) {
        gFailed++;
        CBLog(@"Ảnh hỏng (HTTP %ld): %@", (long)job.status, url);
    }
    if (data.length && !wanted) {
        // Tải xong mà không còn ô nào cần (đã cuộn qua): chỉ lưu đĩa, không giải mã — lần sau cần thì đọc từ đĩa
        dispatch_async(CBDecodeQueue(), ^{ [data writeToFile:file atomically:YES]; });
    } else if (data.length) {
        dispatch_async(CBDecodeQueue(), ^{
            UIImage *img = CBDecode(data, spec);
            if (img) [data writeToFile:file atomically:YES];
            if (!img) {
                const unsigned char *b = data.bytes;
                CBLog(@"Ảnh không giải mã được (%lu byte, đầu %02x%02x%02x%02x…%02x%02x%02x%02x): %@", (unsigned long)data.length,
                      b[0], b[1], b[2], b[3], data.length > 11 ? b[8] : 0, data.length > 11 ? b[9] : 0, data.length > 11 ? b[10] : 0,
                      data.length > 11 ? b[11] : 0, url);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) {
                    [gMemory setObject:img forKey:[self memKey:url spec:spec]
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
