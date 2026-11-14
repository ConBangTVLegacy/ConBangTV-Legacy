#import "TestsViewController.h"
#import "PlayerViewController.h"
#import "CBFetch.h"
#import "CBLog.h"
#import "CBCore.h"

// API gọi qua HTTP để tách riêng phần kiểm TLS (máy chủ trả lời cả HTTP lẫn HTTPS — đã đo 14/11/2026)
static NSString *const kApi = @"http://phimapi.com";
// Ảnh phim trên phimimg.com: chứng chỉ Let's Encrypt (ECDSA)
static NSString *const kLeImage = @"https://phimimg.com/upload/vod/20240103-1/af2ae10bcb72617994f00dce440205dc.jpg";
// CDN video của KKPhim: chứng chỉ Let's Encrypt (RSA). Chỉ cần bắt tay TLS xong — mã HTTP nào cũng tính là qua.
static NSString *const kLeCdn = @"https://a.kvp726.com/20261113/nQPFkMnJ/index.m3u8";

typedef NS_ENUM(NSInteger, CBRow) {
    CBRowHttpApi,
    CBRowHttpsApi,
    CBRowLeSystem,
    CBRowLeBundled,
    CBRowCdnBundled,
    CBRowGithub,
    CBRowPlayHttp,
    CBRowPlayHttps,
    CBRowPlayCustom,
    CBRowCount
};

@interface TestsViewController () <UIAlertViewDelegate>
@end

@implementation TestsViewController {
    NSArray *_titles;
    NSMutableArray *_results;
    NSString *_lastCustomURL;
    BOOL _appeared;
    NSInteger _pendingNet;       // số bài kiểm mạng đang chạy (chế độ tự chạy chờ hết rồi ghi tổng kết)
    NSTimeInterval _autoPlaySecs; // > 0: trình phát mở từ chế độ tự chạy, tự đóng sau chừng ấy giây
    BOOL _viaCore;               // phát qua cổng phát nội bộ của lõi Rust (bỏ quảng cáo) thay vì đưa thẳng link cho AVPlayer
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"CBTV iOS 6 — thử";
        _titles = @[
            @"HTTP · phimapi.com (danh sách phim)",
            @"HTTPS · phimapi.com (gốc GlobalSign)",
            @"HTTPS · ảnh phimimg.com (Let's Encrypt, kho gốc iOS)",
            @"HTTPS · ảnh phimimg.com (Let's Encrypt, gốc đóng kèm)",
            @"HTTPS · CDN video a.kvp726.com (gốc đóng kèm)",
            @"HTTPS · api.github.com (USERTrust ECC)",
            @"▶ Phát tập KKPhim mới · HTTP",
            @"▶ Phát tập KKPhim mới · HTTPS (kho gốc iOS)",
            @"▶ Phát địa chỉ tự nhập…",
        ];
        _results = [NSMutableArray array];
        for (NSUInteger i = 0; i < _titles.count; i++) [_results addObject:@"Chạm để chạy"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Chạy hết" style:UIBarButtonItemStyleBordered target:self action:@selector(runAll)];
}

#pragma mark - Tự chạy

/// Lệnh tự chạy ghi qua SSH vào Documents/ConBangLegacy-autorun.txt (đọc xong thì xoá — mở tay lần sau không chạy lại):
///   net                    chạy hết bài kiểm mạng
///   play-http <giây>       phát tập KKPhim mới qua HTTP, tự tua giữa chừng, tự đóng
///   play-https <giây>      như trên nhưng qua HTTPS (kho gốc iOS)
///   play-url <giây> <url>  phát địa chỉ cho sẵn
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_appeared) return;
    _appeared = YES;
    NSString *path = [[CBLogPath() stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"ConBangLegacy-autorun.txt"];
    NSString *cmd = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!cmd) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CBLog(@"=== Tự chạy: %@", cmd);
    // Đang tự chạy thì không cho máy tự khoá (máy khoá → app vào nền → đo sai)
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSArray *parts = [cmd componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *verb = parts.count ? parts[0] : @"";
    NSTimeInterval secs = parts.count > 1 ? [parts[1] doubleValue] : 60;
    if (secs <= 0) secs = 60;
    if ([verb isEqualToString:@"net"]) {
        [self runAll];
    } else if ([verb isEqualToString:@"core"]) {
        [self runCore];
    } else if ([verb isEqualToString:@"coreplay"]) {
        _autoPlaySecs = secs;
        _viaCore = [CBCore start];
        [self playLatest:CBRowPlayHttps https:YES];
    } else if ([verb isEqualToString:@"speed"]) {
        [self runSpeed];
    } else if ([verb isEqualToString:@"play-http"] || [verb isEqualToString:@"play-https"]) {
        _autoPlaySecs = secs;
        [self playLatest:[verb isEqualToString:@"play-http"] ? CBRowPlayHttp : CBRowPlayHttps https:[verb isEqualToString:@"play-https"]];
    } else if ([verb isEqualToString:@"play-url"] && parts.count > 2) {
        _autoPlaySecs = secs;
        [self play:[NSURL URLWithString:parts[2]] title:parts[2]];
    } else {
        CBLog(@"Lệnh tự chạy không hiểu: %@", cmd);
    }
}

