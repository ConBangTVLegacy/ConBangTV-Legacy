#import "CBListImport.h"
#import "CBIPTV.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBTheme.h"
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

/// Tệp danh sách lớn nhất nhận / đọc (danh sách IPTV lớn cỡ vài MB)
static const NSUInteger kMaxListBytes = 30 * 1024 * 1024;

// ---- Trang nhận tệp trên Wi-Fi (chỉ mở khi hộp «Gửi tệp từ máy tính» đang hiện) ----
static volatile BOOL gRunning;
static NSString *gAddress;
static CBAlert *gUploadAlert;
static void (^gUploadDone)(NSDictionary *);

/// Địa chỉ IPv4 của máy trên Wi-Fi (en0); không có Wi-Fi thì nil
static NSString *CBWifiAddress(void) {
    struct ifaddrs *ifs = NULL;
    NSString *ip = nil;
    if (getifaddrs(&ifs) != 0) return nil;
    for (struct ifaddrs *i = ifs; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || strcmp(i->ifa_name, "en0") != 0) continue;
        char buf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((struct sockaddr_in *)(void *)i->ifa_addr)->sin_addr, buf, sizeof buf)) ip = @(buf);
    }
    freeifaddrs(ifs);
    return ip;
}

static NSString *CBHtml(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

/// Trang cho trình duyệt trên máy tính: chọn tệp (hoặc dán nội dung), tên tuỳ chọn; `msg` = kết quả lần gửi trước
static NSString *CBPage(NSString *msg, BOOL error) {
    NSString *box = msg ? [NSString stringWithFormat:@"<p class=\"%@\">%@</p>", error ? @"err" : @"ok", CBHtml(msg)] : @"";
    return [NSString stringWithFormat:
        @"<!doctype html><html lang=\"vi\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        @"<title>Gửi danh sách kênh — Côn Bằng TV Legacy</title><style>"
        @"body{font:16px/1.5 -apple-system,'Segoe UI',Helvetica,Arial,sans-serif;background:#eef0f3;color:#1d1d1f;margin:0;padding:24px}"
        @"main{max-width:560px;margin:0 auto;background:#fff;border-radius:12px;padding:24px 28px;box-shadow:0 1px 3px rgba(0,0,0,.15)}"
        @"h1{font-size:22px;margin:0 0 6px}p{color:#555;margin:0 0 16px}label{display:block;font-weight:600;margin-top:14px}"
        @"input[type=file],input[type=text],textarea{display:block;width:100%%;box-sizing:border-box;margin-top:6px;font:inherit;font-weight:400}"
        @"input[type=text],textarea{border:1px solid #c8cbd0;border-radius:6px;padding:8px}textarea{height:110px;font-family:monospace;font-size:13px}"
        @"button{margin-top:20px;font:inherit;font-weight:600;background:#1f9d6b;color:#fff;border:0;border-radius:8px;padding:10px 26px;cursor:pointer}"
        @".ok{background:#e7f6ee;border-radius:8px;padding:10px 14px;color:#145c3d}.err{background:#fdeceb;border-radius:8px;padding:10px 14px;color:#8a1f17}"
        @".small{font-size:13px;color:#777;margin-top:18px}</style></head><body><main>"
        @"<h1>Gửi danh sách kênh</h1><p>tới <b>Côn Bằng TV Legacy</b> trên <b>%@</b>. Chọn tệp <b>.m3u / .m3u8</b> trên máy tính rồi bấm "
        @"<b>Gửi</b>. Giữ hộp «Gửi tệp từ máy tính» trên máy mở tới khi xong.</p>%@"
        @"<form method=\"post\" action=\"/upload\" enctype=\"multipart/form-data\">"
        @"<label>Tệp danh sách<input type=\"file\" name=\"file\" accept=\".m3u,.m3u8,.txt\"></label>"
        @"<label>Tên hiện trong app <span style=\"font-weight:400;color:#777\">(không bắt buộc)</span><input type=\"text\" name=\"name\" maxlength=\"40\"></label>"
        @"<label>…hoặc dán nội dung danh sách<textarea name=\"text\" placeholder=\"#EXTM3U&#10;#EXTINF:-1 group-title=&quot;Tin tức&quot;,Tên kênh&#10;http://…/kenh.m3u8\"></textarea></label>"
        @"<button type=\"submit\">Gửi</button></form>"
        @"<p class=\"small\">App không kèm sẵn kênh — chỉ gửi danh sách anh / chị có quyền xem. Trang này chỉ mở khi hộp gửi tệp đang hiện trên máy.</p>"
        @"</main></body></html>", CBHtml([UIDevice currentDevice].name ?: @"iPhone / iPad"), box];
}

static BOOL CBSendAll(int fd, NSData *d) {
    const uint8_t *p = d.bytes;
    size_t left = d.length;
    while (left) {
        ssize_t n = send(fd, p, left, 0);
        if (n <= 0) return NO;
        p += n;
        left -= (size_t)n;
    }
    return YES;
}

static void CBReply(int fd, int code, NSString *html) {
    NSData *body = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSString *reason = code == 200 ? @"OK" : (code == 404 ? @"Not Found" : (code == 413 ? @"Payload Too Large" : @"Bad Request"));
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\n"
                                                @"Cache-Control: no-store\r\nConnection: close\r\n\r\n", code, reason, (unsigned long)body.length];
    if (CBSendAll(fd, [head dataUsingEncoding:NSUTF8StringEncoding])) CBSendAll(fd, body);
}

