#import "CBProxyViewController.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBTheme.h"

typedef NS_ENUM(NSInteger, CBProxySec) { CBProxyMain, CBProxyServer, CBProxyOptions, CBProxyTest, CBProxySecCount };

/// Kiểu mã hoá Shadowsocks lõi hỗ trợ (shadowsocks.rs — SsMethod::ALL)
static NSArray *CBSsMethods(void) {
    return @[@"2022-blake3-aes-256-gcm", @"2022-blake3-aes-128-gcm", @"2022-blake3-chacha20-poly1305", @"aes-256-gcm", @"aes-128-gcm",
             @"chacha20-ietf-poly1305"];
}

static NSString *CBStrPref(NSString *k) {
    id v = [CBPrefs get:k];
    return CBIsStr(v) ? v : @"";
}

static NSInteger CBIntPref(NSString *k, NSInteger def) {
    id v = [CBPrefs get:k];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
}

static BOOL CBBoolPref(NSString *k, BOOL def) {
    id v = [CBPrefs get:k];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}

static NSString *CBSecret(NSString *name) {
    id v = [CBCore sync:@"prefs.secret" args:@{@"name": name}];
    return CBIsStr(v) ? v : @"";
}

static void CBSetSecret(NSString *name, NSString *value) {
    [CBCore sync:@"prefs.setSecret" args:@{@"name": name, @"value": value ?: @""}];
}

@interface CBProxyViewController () <UIActionSheetDelegate>
@end

@implementation CBProxyViewController {
    NSString *_result;  // kết quả «Thử kết nối»
    BOOL _testing;
}

+ (NSString *)summary {
    if (!CBBoolPref(@"proxy_on", NO)) return @"Tắt";
    BOOL ss = [CBStrPref(@"proxy_kind") isEqualToString:@"ss"];
    NSString *host = CBStrPref(ss ? @"ss_host" : @"proxy_host");
    if (!host.length) return @"Chưa nhập máy chủ";
    NSInteger port = ss ? CBIntPref(@"ss_port", 0) : CBIntPref(@"proxy_port", 1080);
    return [NSString stringWithFormat:@"%@ %@:%ld", ss ? @"Shadowsocks" : @"SOCKS5", host, (long)port];
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = @"Proxy";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorColor = [CBTheme surface2];
}

- (BOOL)isSs {
    return [CBStrPref(@"proxy_kind") isEqualToString:@"ss"];
}

/// Lưu xong: lõi đọc lại cấu hình mạng (có hiệu lực ngay, cả cổng phát nội bộ)
- (void)changed {
    [CBCore networkSettingsChanged];
    _result = nil;
    CBLog(@"Proxy: %@", [CBProxyViewController summary]);
    [self.tableView reloadData];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CBProxySecCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CBProxyMain: return 2;                    // bật, kiểu
        case CBProxyServer: return [self isSs] ? 5 : 4;  // ss: link, máy chủ, cổng, mã hoá, khoá; socks: máy chủ, cổng, tài khoản, mật khẩu
        case CBProxyOptions: return 2;                 // DNS qua proxy, chỉ trang phim
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CBProxyServer: return [self isSs] ? @"Máy chủ Shadowsocks" : @"Máy chủ SOCKS5";
        case CBProxyOptions: return @"Tuỳ chọn";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case CBProxyMain:
            return @"Cho app đi qua proxy của bạn (vượt chặn / đổi vùng). Proxy lỗi thì app báo lỗi chứ không lặng lẽ đi thẳng. Mật khẩu / "
                   @"khoá lưu riêng trong máy (secret.json của app), không nằm trong cài đặt đồng bộ.";
        case CBProxyServer:
            return [self isSs] ? @"Dán link ss:// (3X-UI: nút Copy của người dùng) là tự điền máy chủ, cổng, mã hoá và khoá." : nil;
        case CBProxyOptions:
            return @"DNS qua proxy: gửi tên miền cho proxy phân giải (nên bật). Chỉ trang phim: chỉ trang web phim đi qua proxy, "
                   @"video / ảnh đi thẳng cho nhanh.";
        default:
            return _result;
    }
}