/// Bước 3: lõi Rust chung (linux/core) — phiên bản, rồi tải lần lượt qua mạng của lõi (DNS mã hoá, rustls, gốc Mozilla đóng kèm).
- (void)runCore {
    if (![CBCore start]) return;
    CBLog(@"[lõi] app.version → %@", [CBCore callSync:@"app.version" args:nil]);
    [self coreGet:@[
        @"http://phimapi.com/danh-sach/phim-moi-cap-nhat?page=1",
        @"https://phimapi.com/danh-sach/phim-moi-cap-nhat?page=1",
        kLeImage,
        kLeCdn,
        @"https://api.github.com/",
    ] index:0];
}

- (void)coreGet:(NSArray *)urls index:(NSUInteger)i {
    if (i >= urls.count) {
        CBLog(@"=== [lõi] xong");
        return;
    }
    NSDate *t = [NSDate date];
    [CBCore call:@"http.get" args:@{@"url": urls[i]} part:nil done:^(id ok, NSString *err) {
        NSString *res = err ? [@"LỖI " stringByAppendingString:err]
                            : [NSString stringWithFormat:@"OK — HTTP %@, %lu ký tự", ok[@"code"], (unsigned long)[ok[@"text"] length]];
        CBLog(@"[lõi] http.get %@ → %@ (%.2f s)", urls[i], res, -[t timeIntervalSinceNow]);
        [self coreGet:urls index:i + 1];
    }];
}

/// Đo tốc độ tải cùng một đoạn video .ts của CDN KKPhim: NSURLConnection rồi Rust, HTTP rồi HTTPS — chạy lần lượt.
- (void)runSpeed {
    NSString *path = @"a.kvp726.com/20261103/Soe8JLzp/3500kb/hls/1FqLcoZy.ts";
    NSArray *steps = @[@[@"objc", @"http://"], @[@"objc", @"https://"], @[@"rust", @"http://"], @[@"rust", @"https://"],
                       @[@"rust", @"https://"], @[@"objc", @"http://"]];
    [CBCore start];
    CBLog(@"=== Đo tốc độ: %@", path);
    [self runSpeedStep:0 steps:steps path:path];
}

- (void)runSpeedStep:(NSUInteger)i steps:(NSArray *)steps path:(NSString *)path {
    if (i >= steps.count) {
        CBLog(@"=== Đo tốc độ xong");
        return;
    }
    NSString *kind = steps[i][0];
    NSString *url = [steps[i][1] stringByAppendingString:path];
    if ([kind isEqualToString:@"objc"]) {
        NSArray *anchors = [url hasPrefix:@"https"] ? [CBFetch bundledAnchors] : nil;
        [CBFetch get:url anchors:anchors done:^(NSData *data, NSHTTPURLResponse *resp, NSError *err, NSTimeInterval secs) {
            double mb = data.length / 1048576.0;
            CBLog(@"[tốc độ] NSURLConnection %@ → %@", url,
                  err ? err.localizedDescription
                      : [NSString stringWithFormat:@"HTTP %ld, %.2f MB trong %.2f s = %.2f MB/s", (long)resp.statusCode, mb,
                                                   secs, mb / secs]);
            [self runSpeedStep:i + 1 steps:steps path:path];
        }];
        return;
    }
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cbtv-speed.ts"];
    NSDate *t = [NSDate date];
    [CBCore call:@"http.download" args:@{@"url": url, @"path": file} part:nil done:^(id ok, NSString *err) {
        NSTimeInterval secs = -[t timeIntervalSinceNow];
        double mb = [[[NSFileManager defaultManager] attributesOfItemAtPath:file error:NULL] fileSize] / 1048576.0;
        CBLog(@"[tốc độ] lõi Rust %@ → %@", url,
              err ?: [NSString stringWithFormat:@"%.2f MB trong %.2f s = %.2f MB/s", mb, secs, mb / secs]);
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
        [self runSpeedStep:i + 1 steps:steps path:path];
    }];
}