/// `name="file"; filename="x.m3u"` → giá trị của khoá (khoá đứng sau đầu dòng, «;» hoặc khoảng trắng — «name» không khớp trong «filename»)
static NSString *CBHeaderParam(NSString *h, NSString *key) {
    NSString *pattern = [NSString stringWithFormat:@"(?:^|[;\\s])%@=\"([^\"]*)\"", key];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:h options:0 range:NSMakeRange(0, h.length)];
    return m ? [h substringWithRange:[m rangeAtIndex:1]] : nil;
}

/// multipart/form-data → {tên trường: {data, filename?}}
static NSDictionary *CBParseMultipart(NSData *body, NSString *ctype) {
    NSRange b = [ctype rangeOfString:@"boundary=" options:NSCaseInsensitiveSearch];
    if (b.location == NSNotFound) return nil;
    NSString *boundary = [ctype substringFromIndex:NSMaxRange(b)];
    NSRange semi = [boundary rangeOfString:@";"];
    if (semi.location != NSNotFound) boundary = [boundary substringToIndex:semi.location];
    boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" "]];
    if (!boundary.length) return nil;
    NSData *delim = [[@"--" stringByAppendingString:boundary] dataUsingEncoding:NSASCIIStringEncoding];
    NSData *blank = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSRange r = [body rangeOfData:delim options:0 range:NSMakeRange(0, body.length)];
    while (r.location != NSNotFound) {
        NSUInteger start = NSMaxRange(r);
        if (start + 2 > body.length || memcmp((const uint8_t *)body.bytes + start, "--", 2) == 0) break;  // «--boundary--»: hết
        NSRange next = [body rangeOfData:delim options:0 range:NSMakeRange(start, body.length - start)];
        if (next.location == NSNotFound) break;
        NSUInteger ps = start + 2, pe = next.location >= 2 ? next.location - 2 : next.location;  // bỏ CRLF hai đầu
        if (pe > ps) {
            NSData *part = [body subdataWithRange:NSMakeRange(ps, pe - ps)];
            NSRange he = [part rangeOfData:blank options:0 range:NSMakeRange(0, part.length)];
            if (he.location != NSNotFound) {
                NSData *hd = [part subdataWithRange:NSMakeRange(0, he.location)];
                NSString *hs = [[NSString alloc] initWithData:hd encoding:NSUTF8StringEncoding]
                               ?: [[NSString alloc] initWithData:hd encoding:NSISOLatin1StringEncoding];
                NSString *field = CBHeaderParam(hs, @"name"), *filename = CBHeaderParam(hs, @"filename");
                if (field) {
                    NSMutableDictionary *f = [NSMutableDictionary dictionary];
                    f[@"data"] = [part subdataWithRange:NSMakeRange(NSMaxRange(he), part.length - NSMaxRange(he))];
                    if (filename) f[@"filename"] = filename;
                    out[field] = f;
                }
            }
        }
        r = next;
    }
    return out;
}

