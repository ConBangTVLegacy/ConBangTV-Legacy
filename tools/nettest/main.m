// nettest — thử tải URL bằng thư viện mạng của chính iOS (NSURLConnection, kho chứng chỉ gốc của máy): biết Safari / Cydia /
// cài itms-services trên máy iOS 6 có vào được trang đó không. Dựng: make (Theos) → chép vào máy → nettest <url>…
#import <Foundation/Foundation.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSURL *u = [NSURL URLWithString:[NSString stringWithUTF8String:argv[i]]];
            NSURLRequest *r = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
            NSHTTPURLResponse *resp = nil;
            NSError *err = nil;
            NSDate *t0 = [NSDate date];
            NSData *d = [NSURLConnection sendSynchronousRequest:r returningResponse:&resp error:&err];
            int ms = (int)(-[t0 timeIntervalSinceNow] * 1000);
            if (err) {
                printf("%s\n  → LỖI %ld (%s) %s, %d ms\n", argv[i], (long)err.code, err.domain.UTF8String,
                       err.localizedDescription.UTF8String, ms);
            } else {
                printf("%s\n  → HTTP %ld, %lu byte, %d ms (cuối: %s)\n", argv[i], (long)resp.statusCode, (unsigned long)d.length, ms,
                       resp.URL.host.UTF8String);
            }
        }
    }
    return 0;
}
