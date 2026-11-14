#import "CBLog.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

NSString *CBLogPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *dir = dirs.count ? dirs[0] : NSTemporaryDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        path = [dir stringByAppendingPathComponent:@"ConBangLegacy-spike.log"];
    });
    return path;
}

void CBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[CB] %@", msg);

    static dispatch_queue_t queue;
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("vn.conbangtv.legacy.log", DISPATCH_QUEUE_SERIAL);
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss.SSS";
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