- (void)netTestFinished {
    if (--_pendingNet > 0) return;
    NSMutableString *summary = [NSMutableString stringWithString:@"=== Kết quả kiểm mạng:"];
    for (NSInteger r = CBRowHttpApi; r <= CBRowGithub; r++) [summary appendFormat:@"\n  %@ → %@", _titles[r], _results[r]];
    CBLog(@"%@", summary);
}

#pragma mark - Bảng

- (NSInteger)rowAt:(NSIndexPath *)ip {
    return ip.section == 0 ? ip.row : CBRowPlayHttp + ip.row;
}

- (NSIndexPath *)indexPathOf:(NSInteger)row {
    return row < CBRowPlayHttp ? [NSIndexPath indexPathForRow:row inSection:0]
                               : [NSIndexPath indexPathForRow:row - CBRowPlayHttp inSection:1];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return CBRowPlayHttp;
    if (section == 1) return CBRowCount - CBRowPlayHttp;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Mạng / chứng chỉ", @"Trình phát (AVPlayer)", @"Máy"][section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 66;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.numberOfLines = 2;
    }
    if (ip.section == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (ip.row == 0) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@ · iOS %@", CBDeviceModel(), [UIDevice currentDevice].systemVersion];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"RAM %.0f MB", [NSProcessInfo processInfo].physicalMemory / 1048576.0];
        } else if (ip.row == 1) {
            cell.textLabel.text = @"App đang dùng";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f MB", CBResidentMB()];
        } else {
            cell.textLabel.text = @"Tệp log";
            cell.detailTextLabel.text = CBLogPath();
        }
        return cell;
    }
    NSInteger row = [self rowAt:ip];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.text = _titles[row];
    cell.detailTextLabel.text = _results[row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 2) {
        [tableView reloadData];
        return;
    }
    [self run:[self rowAt:ip]];
}

