// cbscreen — chụp toàn màn hình máy iOS 6 jailbreak từ SSH (cả màn hình chính / màn khoá), ghi PNG.
//   cbscreen <tệp.png> [rộng cao]   (mặc định 640 1136 — iPhone 5; iPad mini 1: 768 1024)
// IOSurface + CARenderServerRenderDisplay (API riêng) tra bằng dlsym lúc chạy.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach_time.h>

typedef void *IOSurfaceRef;

static CFNumberRef num(int v) { return CFNumberCreate(NULL, kCFNumberIntType, &v); }

// Nhấn nút Home giả (GraphicsServices): từ một app đang mở thì về màn hình chính
typedef struct {
    int type, subtype;
    CGPoint location, windowLocation;
    int windowContextId;
    uint64_t timestamp;
    void *window;
    unsigned flags, senderPID;
    CFIndex infoSize;
} GSEventRecord;

static int home(void) {
    void *gs = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
    void (*sendSystem)(GSEventRecord *) = gs ? dlsym(gs, "GSSendSystemEvent") : NULL;
    uint64_t (*now)(void) = gs ? dlsym(gs, "GSCurrentEventTimestamp") : NULL;
    if (!sendSystem) { fprintf(stderr, "không có GSSendSystemEvent\n"); return 1; }
    for (int t = 1000; t <= 1001; t++) {  // kGSEventMenuButtonDown / Up
        GSEventRecord r;
        memset(&r, 0, sizeof(r));
        r.type = t;
        r.timestamp = now ? now() : mach_absolute_time();
        r.senderPID = getpid();
        sendSystem(&r);
        usleep(120000);
    }
    printf("đã nhấn Home\n");
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "home")) return home();
    const char *out = argc > 1 ? argv[1] : "/tmp/cbscreen.png";
    int w = argc > 3 ? atoi(argv[2]) : 640, h = argc > 3 ? atoi(argv[3]) : 1136;
    void *ios = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_NOW);
    void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
    if (!ios || !qc) { fprintf(stderr, "không nạp được IOSurface / QuartzCore\n"); return 1; }
    IOSurfaceRef (*create)(CFDictionaryRef) = dlsym(ios, "IOSurfaceCreate");
    void *(*base)(IOSurfaceRef) = dlsym(ios, "IOSurfaceGetBaseAddress");
    size_t (*rowBytes)(IOSurfaceRef) = dlsym(ios, "IOSurfaceGetBytesPerRow");
    int (*lock)(IOSurfaceRef, uint32_t, uint32_t *) = dlsym(ios, "IOSurfaceLock");
    int (*unlock)(IOSurfaceRef, uint32_t, uint32_t *) = dlsym(ios, "IOSurfaceUnlock");
    void (*render)(mach_port_t, CFStringRef, IOSurfaceRef, int, int) = dlsym(qc, "CARenderServerRenderDisplay");
    if (!create || !base || !rowBytes || !lock || !unlock || !render) { fprintf(stderr, "thiếu hàm\n"); return 1; }

    int bpe = 4, bpr = w * bpe, fmt = 'BGRA', size = bpr * h;
    const void *keys[] = {CFSTR("IOSurfaceIsGlobal"), CFSTR("IOSurfaceBytesPerElement"), CFSTR("IOSurfaceBytesPerRow"),
                          CFSTR("IOSurfaceWidth"), CFSTR("IOSurfaceHeight"), CFSTR("IOSurfacePixelFormat"),
                          CFSTR("IOSurfaceAllocSize")};
    const void *vals[] = {kCFBooleanTrue, num(bpe), num(bpr), num(w), num(h), num(fmt), num(size)};
    CFDictionaryRef props = CFDictionaryCreate(NULL, keys, vals, 7, &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    IOSurfaceRef surface = create(props);
    if (!surface) { fprintf(stderr, "không tạo được IOSurface\n"); return 1; }
    lock(surface, 0, NULL);
    render(0, CFSTR("LCD"), surface, 0, 0);
    void *px = base(surface);
    size_t stride = rowBytes(surface);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, stride, cs, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    // «cw»: xoay 90° theo chiều kim đồng hồ — iPad 1 iOS 5 trả khung hình nằm ngang (chụp 1024 768 cw → ảnh dọc 768×1024)
    if (argc > 4 && !strcmp(argv[4], "cw")) {
        CGContextRef rc = CGBitmapContextCreate(NULL, h, w, 8, 0, cs, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
        CGContextTranslateCTM(rc, 0, w);
        CGContextRotateCTM(rc, -M_PI_2);
        CGContextDrawImage(rc, CGRectMake(0, 0, w, h), img);
        CGImageRelease(img);
        img = CGBitmapContextCreateImage(rc);
        int t = w;
        w = h;
        h = t;
    }
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)out, strlen(out), false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    unlock(surface, 0, NULL);
    printf("%s %s (%dx%d)\n", ok ? "ghi" : "lỗi ghi", out, w, h);
    return ok ? 0 : 1;
}
