// cblaunch — điều khiển SpringBoard từ SSH trên máy iOS 6 jailbreak, để em tự chạy thử không cần chạm màn hình:
//   cblaunch status            màn hình khoá? có mật khẩu? app nào đang ở trước
//   cblaunch wake              bật sáng màn hình
//   cblaunch launch <mã gói>   mở app (kèm yêu cầu mở khoá — máy không đặt mật khẩu)
// Hàm của SpringBoardServices (API riêng) tra bằng dlsym lúc chạy: bản SDK 9.3 có những hàm iOS 6 không có, liên kết cứng thì
// thiếu một hàm là dyld không cho chạy. Cần quyền com.apple.springboard.launchapplications (entitlements.plist).
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>

static void *sbs;

static void *sym(const char *name) {
    void *p = sbs ? dlsym(sbs, name) : NULL;
    if (!p) fprintf(stderr, "(không có hàm %s trên máy này)\n", name);
    return p;
}

static void printFrontmost(void) {
    CFStringRef (*copyFront)(void) = (CFStringRef (*)(void))sym("SBSCopyFrontmostApplicationDisplayIdentifier");
    if (!copyFront) return;
    CFStringRef front = copyFront();
    char buf[256] = "(màn hình chính)";
    if (front) {
        CFStringGetCString(front, buf, sizeof(buf), kCFStringEncodingUTF8);
        CFRelease(front);
    }
    printf("frontmost=%s\n", buf);
}

static int status(void) {
    mach_port_t (*serverPort)(void) = (mach_port_t (*)(void))sym("SBSSpringBoardServerPort");
    void (*lockStatus)(mach_port_t, Boolean *, Boolean *) =
        (void (*)(mach_port_t, Boolean *, Boolean *))sym("SBGetScreenLockStatus");
    if (serverPort && lockStatus) {
        Boolean locked = 0, passcode = 0;
        lockStatus(serverPort(), &locked, &passcode);
        printf("locked=%d passcode=%d\n", locked, passcode);
    }
    printFrontmost();
    return 0;
}

static int wake(void) {
    void (*undim)(void) = (void (*)(void))sym("SBSUndimScreen");
    if (!undim) return 1;
    undim();
    printf("đã bật sáng màn hình\n");
    return 0;
}

static int launch(const char *bundle) {
    CFStringRef bundleId = CFStringCreateWithCString(NULL, bundle, kCFStringEncodingUTF8);
    int result = -1;
    int (*launchWithOptions)(CFStringRef, CFDictionaryRef, Boolean) =
        (int (*)(CFStringRef, CFDictionaryRef, Boolean))dlsym(sbs, "SBSLaunchApplicationWithIdentifierAndLaunchOptions");
    if (launchWithOptions) {
        CFStringRef *unlockKey = (CFStringRef *)dlsym(sbs, "SBSApplicationLaunchOptionUnlockDeviceKey");
        CFStringRef key = unlockKey && *unlockKey ? *unlockKey : CFSTR("__UnlockDevice");
        const void *keys[] = {key};
        const void *values[] = {kCFBooleanTrue};
        CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        result = launchWithOptions(bundleId, options, false);
        CFRelease(options);
        printf("launch (kèm mở khoá) → %d\n", result);
    }
    if (result != 0) {
        int (*launchPlain)(CFStringRef, Boolean) = (int (*)(CFStringRef, Boolean))sym("SBSLaunchApplicationWithIdentifier");
        if (launchPlain) {
            result = launchPlain(bundleId, false);
            printf("launch → %d\n", result);
        }
    }
    CFRelease(bundleId);
    return result == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (!sbs) {
        fprintf(stderr, "không mở được SpringBoardServices: %s\n", dlerror());
        return 1;
    }
    if (argc >= 2 && !strcmp(argv[1], "status")) return status();
    if (argc >= 2 && !strcmp(argv[1], "wake")) return wake();
    if (argc >= 3 && !strcmp(argv[1], "launch")) return launch(argv[2]);
    fprintf(stderr, "cách dùng: cblaunch status | wake | launch <mã gói>\n");
    return 2;
}