@interface CBListImport ()
+ (NSDictionary *)receivedData:(NSData *)data fileName:(NSString *)fileName name:(NSString *)name error:(NSString **)error;
@end

/// Một kết nối: đọc yêu cầu HTTP, GET / → trang, POST /upload → thêm danh sách (trên luồng chính), trả trang kết quả
static void CBServe(int fd) {
    struct timeval tv = {30, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    NSMutableData *buf = [NSMutableData data];
    NSData *sep = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    uint8_t tmp[16384];
    NSRange hdrEnd = NSMakeRange(NSNotFound, 0);
    while (hdrEnd.location == NSNotFound) {
        ssize_t n = recv(fd, tmp, sizeof tmp, 0);
        if (n <= 0) return;
        [buf appendBytes:tmp length:(NSUInteger)n];
        hdrEnd = [buf rangeOfData:sep options:0 range:NSMakeRange(0, buf.length)];
        if (hdrEnd.location == NSNotFound && buf.length > 65536) return;
    }
    NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, hdrEnd.location)] encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *rl = [lines.firstObject componentsSeparatedByString:@" "];
    NSString *method = rl.count > 0 ? rl[0] : @"", *path = rl.count > 1 ? rl[1] : @"/";
    unsigned long long clen = 0;
    NSString *ctype = @"";
    for (NSString *l in lines) {
        NSRange c = [l rangeOfString:@":"];
        if (c.location == NSNotFound) continue;
        NSString *k = [[l substringToIndex:c.location] lowercaseString];
        NSString *v = [[l substringFromIndex:c.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([k isEqualToString:@"content-length"]) clen = (unsigned long long)MAX(0, [v longLongValue]);
        if ([k isEqualToString:@"content-type"]) ctype = v;
    }
    if ([method isEqualToString:@"GET"]) {
        if ([path isEqualToString:@"/"] || [path hasPrefix:@"/?"] || [path hasPrefix:@"/upload"]) CBReply(fd, 200, CBPage(nil, NO));
        else CBReply(fd, 404, @"Không có trang này.");
        return;
    }
    if (![method isEqualToString:@"POST"] || ![path hasPrefix:@"/upload"]) {
        CBReply(fd, 404, @"Không có trang này.");
        return;
    }
    if (clen > kMaxListBytes) {
        CBReply(fd, 413, CBPage(@"Tệp quá lớn (tối đa 30 MB).", YES));
        return;
    }
    NSMutableData *body = [[buf subdataWithRange:NSMakeRange(NSMaxRange(hdrEnd), buf.length - NSMaxRange(hdrEnd))] mutableCopy];
    while (body.length < clen) {
        ssize_t n = recv(fd, tmp, (size_t)MIN((unsigned long long)sizeof tmp, clen - body.length), 0);
        if (n <= 0) return;
        [body appendBytes:tmp length:(NSUInteger)n];
    }
    NSDictionary *form = CBParseMultipart(body, ctype);
    NSData *data = form[@"file"][@"data"];
    NSString *fileName = form[@"file"][@"filename"];
    if (!data.length) {
        data = form[@"text"][@"data"];
        fileName = @"danh-sach-dan.m3u";
    }
    NSString *name = form[@"name"][@"data"] ? [[NSString alloc] initWithData:form[@"name"][@"data"] encoding:NSUTF8StringEncoding] : nil;
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!data.length) {
        CBReply(fd, 400, CBPage(@"Chưa chọn tệp nào (hoặc nội dung dán trống).", YES));
        return;
    }
    __block NSDictionary *list = nil;
    __block NSString *err = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString *e = nil;
        list = [CBListImport receivedData:data fileName:fileName name:name error:&e];
        err = e;
    });
    if (list) {
        CBReply(fd, 200, CBPage([NSString stringWithFormat:@"Đã gửi «%@» (%lu KB) — danh sách «%@» đang được đọc trên máy.",
                                 fileName.lastPathComponent, (unsigned long)MAX(1, data.length / 1024), CBStr(list, @"name")], NO));
    } else {
        CBReply(fd, 400, CBPage(err ?: @"Không thêm được danh sách.", YES));
    }
}

