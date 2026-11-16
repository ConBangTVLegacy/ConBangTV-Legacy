// cbupdate — cài bản cập nhật (OTA) của Côn Bằng TV Legacy, chạy quyền root (setuid, postinst đặt chown root + chmod 4755).
//   /usr/libexec/conbangtv/cbupdate <tệp .deb> [pid app]
//   /usr/libexec/conbangtv/cbupdate --respring <tệp .deb>   (postinst gọi khi bản cài là cbupdate cũ ≤ 0.4.2 — xem dưới)
// App tải .deb từ GitHub Releases (qua lõi, đã kiểm SHA-256) vào /var/mobile/Documents/ConBangTV-update/ rồi gọi công cụ này.
// Chỉ nhận tệp .deb nằm trong đúng thư mục đó và đúng gói vn.conbangtv.legacy (dpkg-deb -f … Package) — không cài gói khác.
// Kiểm xong thì tách nền (app chờ được mã thoát ngay), đóng app, dpkg -i, xoá tệp, khởi động lại SpringBoard (để nhận biểu
// tượng / tên mới — postinst đã xoá bộ đệm biểu tượng), rồi mở lại app (SpringBoardServices, quyền
// com.apple.springboard.launchapplications như tools/cblaunch). Không uicache, trừ khi bản mới đổi tên hiện dưới biểu tượng —
// uicache trên iOS 6 từng làm SpringBoard của iPad treo.
// dpkg chạy với CONBANG_OTA=1 để postinst biết cbupdate này tự khởi động lại SpringBoard. cbupdate ≤ 0.4.2 không làm việc đó:
// postinst thấy tệp .deb còn trong thư mục tải (cbupdate cũ chỉ xoá sau khi dpkg xong) thì gọi «--respring»: chờ tệp bị xoá
// (dpkg xong), khởi động lại SpringBoard, mở lại app.
// Nhật ký: /var/mobile/Documents/ConBangTV-update/install.log
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define UPDATE_DIR "/var/mobile/Documents/ConBangTV-update/"
#define PACKAGE "vn.conbangtv.legacy"
#define MOBILE_UID 501

extern char **environ;

static void logf_(const char *fmt, const char *a) {
    time_t t = time(NULL);
    char ts[32];
    strftime(ts, sizeof(ts), "%m-%d %H:%M:%S", localtime(&t));
    printf("%s ", ts);
    printf(fmt, a ? a : "");
    printf("\n");
    fflush(stdout);
}

