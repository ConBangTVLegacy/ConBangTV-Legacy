#import "CBLog.h"
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <sys/time.h>

NSString *CBDocumentsDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        dir = dirs.count ? dirs[0] : NSTemporaryDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    return dir;
}

NSString *CBLogPath(void) {
    return [CBDocumentsDir() stringByAppendingPathComponent:@"ConBangTV.log"];
}

void CBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[CBTV] %@", msg);

    static dispatch_queue_t queue;
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("vn.conbangtv.legacy.log", DISPATCH_QUEUE_SERIAL);
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd HH:mm:ss.SSS";
        // Tệp quá 1 MB thì bắt đầu tệp mới (giữ một bản cũ)
        NSString *path = CBLogPath();
        if ([[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize] > 1000000) {
            NSString *old = [path stringByAppendingString:@".1"];
            [[NSFileManager defaultManager] removeItemAtPath:old error:NULL];
            [[NSFileManager defaultManager] moveItemAtPath:path toPath:old error:NULL];
        }
    });
    NSDate *now = [NSDate date];
    dispatch_async(queue, ^{
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:now], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:CBLogPath()];
        if (!h) {
            [data writeToFile:CBLogPath() atomically:NO];
            return;
        }
        [h seekToEndOfFile];
        [h writeData:data];
        [h closeFile];
    });
}

NSString *CBDeviceModel(void) {
    char buf[64] = {0};
    size_t len = sizeof(buf) - 1;
    if (sysctlbyname("hw.machine", buf, &len, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buf] ?: @"?";
}

double CBResidentMB(void) {
    struct task_basic_info info;
    mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.resident_size / 1048576.0;
}

long long CBNowMs(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}
