#import "CBSyncViewController.h"
#import "CBAlert.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBSync.h"
#import "CBTheme.h"

typedef NS_ENUM(NSInteger, CBSyncSec) { CBSyncMe, CBSyncPeers, CBSyncFound, CBSyncManual, CBSyncSecCount };
enum { CBAskCode = 1, CBAskAddress };

static NSString *CBPlatformIcon(NSString *p) {
    if ([p isEqualToString:@"android"]) return @"📺";
    if ([p isEqualToString:@"ios"]) return @"📱";
    if ([p isEqualToString:@"linux"]) return @"🐧";
    return @"💻";  // windows, mac… (🖥 của bản Windows không có trong bộ emoji iOS 6 → ô vuông)
}

static BOOL CBTrue(id v) {
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

@interface CBSyncViewController () <UIAlertViewDelegate, UIActionSheetDelegate>
@end

@implementation CBSyncViewController {
    NSArray *_peers;   // [{id, name, platform, host, port, last, status}]
    NSArray *_found;   // máy trong mạng chưa ghép: [{id, name, platform, host, port}]
    NSString *_code;   // mã ghép đang mở
    NSString *_address;
    BOOL _busy, _browsing;
    NSDictionary *_target;  // máy đang ghép (chọn trong «Máy trong mạng») / đang hỏi bỏ ghép
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = @"Đồng bộ trong nhà";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorColor = [CBTheme surface2];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refresh) name:CBSyncStateChanged object:nil];
    [nc addObserver:self selector:@selector(refresh) name:CBSyncDataChanged object:nil];
    [CBCore sync:@"sync.openPairing" args:nil];
    [self refresh];
    [self browse];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [CBCore sync:@"sync.closePairing" args:nil];
}

- (void)refresh {
    id peers = [CBCore sync:@"sync.peers" args:nil];
    _peers = CBIsArr(peers) ? peers : @[];
    NSMutableSet *paired = [NSMutableSet set];
    for (id p in _peers) if (CBStr(p, @"id")) [paired addObject:CBStr(p, @"id")];
    NSMutableArray *found = [NSMutableArray array];
    id f = [CBCore sync:@"sync.found" args:nil];
    for (id x in CBIsArr(f) ? f : @[]) {
        if (CBIsDict(x) && ![paired containsObject:CBStr(x, @"id") ?: @""]) [found addObject:x];
    }
    _found = found;
    id code = [CBCore sync:@"sync.pairCode" args:nil];
    _code = CBIsStr(code) ? code : nil;
    id addr = [CBCore sync:@"sync.addressText" args:nil];
    _address = CBIsStr(addr) ? addr : @"?";
    _busy = CBTrue([CBCore sync:@"sync.busy" args:nil]);
    [self.tableView reloadData];
}

- (void)browse {
    if (_browsing) return;
    _browsing = YES;
    [self.tableView reloadData];
    long long t0 = CBNowMs();
    [CBCore call:@"sync.browse" args:nil done:^(id ok, NSString *err) {
        self->_browsing = NO;
        CBLog(@"Đồng bộ: tìm máy trong mạng → %lu máy sau %lld ms%@", (unsigned long)(CBIsArr(ok) ? [ok count] : 0), CBNowMs() - t0,
              err ? [@" — LỖI " stringByAppendingString:err] : @"");
        [self refresh];
    }];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CBSyncSecCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CBSyncMe: return _code ? 2 : 1;
        // từng máy (hoặc «Chưa ghép»), «Đồng bộ ngay» (khi đã ghép), «Tự đồng bộ»
        case CBSyncPeers: return (_peers.count ? (NSInteger)_peers.count + 1 : 1) + 1;
        case CBSyncFound: return (NSInteger)_found.count + 1;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Máy này", @"Máy đã ghép", @"Máy trong mạng", @"Ghép bằng địa chỉ máy kia"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case CBSyncMe:
            return @"Máy này, tivi (Côn Bằng TV 2.2+), máy tính Windows và iPad / iPhone cùng mạng Wi-Fi đồng bộ với nhau: Xem tiếp / "
                   @"lịch sử, chỗ đang xem từng tập, phim theo dõi, người xem và danh sách trang phim. Xoá ở máy này thì máy kia cũng xoá.\n\n"
                   @"Ghép: chọn máy ở «Máy trong mạng» rồi gõ mã 4 số đang hiện trên màn Đồng bộ của máy đó. Làm ngược lại cũng được: "
                   @"trên máy kia chọn máy này rồi nhập mã ở trên (giữ màn này mở). Mã đổi sau mỗi lần ghép.";
        case CBSyncPeers:
            return @"Tự đồng bộ: lúc mở / quay lại app, thoát phim, theo dõi / bỏ theo dõi, xoá lịch sử, và 3 phút một lần khi app "
                   @"đang mở (trừ lúc đang xem phim). iOS dừng app khi ra màn hình chính nên máy kia chỉ gửi sang được lúc app đang mở.";
        case CBSyncFound:
            return _found.count ? nil : @"Máy kia phải đang mở Côn Bằng TV; khác lớp mạng thì nhập địa chỉ ở dưới.";
        default:
            return @"Nhập địa chỉ IP của tivi / máy tính (hiện trên màn Đồng bộ của máy đó) và mã ghép 4 số đang hiện ở máy đó.";
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == CBSyncMe) return ip.row == 1 ? 64 : 58;
    if (ip.section == CBSyncPeers && ip.row < (NSInteger)_peers.count) return 58;
    if (ip.section == CBSyncFound && ip.row < (NSInteger)_found.count) return 58;
    return 46;
}