@implementation CBListImport

+ (NSString *)uploadAddress {
    return gRunning ? gAddress : nil;
}

+ (void)serverThread:(NSNumber *)listenFd {
    @autoreleasepool {
        int lfd = listenFd.intValue;
        while (gRunning) {
            struct pollfd p = {lfd, POLLIN, 0};
            int r = poll(&p, 1, 500);
            if (!gRunning) break;
            if (r <= 0) continue;
            int c = accept(lfd, NULL, NULL);
            if (c < 0) continue;
            @autoreleasepool {
                CBServe(c);
            }
            close(c);
        }
        close(lfd);
    }
}

/// Mở cổng (8790…8799, bỏ 8791 / 8792 của Đồng bộ); trả địa chỉ trang, nil = không có Wi-Fi / không mở được cổng
+ (NSString *)startServer {
    if (gRunning) return gAddress;
    NSString *ip = CBWifiAddress();
    if (!ip) return nil;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_len = sizeof a;
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_ANY);
    uint16_t port = 0;
    for (uint16_t p = 8790; p < 8800 && !port; p++) {
        if (p == 8791 || p == 8792) continue;
        a.sin_port = htons(p);
        if (bind(fd, (struct sockaddr *)&a, sizeof a) == 0) port = p;
    }
    if (!port || listen(fd, 8) != 0) {
        close(fd);
        return nil;
    }
    gRunning = YES;
    gAddress = [NSString stringWithFormat:@"http://%@:%u", ip, port];
    [NSThread detachNewThreadSelector:@selector(serverThread:) toTarget:self withObject:@(fd)];
    CBLog(@"Truyền hình: mở trang nhận danh sách %@", gAddress);
    return gAddress;
}

+ (void)stopServer {
    if (gRunning) CBLog(@"Truyền hình: đóng trang nhận danh sách");
    gRunning = NO;
    gAddress = nil;
}

/// Danh sách vừa thêm: đọc ngay (nền), báo số kênh
+ (void)loaded:(NSDictionary *)l done:(void (^)(NSDictionary *))done {
    [CBIPTV refresh:YES done:^(NSString *err) {
        [CBTheme toast:err ?: [NSString stringWithFormat:@"Đã thêm «%@» — %lu kênh.", CBStr(l, @"name"), (unsigned long)[CBIPTV channels].count]];
    }];
    if (done) done(l);
}

+ (NSDictionary *)receivedData:(NSData *)data fileName:(NSString *)fileName name:(NSString *)name error:(NSString **)error {
    NSDictionary *l = [CBIPTV addListWithData:data fileName:fileName name:name error:error];
    if (!l) return nil;
    CBLog(@"Truyền hình: máy tính gửi «%@» (%lu byte)", fileName, (unsigned long)data.length);
    void (^done)(NSDictionary *) = gUploadDone;
    // Nhận xong: đóng hộp (đóng bằng mã thì CBAlert không gọi khối done — tự đóng trang nhận)
    [gUploadAlert dismissWithClickedButtonIndex:gUploadAlert.cancelButtonIndex animated:YES];
    gUploadAlert = nil;
    gUploadDone = nil;
    [self stopServer];
    [self loaded:l done:done];
    return l;
}