/// Chạy lệnh, chờ xong, trả mã thoát (-1 = không chạy được). out: nhận stdout (có thể NULL)
static int run(char *const argv[], char *out, size_t outSize) {
    int fds[2] = {-1, -1};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    if (out) {
        if (pipe(fds) != 0) return -1;
        posix_spawn_file_actions_adddup2(&fa, fds[1], 1);
        posix_spawn_file_actions_addclose(&fa, fds[0]);
    }
    pid_t pid;
    int rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    if (out) close(fds[1]);
    if (rc != 0) {
        if (out) close(fds[0]);
        return -1;
    }
    if (out) {
        size_t n = 0;
        ssize_t r;
        while (n + 1 < outSize && (r = read(fds[0], out + n, outSize - 1 - n)) > 0) n += (size_t)r;
        out[n] = 0;
        close(fds[0]);
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/// Tên hiện dưới biểu tượng (CFBundleDisplayName trong Info.plist dạng XML của app); rỗng nếu không đọc được
static void displayName(char *out, size_t size) {
    out[0] = 0;
    FILE *f = fopen("/Applications/ConBangTV.app/Info.plist", "r");
    if (!f) return;
    char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    char *k = strstr(buf, "<key>CFBundleDisplayName</key>");
    char *s = k ? strstr(k, "<string>") : NULL;
    char *e = s ? strstr(s, "</string>") : NULL;
    if (!s || !e) return;
    s += 8;
    size_t len = (size_t)(e - s) < size - 1 ? (size_t)(e - s) : size - 1;
    memcpy(out, s, len);
    out[len] = 0;
}

static int launchApp(void) {
    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (!sbs) return -1;
    CFStringRef bundleId = CFSTR(PACKAGE);
    int (*launchWithOptions)(CFStringRef, CFDictionaryRef, Boolean) =
        (int (*)(CFStringRef, CFDictionaryRef, Boolean))dlsym(sbs, "SBSLaunchApplicationWithIdentifierAndLaunchOptions");
    int result = -1;
    if (launchWithOptions) {
        CFStringRef *unlockKey = (CFStringRef *)dlsym(sbs, "SBSApplicationLaunchOptionUnlockDeviceKey");
        CFStringRef key = unlockKey && *unlockKey ? *unlockKey : CFSTR("__UnlockDevice");
        const void *keys[] = {key};
        const void *values[] = {kCFBooleanTrue};
        CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        result = launchWithOptions(bundleId, options, false);
        CFRelease(options);
    }
    if (result != 0) {
        int (*launchPlain)(CFStringRef, Boolean) = (int (*)(CFStringRef, Boolean))dlsym(sbs, "SBSLaunchApplicationWithIdentifier");
        if (launchPlain) result = launchPlain(bundleId, false);
    }
    return result;
}

/// App đang ở trước màn hình?
static int appIsFrontmost(void) {
    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    CFStringRef (*copyFront)(void) = sbs ? (CFStringRef (*)(void))dlsym(sbs, "SBSCopyFrontmostApplicationDisplayIdentifier") : NULL;
    if (!copyFront) return 0;
    CFStringRef front = copyFront();
    int yes = front && CFStringCompare(front, CFSTR(PACKAGE), 0) == kCFCompareEqualTo;
    if (front) CFRelease(front);
    return yes;
}

/// Khởi động lại SpringBoard rồi mở lại app: SpringBoard lên lại mất ~15–30 giây (lúc đầu nhận lệnh mở app mà chưa mở thật),
/// nên thử tới khi app thật sự ở trước màn hình (tối đa ~90 giây)
static int respringAndRelaunch(void) {
    char *respring[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
    run(respring, NULL, 0);
    logf_("đã khởi động lại SpringBoard%s", "");
    sleep(12);
    for (int i = 0; i < 39; i++) {
        if (launchApp() == 0) {
            sleep(2);
            if (appIsFrontmost()) return 0;
        } else {
            sleep(2);
        }
    }
    return -1;
}

/// Tệp hợp lệ: đúng thư mục tải của app, đuôi .deb, tệp thường (realpath gỡ hết liên kết tượng trưng — trên iOS /var là liên
/// kết tới /private/var nên so với realpath của chính thư mục tải)
static int validDeb(const char *arg, char real[PATH_MAX]) {
    char dir[PATH_MAX];
    if (!realpath(arg, real) || !realpath(UPDATE_DIR, dir)) return 0;
    strlcat(dir, "/", PATH_MAX);
    size_t n = strlen(real), dn = strlen(dir);
    struct stat st;
    if (strncmp(real, dir, dn) != 0 || n < dn + 5 || strcmp(real + n - 4, ".deb") != 0 || strchr(real + dn, '/') ||
        stat(real, &st) != 0 || !S_ISREG(st.st_mode)) {
        fprintf(stderr, "tệp không hợp lệ: %s\n", real);
        return 0;
    }
    return 1;
}

/// Tách nền (cha thoát ngay), ghi nhật ký vào install.log. Trả 1 ở tiến trình con, 0 ở cha, -1 lỗi
static int detach(void) {
    pid_t child = fork();
    if (child < 0) return -1;
    if (child > 0) return 0;
    setsid();
    int logfd = open(UPDATE_DIR "install.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (logfd >= 0) {
        dup2(logfd, 1);
        dup2(logfd, 2);
        close(logfd);
    }
    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) dup2(devnull, 0);
    return 1;
}

/// «--respring <tệp .deb>»: bản cài đang chạy là cbupdate cũ — chờ nó cài xong (xoá tệp .deb) rồi khởi động lại SpringBoard và
/// mở lại app. Tệp không bị xoá trong 2 phút (tệp sót lại, không phải đang cài) thì thôi.
static int respringMode(const char *arg) {
    char real[PATH_MAX];
    if (!validDeb(arg, real)) return 65;
    if (setgid(0) != 0 || setuid(0) != 0) return 66;
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
    int d = detach();
    if (d <= 0) return d == 0 ? 0 : 70;
    struct stat st;
    int i = 0;
    for (; i < 600 && stat(real, &st) == 0; i++) usleep(200000);
    if (i == 600) {
        logf_("--respring: %s vẫn còn sau 2 phút — bỏ, không khởi động lại SpringBoard", real);
        return 1;
    }
    logf_("--respring: bản cài cũ đã cài xong%s", "");
    char code[16];
    snprintf(code, sizeof(code), "%d", respringAndRelaunch());
    logf_("mở lại app sau khi khởi động lại SpringBoard → %s", code);
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 3 && strcmp(argv[1], "--respring") == 0) return respringMode(argv[2]);
    if (argc < 2) {
        fprintf(stderr, "cách dùng: cbupdate <tệp .deb trong " UPDATE_DIR "> [pid app]\n");
        return 64;
    }
    // 1. Tệp: đúng thư mục tải của app (xem validDeb)
    char real[PATH_MAX];
    if (!validDeb(argv[1], real)) return 65;
    // 2. Quyền root (bit setuid do postinst đặt)
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "cbupdate cần quyền root (setuid) — cài lại gói " PACKAGE "\n");
        return 66;
    }
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
    // 3. Đúng gói của app
    char pkg[256] = {0};
    char *field[] = {"/usr/bin/dpkg-deb", "-f", real, "Package", NULL};
    if (run(field, pkg, sizeof(pkg)) != 0) return 67;
    pkg[strcspn(pkg, "\r\n")] = 0;
    if (strcmp(pkg, PACKAGE) != 0) {
        fprintf(stderr, "gói không phải " PACKAGE ": %s\n", pkg);
        return 68;
    }
    pid_t app = argc > 2 ? (pid_t)atoi(argv[2]) : 0;
    // 4. Tách nền: app nhận mã 0 ngay (đã kiểm xong), phần cài chạy tiếp sau khi app bị đóng
    int d = detach();
    if (d <= 0) return d == 0 ? 0 : 70;
    logf_("cài %s", real);
    sleep(1);
    if (app > 1) {
        kill(app, SIGTERM);
        for (int i = 0; i < 30 && kill(app, 0) == 0; i++) usleep(100000);
        if (kill(app, 0) == 0) kill(app, SIGKILL);
        logf_("đã đóng app%s", "");
    }
    char before[256], after[256];
    displayName(before, sizeof(before));
    char *install[] = {"/usr/bin/dpkg", "-i", real, NULL};
    setenv("CONBANG_OTA", "1", 1);  // postinst: cbupdate này tự khởi động lại SpringBoard
    int rc = run(install, NULL, 0);
    char code[16];
    snprintf(code, sizeof(code), "%d", rc);
    logf_("dpkg -i → %s", code);
    unlink(real);
    displayName(after, sizeof(after));
    // Cập nhật thường KHÔNG chạy uicache: app vẫn ở chỗ cũ nên SpringBoard mở được ngay; uicache trên iOS 6 có lúc làm
    // SpringBoard treo (iPad mini 1, 14/11/2026 — phải khởi động lại SpringBoard). Chỉ khi đổi tên hiện dưới biểu tượng mới
    // uicache (quyền mobile) để nhận tên mới — kể cả uicache làm treo thì bước khởi động lại SpringBoard ngay sau cũng gỡ được.
    if (rc == 0 && strcmp(before, after) != 0) {
        logf_("đổi tên app → %s: uicache + khởi động lại SpringBoard", after);
        pid_t u = fork();
        if (u == 0) {
            setgid(MOBILE_UID);
            setuid(MOBILE_UID);
            setenv("HOME", "/var/mobile", 1);
            execl("/usr/bin/uicache", "uicache", (char *)NULL);
            _exit(127);
        }
        if (u > 0) {
            int status;
            for (int i = 0; i < 300 && waitpid(u, &status, WNOHANG) == 0; i++) usleep(100000);  // tối đa 30 giây
            kill(u, SIGKILL);
        }
    }
    int launched;
    // iOS 5: khởi động lại SpringBoard xong máy về màn khoá (kể cả không đặt mật khẩu) — mở lại app không được (SpringBoardServices
    // báo lỗi 3, đã thử trên iPad 1 iOS 5.1.1) → chỉ mở lại app; biểu tượng mới hiện ở lần khởi động lại SpringBoard sau
    int oldIOS = kCFCoreFoundationVersionNumber < 793.0;  // 793.00 = iOS 6.0
    if (rc == 0 && !oldIOS) {
        // Cài xong: khởi động lại SpringBoard để nhận biểu tượng / tên mới (postinst đã xoá bộ đệm biểu tượng), rồi mở lại app
        launched = respringAndRelaunch();
    } else if (rc == 0) {
        logf_("iOS 5: không khởi động lại SpringBoard, chỉ mở lại app%s", "");
        sleep(1);
        launched = -1;
        for (int i = 0; i < 10 && launched != 0; i++) {
            launched = launchApp();
            if (launched != 0) sleep(2);
        }
    } else {
        // Cài lỗi: bản cũ vẫn nguyên, chỉ mở lại app
        sleep(1);
        launched = launchApp();
        if (launched != 0) {  // SpringBoard đang bận: thử lại một lần
            sleep(3);
            launched = launchApp();
        }
    }
    snprintf(code, sizeof(code), "%d", launched);
    logf_("mở lại app → %s", code);
    return rc == 0 ? 0 : 1;
}