- (UITableViewCell *)cell:(UITableView *)tv text:(NSString *)text detail:(NSString *)detail subtitle:(BOOL)sub {
    NSString *rid = sub ? @"s" : @"v";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:sub ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:rid];
        c.backgroundColor = [CBTheme surface];
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.detailTextLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.adjustsFontSizeToFitWidth = YES;
        c.textLabel.minimumScaleFactor = 0.75;
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [CBTheme surface2];
        c.selectedBackgroundView = sel;
    }
    c.textLabel.text = text;
    c.textLabel.textColor = [CBTheme text];
    c.textLabel.font = [CBTheme font:16];
    c.detailTextLabel.text = detail;
    c.detailTextLabel.textColor = [CBTheme dim];
    c.detailTextLabel.font = [CBTheme font:sub ? 13 : 16];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    switch (ip.section) {
        case CBSyncMe: {
            if (ip.row == 0) {
                UITableViewCell *c = [self cell:tv text:[UIDevice currentDevice].name detail:[@"địa chỉ: " stringByAppendingString:_address]
                                       subtitle:YES];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
                return c;
            }
            UITableViewCell *c = [self cell:tv text:@"Mã ghép" detail:_code subtitle:NO];
            c.detailTextLabel.font = [CBTheme bold:30];
            c.detailTextLabel.textColor = [CBTheme focus];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        case CBSyncPeers: {
            NSInteger n = (NSInteger)_peers.count;
            if (n == 0 && ip.row == 0) {
                UITableViewCell *c = [self cell:tv text:@"Chưa ghép máy nào." detail:nil subtitle:NO];
                c.textLabel.textColor = [CBTheme dim];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
                return c;
            }
            if (ip.row < n) {
                NSDictionary *p = _peers[ip.row];
                double last = CBNum(p, @"last", 0);
                NSString *when = @"chưa";
                if (last > 0) {
                    NSDateFormatter *f = [[NSDateFormatter alloc] init];
                    f.dateFormat = @"HH:mm dd/MM";
                    when = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:last / 1000.0]];
                }
                NSString *status = CBStr(p, @"status");
                NSString *detail = [NSString stringWithFormat:@"%@lần cuối: %@ — chạm để bỏ ghép",
                                                              status.length ? [status stringByAppendingString:@" · "] : @"", when];
                return [self cell:tv text:[NSString stringWithFormat:@"%@  %@", CBPlatformIcon(CBStr(p, @"platform")), CBStr(p, @"name") ?: @"?"]
                           detail:detail subtitle:YES];
            }
            if (n > 0 && ip.row == n) {
                UITableViewCell *c = [self cell:tv text:_busy ? @"Đang đồng bộ…" : @"⇄  Đồng bộ ngay" detail:nil subtitle:NO];
                c.textLabel.textColor = [CBTheme brand];
                return c;
            }
            UITableViewCell *c = [self cell:tv text:@"Tự đồng bộ" detail:nil subtitle:NO];
            UISwitch *sw = [[UISwitch alloc] init];
            id v = [CBPrefs get:@"sync_auto"];
            sw.on = ![v respondsToSelector:@selector(boolValue)] || [v boolValue];  // lõi: chưa đặt = bật
            [sw addTarget:self action:@selector(autoSwitched:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        case CBSyncFound: {
            if (ip.row < (NSInteger)_found.count) {
                NSDictionary *f = _found[ip.row];
                UITableViewCell *c = [self cell:tv text:[NSString stringWithFormat:@"%@  Ghép với %@", CBPlatformIcon(CBStr(f, @"platform")),
                                                                                   CBStr(f, @"name") ?: @"?"]
                                         detail:CBStr(f, @"host") subtitle:YES];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            UITableViewCell *c = [self cell:tv text:_browsing ? @"Đang tìm…" : @"↻  Tìm lại" detail:nil subtitle:NO];
            c.textLabel.textColor = [CBTheme brand];
            return c;
        }
        default: {
            UITableViewCell *c = [self cell:tv text:@"Nhập địa chỉ và mã ghép…" detail:nil subtitle:NO];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
    }
}

- (void)autoSwitched:(UISwitch *)sw {
    [CBPrefs set:@"sync_auto" value:@(sw.on)];
    CBLog(@"Tự đồng bộ: %@", sw.on ? @"bật" : @"tắt");
}

#pragma mark - Thao tác

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSInteger n = (NSInteger)_peers.count;
    if (ip.section == CBSyncPeers && ip.row < n) {
        _target = _peers[ip.row];
        NSString *title = [NSString stringWithFormat:@"Bỏ ghép với %@? Hai máy thôi đồng bộ (dữ liệu đã có vẫn giữ).", CBStr(_target, @"name")];
        UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"Huỷ"
                                         destructiveButtonTitle:@"Bỏ ghép" otherButtonTitles:nil];
        [s showInView:self.view];
    } else if (ip.section == CBSyncPeers && n > 0 && ip.row == n) {
        if (_busy) return;
        CBLog(@"Đồng bộ ngay");
        _busy = YES;
        [tv reloadData];
        [CBCore call:@"sync.all" args:@{@"manual": @YES} done:^(id ok, NSString *err) { [self refresh]; }];
    } else if (ip.section == CBSyncFound && ip.row < (NSInteger)_found.count) {
        _target = _found[ip.row];
        UIAlertView *a = [[CBAlert alloc] initWithTitle:[NSString stringWithFormat:@"Ghép với %@", CBStr(_target, @"name")]
                                                    message:@"Nhập mã ghép 4 số đang hiện trên màn Đồng bộ của máy đó." delegate:self
                                          cancelButtonTitle:@"Huỷ" otherButtonTitles:@"Ghép", nil];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        a.tag = CBAskCode;
        [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
        [a textFieldAtIndex:0].placeholder = @"Mã 4 số";
        [a show];
    } else if (ip.section == CBSyncFound) {
        [self browse];
    } else if (ip.section == CBSyncManual) {
        UIAlertView *a = [[CBAlert alloc] initWithTitle:@"Ghép bằng địa chỉ"
                                                    message:@"Địa chỉ IP của máy kia và mã ghép 4 số đang hiện ở máy đó."
                                                   delegate:self cancelButtonTitle:@"Huỷ" otherButtonTitles:@"Ghép", nil];
        a.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
        a.tag = CBAskAddress;
        UITextField *ipField = [a textFieldAtIndex:0], *codeField = [a textFieldAtIndex:1];
        ipField.placeholder = @"Địa chỉ IP (vd 192.168.1.20)";
        ipField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        codeField.placeholder = @"Mã 4 số";
        codeField.secureTextEntry = NO;
        codeField.keyboardType = UIKeyboardTypeNumberPad;
        [a show];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index != sheet.destructiveButtonIndex || !_target) return;
    CBLog(@"Bỏ ghép với %@", CBStr(_target, @"name"));
    [CBCore sync:@"sync.unpair" args:@{@"id": CBStr(_target, @"id") ?: @""}];
    _target = nil;
    [self refresh];
}

- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)index {
    if (index == a.cancelButtonIndex) return;
    if (a.tag == CBAskCode && _target) {
        NSString *code = [[a textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self pairHost:CBStr(_target, @"host") port:(NSInteger)CBNum(_target, @"port", 8791) code:code];
    } else if (a.tag == CBAskAddress) {
        id hp = [CBCore sync:@"sync.parseAddress" args:@{@"input": [a textFieldAtIndex:0].text ?: @""}];
        if (!CBIsDict(hp)) {
            [CBTheme toast:@"Nhập địa chỉ IP của máy kia."];
            return;
        }
        NSString *code = [[a textFieldAtIndex:1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self pairHost:CBStr(hp, @"host") port:(NSInteger)CBNum(hp, @"port", 8791) code:code];
    }
}

/// Ghép (mã 4 số đang hiện ở máy kia). Gỡ lỗi: lệnh «syncpair <địa chỉ> <mã>».
- (void)pairHost:(NSString *)host port:(NSInteger)port code:(NSString *)code {
    NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (code.length != 4 || [code rangeOfCharacterFromSet:nonDigit].location != NSNotFound) {
        [CBTheme toast:@"Mã ghép gồm 4 chữ số."];
        return;
    }
    if (!host.length) return;
    [CBTheme toast:[NSString stringWithFormat:@"Đang ghép với %@…", host]];
    CBLog(@"Đồng bộ: ghép với %@:%ld", host, (long)port);
    long long t0 = CBNowMs();
    [CBCore call:@"sync.pair" args:@{@"host": host, @"port": @(port), @"code": code} done:^(id ok, NSString *err) {
        NSString *msg = CBIsStr(ok) ? ok : err;
        CBLog(@"Đồng bộ: ghép %@ → %@ sau %lld ms", host, msg ?: @"được", CBNowMs() - t0);
        [CBTheme toast:msg ?: @"Đã ghép và đồng bộ xong."];
        [self refresh];
    }];
}

@end