- (void)setResult:(NSString *)text row:(NSInteger)row {
    _results[row] = text;
    [self.tableView reloadRowsAtIndexPaths:@[[self indexPathOf:row]] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Bài kiểm

- (void)runAll {
    CBLog(@"--- Chạy hết bài kiểm mạng");
    for (NSInteger r = CBRowHttpApi; r <= CBRowGithub; r++) [self run:r];
}

- (void)run:(NSInteger)row {
    switch (row) {
        case CBRowHttpApi:
            [self fetch:row url:[kApi stringByAppendingString:@"/danh-sach/phim-moi-cap-nhat?page=1"] anchors:nil];
            break;
        case CBRowHttpsApi:
            [self fetch:row url:@"https://phimapi.com/danh-sach/phim-moi-cap-nhat?page=1" anchors:nil];
            break;
        case CBRowLeSystem:
            [self fetch:row url:kLeImage anchors:nil];
            break;
        case CBRowLeBundled:
            [self fetch:row url:kLeImage anchors:[CBFetch bundledAnchors]];
            break;
        case CBRowCdnBundled:
            [self fetch:row url:kLeCdn anchors:[CBFetch bundledAnchors]];
            break;
        case CBRowGithub:
            [self fetch:row url:@"https://api.github.com/" anchors:nil];
            break;
        case CBRowPlayHttp:
            [self playLatest:row https:NO];
            break;
        case CBRowPlayHttps:
            [self playLatest:row https:YES];
            break;
        case CBRowPlayCustom:
            [self askURL];
            break;
    }
}

- (void)fetch:(NSInteger)row url:(NSString *)url anchors:(NSArray *)anchors {
    [self setResult:@"Đang chạy…" row:row];
    CBLog(@"Kiểm [%@] %@", anchors ? @"gốc đóng kèm" : @"kho gốc iOS", url);
    _pendingNet++;
    [CBFetch get:url anchors:anchors done:^(NSData *data, NSHTTPURLResponse *resp, NSError *err, NSTimeInterval secs) {
        NSString *text = err
            ? [NSString stringWithFormat:@"LỖI %ld: %@ (%.1f s)", (long)err.code, err.localizedDescription, secs]
            : [NSString stringWithFormat:@"OK — HTTP %ld, %lu byte, %.1f s", (long)resp.statusCode, (unsigned long)data.length, secs];
        CBLog(@"  %@ → %@", url, text);
        [self setResult:text row:row];
        [self netTestFinished];
    }];
}

#pragma mark - Phát

/// Lấy tập đầu tiên có link m3u8 của một trong 5 phim mới cập nhật trên KKPhim (API công khai phimapi.com)
- (void)playLatest:(NSInteger)row https:(BOOL)https {
    [self setResult:@"Đang tìm tập mới trên KKPhim…" row:row];
    [CBFetch get:[kApi stringByAppendingString:@"/danh-sach/phim-moi-cap-nhat?page=1"] anchors:nil
            done:^(NSData *data, NSHTTPURLResponse *resp, NSError *err, NSTimeInterval secs) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSArray *items = [json isKindOfClass:[NSDictionary class]] ? json[@"items"] : nil;
        NSMutableArray *slugs = [NSMutableArray array];
        if ([items isKindOfClass:[NSArray class]]) {
            for (id item in items) {
                id slug = [item isKindOfClass:[NSDictionary class]] ? item[@"slug"] : nil;
                if ([slug isKindOfClass:[NSString class]]) [slugs addObject:slug];
                if (slugs.count >= 5) break;
            }
        }
        if (!slugs.count) {
            [self setResult:[NSString stringWithFormat:@"LỖI đọc danh sách: %@", err.localizedDescription ?: @"không có phim"] row:row];
            return;
        }
        [self tryFilms:slugs index:0 row:row https:https];
    }];
}

- (void)tryFilms:(NSArray *)slugs index:(NSUInteger)i row:(NSInteger)row https:(BOOL)https {
    if (i >= slugs.count) {
        [self setResult:@"LỖI: không phim nào có link m3u8" row:row];
        return;
    }
    NSString *url = [NSString stringWithFormat:@"%@/phim/%@", kApi, slugs[i]];
    [CBFetch get:url anchors:nil done:^(NSData *data, NSHTTPURLResponse *resp, NSError *err, NSTimeInterval secs) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *m3u8 = nil, *title = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *movie = [json[@"movie"] isKindOfClass:[NSDictionary class]] ? json[@"movie"] : nil;
            NSArray *servers = [json[@"episodes"] isKindOfClass:[NSArray class]] ? json[@"episodes"] : nil;
            NSDictionary *server = servers.count && [servers[0] isKindOfClass:[NSDictionary class]] ? servers[0] : nil;
            NSArray *eps = [server[@"server_data"] isKindOfClass:[NSArray class]] ? server[@"server_data"] : nil;
            for (id ep in eps) {
                if (![ep isKindOfClass:[NSDictionary class]]) continue;
                id link = ep[@"link_m3u8"];
                if ([link isKindOfClass:[NSString class]] && [link length]) {
                    m3u8 = link;
                    title = [NSString stringWithFormat:@"%@ — %@", movie[@"name"] ?: slugs[i], ep[@"name"] ?: @"?"];
                    break;
                }
            }
        }
        if (!m3u8) {
            [self tryFilms:slugs index:i + 1 row:row https:https];
            return;
        }
        if (!https && [m3u8 hasPrefix:@"https://"]) {
            m3u8 = [@"http://" stringByAppendingString:[m3u8 substringFromIndex:8]];
        }
        if (self->_viaCore) {
            // Cổng phát nội bộ của lõi: bỏ khối quảng cáo chèn giữa phim, tải qua mạng + TLS của lõi
            self->_viaCore = NO;
            NSDictionary *r = [CBCore callSync:@"media.open" args:@{@"src": m3u8, @"hls": @YES}];
            NSString *local = [r[@"ok"] isKindOfClass:[NSDictionary class]] ? r[@"ok"][@"url"] : nil;
            CBLog(@"[lõi] media.open → %@", local ?: r);
            if (local) m3u8 = local;
        }
        [self setResult:[NSString stringWithFormat:@"Phát: %@", title] row:row];
        CBLog(@"Phát %@: %@", title, m3u8);
        [self play:[NSURL URLWithString:m3u8] title:title];
    }];
}

- (void)play:(NSURL *)url title:(NSString *)title {
    if (!url) {
        CBLog(@"Địa chỉ phát không hợp lệ: %@", title);
        return;
    }
    PlayerViewController *player = [[PlayerViewController alloc] initWithURL:url title:title];
    player.autoCloseAfter = _autoPlaySecs;
    _autoPlaySecs = 0;
    [self presentViewController:player animated:YES completion:nil];
}

- (void)askURL {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Địa chỉ video"
                                                    message:@"m3u8 / mp4 (http hoặc https)"
                                                   delegate:self
                                          cancelButtonTitle:@"Huỷ"
                                          otherButtonTitles:@"Phát", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.keyboardType = UIKeyboardTypeURL;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.text = _lastCustomURL ?: @"http://";
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *text = [[alertView textFieldAtIndex:0].text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _lastCustomURL = text;
    [self play:[NSURL URLWithString:text] title:text];
}

@end