+ (void)ask:(void (^)(NSDictionary *))done {
    [[CBAlert title:@"Thêm danh sách kênh" message:@"Danh sách M3U / M3U8 mà anh có quyền xem — app không kèm sẵn kênh." cancel:@"Huỷ"
             others:@[@"Nhập địa chỉ (http…)", @"Gửi tệp từ máy tính (Wi-Fi)", @"Chọn tệp .m3u trên máy này"]
               done:^(CBAlert *a, NSInteger index) {
        if (index == a.cancelButtonIndex) return;
        NSInteger k = index - a.firstOtherButtonIndex;
        // Hộp sau mở khi hộp này đã đóng hẳn (iOS 5 / 6: mở hộp mới lúc hộp cũ đang đóng thì hộp mới không hiện)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (k == 0) [self askURL:done];
            else if (k == 1) [self showUpload:done];
            else [self pickLocal:done];
        });
    }] show];
}

+ (void)askURL:(void (^)(NSDictionary *))done {
    CBAlert *a = [CBAlert title:@"Thêm danh sách kênh" message:@"Địa chỉ danh sách M3U / M3U8 (http…)" cancel:@"Huỷ"
                         others:@[@"Thêm"] done:^(CBAlert *alert, NSInteger index) {
        if (index == alert.cancelButtonIndex) return;
        NSString *url = [[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (url.length < 8) {
            [CBTheme toast:@"Chưa có địa chỉ danh sách."];
            return;
        }
        NSDictionary *l = [CBIPTV addList:url name:nil];
        CBLog(@"Truyền hình: thêm danh sách %@", url);
        [CBIPTV refresh:YES done:^(NSString *err) {
            [CBTheme toast:err ?: [NSString stringWithFormat:@"Đã tải %lu kênh.", (unsigned long)[CBIPTV channels].count]];
        }];
        if (done) done(l);
    }];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *f = [a textFieldAtIndex:0];
    f.keyboardType = UIKeyboardTypeURL;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.placeholder = @"http://…/danh-sach.m3u";
    [a show];
}

+ (void)showUpload:(void (^)(NSDictionary *))done {
    NSString *addr = [self startServer];
    if (!addr) {
        [[CBAlert title:@"Chưa nối Wi-Fi" message:@"Máy cần nối cùng mạng Wi-Fi với máy tính để nhận tệp." cancel:@"Đóng" others:nil done:nil] show];
        return;
    }
    gUploadDone = [done copy];
    gUploadAlert = [CBAlert title:@"Gửi tệp từ máy tính"
                          message:[NSString stringWithFormat:@"Trên máy tính dùng chung Wi-Fi, mở trình duyệt vào địa chỉ\n\n%@\n\n"
                                                              @"chọn tệp .m3u / .m3u8 rồi bấm «Gửi». Giữ hộp này mở tới khi xong.", addr]
                           cancel:@"Đóng" others:nil done:^(CBAlert *a, NSInteger index) {
        gUploadAlert = nil;
        gUploadDone = nil;
        [self stopServer];
    }];
    [gUploadAlert show];
}

+ (NSArray *)localFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = CBDocumentsDir();
    // Chỗ hay chép tệp vào: Documents (Filza / iFile / SSH), Inbox («Mở bằng»), Media + Downloads (iFunBox, Safari tải về…)
    NSMutableArray *dirs = [NSMutableArray arrayWithObjects:docs, [docs stringByAppendingPathComponent:@"Inbox"], @"/var/mobile/Media",
                                                            @"/var/mobile/Media/Downloads", @"/var/mobile/Downloads", @"/var/mobile", nil];
    // Một lớp thư mục con của Documents (trừ dữ liệu của app)
    NSSet *skip = [NSSet setWithArray:@[@"ConBangTV-iptv", @"ConBangTV-update", @"cbtv-core", @"shots", @"Inbox"]];
    for (NSString *sub in [fm contentsOfDirectoryAtPath:docs error:NULL]) {
        BOOL dir = NO;
        NSString *p = [docs stringByAppendingPathComponent:sub];
        if (![skip containsObject:sub] && [fm fileExistsAtPath:p isDirectory:&dir] && dir) [dirs addObject:p];
    }
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *d in dirs) {
        for (NSString *n in [fm contentsOfDirectoryAtPath:d error:NULL]) {
            NSString *ext = n.pathExtension.lowercaseString;
            if (![ext isEqualToString:@"m3u"] && ![ext isEqualToString:@"m3u8"]) continue;
            NSString *p = [[d stringByAppendingPathComponent:n] stringByResolvingSymlinksInPath];
            if ([seen containsObject:p]) continue;
            NSDictionary *attr = [fm attributesOfItemAtPath:p error:NULL];
            if (![attr.fileType isEqualToString:NSFileTypeRegular] || attr.fileSize == 0 || attr.fileSize > kMaxListBytes) continue;
            [seen addObject:p];
            [out addObject:@{@"path": p, @"name": n, @"size": @(attr.fileSize), @"date": attr.fileModificationDate ?: [NSDate distantPast]}];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    return out;
}

+ (void)pickLocal:(void (^)(NSDictionary *))done {
    NSArray *files = [self localFiles];
    if (!files.count) {
        [[CBAlert title:@"Không thấy tệp .m3u nào"
                message:@"Chép tệp .m3u / .m3u8 vào thư mục Documents hoặc Media của máy (Filza, iFunBox, SSH…) rồi thử lại — "
                        @"hoặc chọn «Gửi tệp từ máy tính (Wi-Fi)»."
                 cancel:@"Đóng" others:nil done:nil] show];
        return;
    }
    if (files.count > 8) files = [files subarrayWithRange:NSMakeRange(0, 8)];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSDictionary *f in files) {
        double kb = MAX(1, [f[@"size"] doubleValue] / 1024);
        [titles addObject:[NSString stringWithFormat:@"%@ · %@", f[@"name"], kb >= 1024 ? [NSString stringWithFormat:@"%.1f MB", kb / 1024]
                                                                                       : [NSString stringWithFormat:@"%.0f KB", kb]]];
    }
    [[CBAlert title:@"Chọn tệp danh sách" message:@"Tệp .m3u / .m3u8 trên máy (mới nhất trước)" cancel:@"Huỷ" others:titles
               done:^(CBAlert *a, NSInteger index) {
        if (index == a.cancelButtonIndex) return;
        NSInteger k = index - a.firstOtherButtonIndex;
        if (k >= 0 && k < (NSInteger)files.count) [self importFile:files[k][@"path"] done:done];
    }] show];
}

+ (BOOL)importFile:(NSString *)path done:(void (^)(NSDictionary *))done {
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (attr.fileSize > kMaxListBytes) {
        [CBTheme toast:@"Tệp quá lớn (tối đa 30 MB)."];
        return NO;
    }
    NSData *d = [NSData dataWithContentsOfFile:path];
    NSString *err = nil;
    NSDictionary *l = d ? [CBIPTV addListWithData:d fileName:path.lastPathComponent name:nil error:&err] : nil;
    if (!l) {
        CBLog(@"Truyền hình: không thêm được danh sách từ %@: %@", path, err ?: @"không đọc được tệp");
        [CBTheme toast:err ?: @"Không đọc được tệp."];
        return NO;
    }
    // Tệp «Mở bằng» iOS chép vào Documents/Inbox: đã chép vào app thì bỏ bản trong Inbox
    if ([path rangeOfString:@"/Documents/Inbox/"].location != NSNotFound) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    [self loaded:l done:done];
    return YES;
}

@end