- (UITableViewCell *)cell:(UITableView *)tv text:(NSString *)text detail:(NSString *)detail {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        c.backgroundColor = [CBTheme surface];
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.detailTextLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.font = [CBTheme font:16];
        c.detailTextLabel.font = [CBTheme font:15];
        c.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        c.detailTextLabel.minimumScaleFactor = 0.6;
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [CBTheme surface2];
        c.selectedBackgroundView = sel;
    }
    c.textLabel.text = text;
    c.textLabel.textColor = [CBTheme text];
    c.detailTextLabel.text = detail;
    c.detailTextLabel.textColor = [CBTheme dim];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

- (UITableViewCell *)switchCell:(UITableView *)tv text:(NSString *)text on:(BOOL)on tag:(NSInteger)tag {
    UITableViewCell *c = [self cell:tv text:text detail:nil];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (NSString *)orUnset:(NSString *)s {
    return s.length ? s : @"chưa nhập";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    BOOL ss = [self isSs];
    switch (ip.section) {
        case CBProxyMain: {
            if (ip.row == 0) return [self switchCell:tv text:@"Dùng proxy" on:CBBoolPref(@"proxy_on", NO) tag:1];
            UITableViewCell *c = [self cell:tv text:@"Kiểu" detail:nil];
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"SOCKS5", @"Shadowsocks"]];
            seg.segmentedControlStyle = UISegmentedControlStyleBar;
            seg.selectedSegmentIndex = ss ? 1 : 0;
            seg.frame = CGRectMake(0, 0, 200, 30);
            [seg addTarget:self action:@selector(kindChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = seg;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        case CBProxyServer: {
            NSInteger r = ss ? ip.row : ip.row + 1;  // socks không có dòng «link»
            UITableViewCell *c;
            if (ss) {
                switch (r) {
                    case 0: c = [self cell:tv text:@"Dán link ss://…" detail:nil]; c.textLabel.textColor = [CBTheme brand]; break;
                    case 1: c = [self cell:tv text:@"Máy chủ" detail:[self orUnset:CBStrPref(@"ss_host")]]; break;
                    case 2: {
                        NSInteger p = CBIntPref(@"ss_port", 0);
                        c = [self cell:tv text:@"Cổng" detail:p > 0 ? [NSString stringWithFormat:@"%ld", (long)p] : @"chưa nhập"];
                        break;
                    }
                    case 3: c = [self cell:tv text:@"Mã hoá" detail:CBStrPref(@"ss_method").length ? CBStrPref(@"ss_method") : CBSsMethods()[0]]; break;
                    default: c = [self cell:tv text:@"Khoá / mật khẩu" detail:CBSecret(@"ss_key").length ? @"••••••" : @"chưa nhập"]; break;
                }
            } else {
                switch (r) {
                    case 1: c = [self cell:tv text:@"Máy chủ" detail:[self orUnset:CBStrPref(@"proxy_host")]]; break;
                    case 2: c = [self cell:tv text:@"Cổng" detail:[NSString stringWithFormat:@"%ld", (long)CBIntPref(@"proxy_port", 1080)]]; break;
                    case 3: c = [self cell:tv text:@"Tài khoản" detail:CBStrPref(@"proxy_user").length ? CBStrPref(@"proxy_user") : @"không"]; break;
                    default: c = [self cell:tv text:@"Mật khẩu" detail:CBSecret(@"proxy_pass").length ? @"••••••" : @"không"]; break;
                }
            }
            if (r > 0) c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        case CBProxyOptions:
            if (ip.row == 0) return [self switchCell:tv text:@"DNS qua proxy" on:CBBoolPref(@"proxy_remote_dns", YES) tag:2];
            return [self switchCell:tv text:@"Chỉ trang phim qua proxy" on:CBBoolPref(@"proxy_sites_only", NO) tag:3];
        default: {
            UITableViewCell *c = [self cell:tv text:_testing ? @"Đang kiểm tra…" : @"Kiểm tra proxy" detail:nil];  // tên như ở mục miễn trừ
            c.textLabel.textColor = [CBTheme brand];
            return c;
        }
    }
}

#pragma mark - Thao tác

- (void)switched:(UISwitch *)sw {
    NSString *key = @[@"", @"proxy_on", @"proxy_remote_dns", @"proxy_sites_only"][sw.tag];
    [CBPrefs set:key value:@(sw.on)];
    [self changed];
}

- (void)kindChanged:(UISegmentedControl *)seg {
    [CBPrefs set:@"proxy_kind" value:seg.selectedSegmentIndex == 1 ? @"ss" : @"socks5"];
    [self changed];
}

- (void)ask:(NSString *)title value:(NSString *)value secure:(BOOL)secure number:(BOOL)number done:(void (^)(NSString *text))done {
    CBAlert *a = [CBAlert title:title message:nil cancel:@"Huỷ" others:@[@"Lưu"] done:^(CBAlert *alert, NSInteger index) {
        if (index == alert.cancelButtonIndex) return;
        done([[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"");
    }];
    a.alertViewStyle = secure ? UIAlertViewStyleSecureTextInput : UIAlertViewStylePlainTextInput;
    UITextField *f = [a textFieldAtIndex:0];
    f.text = value;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.keyboardType = number ? UIKeyboardTypeNumberPad : (secure ? UIKeyboardTypeDefault : UIKeyboardTypeURL);
    [a show];
}

- (void)setPortKey:(NSString *)key text:(NSString *)text {
    NSInteger p = [text integerValue];
    if (p <= 0 || p > 65535) {
        [CBTheme toast:@"Cổng là số từ 1 tới 65535."];
        return;
    }
    [CBPrefs set:key value:@(p)];
    [self changed];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    __weak CBProxyViewController *weakSelf = self;
    if (ip.section == CBProxyServer) {
        BOOL ss = [self isSs];
        NSInteger r = ss ? ip.row : ip.row + 1;
        if (ss && r == 0) {
            [self ask:@"Dán link ss://" value:@"" secure:NO number:NO done:^(NSString *t) { [weakSelf applyLink:t]; }];
        } else if (r == 1) {
            NSString *key = ss ? @"ss_host" : @"proxy_host";
            [self ask:@"Máy chủ (IP hoặc tên miền)" value:CBStrPref(key) secure:NO number:NO done:^(NSString *t) {
                [CBPrefs set:key value:t];
                [weakSelf changed];
            }];
        } else if (r == 2) {
            NSString *key = ss ? @"ss_port" : @"proxy_port";
            NSInteger p = ss ? CBIntPref(key, 0) : CBIntPref(key, 1080);
            [self ask:@"Cổng" value:p > 0 ? [NSString stringWithFormat:@"%ld", (long)p] : @"" secure:NO number:YES done:^(NSString *t) {
                [weakSelf setPortKey:key text:t];
            }];
        } else if (ss && r == 3) {
            UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Kiểu mã hoá" delegate:self cancelButtonTitle:nil
                                                 destructiveButtonTitle:nil otherButtonTitles:nil];
            for (NSString *m in CBSsMethods()) [sheet addButtonWithTitle:m];
            sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Huỷ"];
            [sheet showInView:self.view];
        } else if (ss) {
            [self ask:@"Khoá / mật khẩu Shadowsocks" value:@"" secure:YES number:NO done:^(NSString *t) { [weakSelf setSsKey:t]; }];
        } else if (r == 3) {
            [self ask:@"Tài khoản (bỏ trống = không đăng nhập)" value:CBStrPref(@"proxy_user") secure:NO number:NO done:^(NSString *t) {
                [CBPrefs set:@"proxy_user" value:t];
                [weakSelf changed];
            }];
        } else {
            [self ask:@"Mật khẩu proxy" value:@"" secure:YES number:NO done:^(NSString *t) {
                CBSetSecret(@"proxy_pass", t);
                [weakSelf changed];
            }];
        }
    } else if (ip.section == CBProxyTest) {
        [self test];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index < 0) return;
    NSString *m = [sheet buttonTitleAtIndex:index];
    if (![CBSsMethods() containsObject:m]) return;
    [CBPrefs set:@"ss_method" value:m];
    // Đổi kiểu mã hoá thì khoá cũ có thể không còn đúng dạng (2022-… cần khoá base64 đúng độ dài)
    NSString *key = CBSecret(@"ss_key");
    if (key.length) {
        NSString *err = nil;
        [CBCore sync:@"ss.keys" args:@{@"method": m, @"password": key} error:&err];
        if (err) [CBTheme toast:[@"Khoá hiện tại không hợp kiểu mã hoá này: " stringByAppendingString:[self clean:err]]];
    }
    [self changed];
}

/// Bỏ dấu «socks|» / «ss|» lõi gắn vào câu báo lỗi
- (NSString *)clean:(NSString *)err {
    NSRange bar = [err rangeOfString:@"|"];
    return bar.location != NSNotFound && bar.location < 8 ? [err substringFromIndex:bar.location + 1] : err;
}

- (void)setSsKey:(NSString *)key {
    NSString *method = CBStrPref(@"ss_method").length ? CBStrPref(@"ss_method") : CBSsMethods()[0];
    NSString *err = nil;
    [CBCore sync:@"ss.keys" args:@{@"method": method, @"password": key} error:&err];
    if (err) {
        [CBTheme toast:[@"Khoá không hợp lệ: " stringByAppendingString:[self clean:err]]];
        return;
    }
    CBSetSecret(@"ss_key", key);
    [self changed];
}

- (void)applyLink:(NSString *)link {
    NSString *err = nil;
    id c = [CBCore sync:@"ss.parseLink" args:@{@"link": link, @"remoteDns": @(CBBoolPref(@"proxy_remote_dns", YES)),
                                               @"sitesOnly": @(CBBoolPref(@"proxy_sites_only", NO))} error:&err];
    if (!CBIsDict(c)) {
        [CBTheme toast:[@"Không đọc được link: " stringByAppendingString:[self clean:err ?: @"?"]]];
        return;
    }
    [CBPrefs set:@"ss_host" value:CBStr(c, @"host") ?: @""];
    [CBPrefs set:@"ss_port" value:@((NSInteger)CBNum(c, @"port", 0))];
    [CBPrefs set:@"ss_method" value:CBStr(c, @"method") ?: CBSsMethods()[0]];
    CBSetSecret(@"ss_key", CBStr(c, @"password") ?: @"");
    [CBTheme toast:@"Đã điền từ link ss://."];
    [self changed];
}

/// Thử kết nối theo cấu hình đã lưu (SOCKS5: mở kết nối tới trang phim qua proxy; Shadowsocks: IP ra ngoài)
- (void)test {
    if (_testing) return;
    BOOL ss = [self isSs];
    BOOL remoteDns = CBBoolPref(@"proxy_remote_dns", YES);
    NSString *target = CBHostOf([CBPrefs baseUrl]) ?: @"www.kkphim.com";
    NSString *method;
    NSDictionary *args;
    if (ss) {
        if (!CBStrPref(@"ss_host").length || CBIntPref(@"ss_port", 0) <= 0 || !CBSecret(@"ss_key").length) {
            [CBTheme toast:@"Nhập đủ máy chủ, cổng và khoá trước."];
            return;
        }
        method = @"ss.check";
        args = @{@"host": CBStrPref(@"ss_host"), @"port": @(CBIntPref(@"ss_port", 0)),
                 @"method": CBStrPref(@"ss_method").length ? CBStrPref(@"ss_method") : CBSsMethods()[0], @"password": CBSecret(@"ss_key"),
                 @"remoteDns": @(remoteDns)};
    } else {
        if (!CBStrPref(@"proxy_host").length) {
            [CBTheme toast:@"Nhập máy chủ proxy trước."];
            return;
        }
        method = @"net.testSocks";
        args = @{@"host": CBStrPref(@"proxy_host"), @"port": @(CBIntPref(@"proxy_port", 1080)), @"user": CBStrPref(@"proxy_user"),
                 @"pass": CBStrPref(@"proxy_user").length ? CBSecret(@"proxy_pass") : @"", @"remoteDns": @(remoteDns),
                 @"target": target, @"targetPort": @443};
    }
    _testing = YES;
    _result = ss ? @"Đang thử Shadowsocks…" : [NSString stringWithFormat:@"Đang thử qua proxy tới %@…", target];
    [self.tableView reloadData];
    [CBCore call:method args:args done:^(id ok, NSString *err) {
        self->_testing = NO;
        if (err) {
            self->_result = [NSString stringWithFormat:@"✗ %@: %@", ss ? @"Lỗi Shadowsocks" : @"Lỗi proxy", [self clean:err]];
        } else if (ss) {
            self->_result = [NSString stringWithFormat:@"✓ Shadowsocks chạy — IP ra ngoài: %@", CBIsStr(ok) ? ok : @"?"];
        } else {
            self->_result = [NSString stringWithFormat:@"✓ Kết nối được qua proxy tới %@ (%@ ms).", target, ok];
        }
        CBLog(@"Thử proxy: %@", self->_result);
        [self.tableView reloadData];
    }];
}

@end
