#import "CBSettingsViewController.h"
#import "CBCore.h"
#import "CBDisclaimerViewController.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBLimitsViewController.h"
#import "CBParental.h"
#import "CBProfilesViewController.h"
#import "CBProxyViewController.h"
#import "CBSyncViewController.h"
#import "CBIPTV.h"
#import "CBTVSettingsViewController.h"
#import "CBUpdate.h"
#import "CBSheet.h"
#import "CBTabHeader.h"
#import "CBGlass.h"
#import "CBTheme.h"

typedef NS_ENUM(NSInteger, CBSection) { CBSecProfile, CBSecSites, CBSecPlayer, CBSecNet, CBSecData, CBSecAbout, CBSecCount };
typedef NS_ENUM(NSInteger, CBSettingsAlert) {
    CBAlertAdd = 1, CBAlertRename, CBAlertPin, CBAlertPinConfirm, CBAlertPinRemove, CBAlertDelete, CBAlertClear, CBAlertClearImages
};

@interface CBSettingsViewController () <UIAlertViewDelegate, UIActionSheetDelegate>
@end

@implementation CBSettingsViewController {
    NSString *_pinDraft;  // mã PIN lần nhập đầu, chờ nhập lại
    NSArray *_sites;
    NSMutableDictionary *_siteNames;
    NSMutableDictionary *_checks;   // «Đo tốc độ các trang»: url → «320 ms · 24 phim» / «đang đo…» / lỗi
    NSMutableDictionary *_checkMs;  // url → ms (đo xong, có phim) — đánh dấu ★ trang nhanh nhất
    unsigned long long _imageBytes; // ảnh bìa lưu trên máy (tính ở nền khi mở màn)
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Cài đặt";
        _siteNames = [NSMutableDictionary dictionary];
        _checks = [NSMutableDictionary dictionary];
        _checkMs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [CBTheme bg];
    // Màn gốc của tab «Cài đặt»: tiêu đề lớn cuộn cùng bảng (thanh điều hướng ẩn)
    if (self.navigationController.viewControllers.firstObject == self) {
        CBTabHeader *h = [[CBTabHeader alloc] initWithTitle:self.title];
        h.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, [CBTabHeader height]);
        self.tableView.tableHeaderView = h;
    }
    self.tableView.separatorColor = [CBTheme surface2];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _sites = [CBPrefs sites];
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        unsigned long long bytes = [CBImages diskBytes];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_imageBytes = bytes;
            [self.tableView reloadData];
        });
    });
}

- (NSString *)siteName:(NSString *)url {
    NSString *name = _siteNames[url];
    if (!name) {
        id n = [CBCore sync:@"site.displayName" args:@{@"host": CBHostOf(url) ?: url}];
        name = CBIsStr(n) && [n length] ? n : (CBHostOf(url) ?: url);
        _siteNames[url] = name;
    }
    return name;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CBSecCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CBSecProfile: return [CBPrefs profiles].count > 1 ? 7 : 6;
        case CBSecSites: return 3 + _sites.count;  // tổng hợp, hồ sơ trẻ em, từng trang, «Đo tốc độ các trang»
        case CBSecPlayer: return 6;  // tự chuyển tập, bước tua, lấp đầy, xem riêng, server dự phòng KKPhim, đặt lại server
        case CBSecNet: return 3;
        case CBSecData: return 4;    // đồng bộ, xoá lịch sử, xoá ảnh, truyền hình
        case CBSecAbout: return 4;   // phiên bản, miễn trừ, liên hệ, tự kiểm tra bản mới
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Người xem", @"Trang phim", @"Phát video", @"Mạng", @"Dữ liệu", @"Thông tin"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == CBSecSites) return @"Trang chủ tổng hợp gộp phim từ mọi trang. Tắt đi thì trang chủ là của trang đang chọn. "
                                      @"Hồ sơ trẻ em: trang chủ chỉ có phim hoạt hình hợp trẻ em (thiếu nhi, gia đình, lồng tiếng; bỏ "
                                      @"kinh dị / hình sự / chiến tranh / 18+) — tắt cần mã PIN phụ huynh nếu đã đặt. "
                                      @"Trên iOS 6 chỉ phát được server có luồng HLS / tệp video (KKPhim, VSMOV, server KK Phim "
                                      @"của phimmois…); trình phát nhúng của trang (NguonC, streamfree…) không chạy được.";
    if (section == CBSecPlayer) return @"Xem riêng: không ghi lịch sử, chỗ đang xem chỉ nhớ tới khi đóng app (của người xem này). "
                                       @"Server dự phòng KKPhim: với yanhh3d, hoathinh3d, hhkungfu… app tìm cùng phim, cùng tập trên "
                                       @"KKPhim và thêm server «KKPhim…» vào danh sách server — trang hỏng vẫn xem được.";
    if (section == CBSecNet) return @"DNS mã hoá: hỏi địa chỉ trang qua DNS mã hoá thay DNS nhà mạng. Vượt chặn: trang không vào được "
                                    @"(nhà mạng chặn theo tên trang) thì bật Mức 1 — app chia nhỏ gói bắt tay HTTPS; Mức 1 mà trang vẫn "
                                    @"không trả lời thì app tự thử Mức 2 cho riêng trang đó. Không cần VPN.";
    if (section == CBSecAbout) return @"Bật «Tự kiểm tra bản mới» thì app hỏi GitHub khi mở (6 giờ một lần); chạm «Phiên bản» để kiểm tra ngay.";
    return nil;
}

/// Ô vuông màu đầu dòng (kiểu Cài đặt iOS 26) theo chữ của dòng; dòng trang phim (tên trang) = quả địa cầu
- (UIImage *)iconFor:(NSString *)text {
    static NSArray *map;
    if (!map) map = @[
        @[@"Đang xem", @"person", @0x3B82F6], @[@"Thêm người xem", @"plus", @0x2BAF85], @[@"Đổi tên", @"pencil", @0x6B7280],
        @[@"Mã PIN", @"lock", @0x3B82F6], @[@"Hỏi người xem", @"people", @0x2BAF85], @[@"Giới hạn giờ xem", @"clock", @0xF59E0B],
        @[@"Xoá người xem", @"trash", @0xDC4A35], @[@"Trang chủ tổng hợp", @"grid", @0x0891B2], @[@"Hồ sơ trẻ em", @"smile", @0xDB2777],
        @[@"Đo tốc độ", @"gauge", @0x7C3AED], @[@"Tự chuyển tập", @"next", @0xDC4A35], @[@"Bước tua", @"fwd10", @0x4F46E5],
        @[@"Lấp đầy", @"expand", @0x475569], @[@"Xem riêng", @"eyeoff", @0x6B7280], @[@"Server dự phòng", @"server", @0x2563EB],
        @[@"Đặt lại server", @"reload", @0xEA580C], @[@"DNS mã hoá", @"shield", @0x16A34A], @[@"Vượt chặn", @"globe", @0xEA580C],
        @[@"Proxy", @"server", @0x7C3AED], @[@"Đồng bộ", @"sync", @0x0D9488], @[@"Truyền hình", @"tv", @0xE11D48],
        @[@"Xoá ảnh", @"photo", @0x64748B], @[@"Xoá lịch sử", @"history", @0x64748B], @[@"Phiên bản", @"info", @0x64748B],
        @[@"Miễn trừ", @"doc", @0x64748B], @[@"Tự kiểm tra bản mới", @"download", @0x2563EB], @[@"Liên hệ", @"send", @0x0EA5E9],
    ];
    for (NSArray *m in map) {
        if ([text hasPrefix:m[0]]) return [CBGroupedTableViewController rowIcon:m[1] color:CBRGB([m[2] unsignedIntValue])];
    }
    return [CBGroupedTableViewController rowIcon:@"globe" color:CBRGB(0x0E9F8E)];
}

- (UITableViewCell *)cell:(UITableView *)tv text:(NSString *)text detail:(NSString *)detail {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        c.backgroundColor = [CBTheme surface];
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.detailTextLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.adjustsFontSizeToFitWidth = YES;  // chữ hơi dài (cạnh công tắc) co lại thay vì bị cắt «…»
        c.textLabel.minimumScaleFactor = 0.75;
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [CBTheme surface2];
        c.selectedBackgroundView = sel;
    }
    c.textLabel.text = text;
    c.textLabel.textColor = [CBTheme text];
    c.textLabel.font = [CBTheme font:16];
    c.imageView.image = [self iconFor:text];
    c.detailTextLabel.text = detail;
    c.detailTextLabel.textColor = [CBTheme dim];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

- (UITableViewCell *)switchCell:(UITableView *)tv text:(NSString *)text on:(BOOL)on tag:(NSInteger)tag {
    UITableViewCell *c = [self cell:tv text:text detail:nil];
    UISwitch *sw = (UISwitch *)[[CBSwitch alloc] init];   // công tắc kiểu iOS 26 (CBGlass)
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *p = [CBPrefs currentProfile];
    switch (ip.section) {
        case CBSecProfile:
            switch (ip.row) {
                case 0: {
                    UITableViewCell *c = [self cell:tv text:@"Đang xem" detail:CBStr(p, @"name")];
                    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return c;
                }
                case 1: return [self cell:tv text:@"Thêm người xem…" detail:nil];
                case 2: return [self cell:tv text:@"Đổi tên người này…" detail:nil];
                case 3: return [self cell:tv text:@"Mã PIN" detail:CBStr(p, @"pin") ? @"Đang khoá" : @"Không khoá"];
                case 4: return [self switchCell:tv text:@"Hỏi người xem khi mở app" on:[CBPrefs askProfile] tag:1];
                case 5: {
                    UITableViewCell *c = [self cell:tv text:@"Giới hạn giờ xem"
                                             detail:[CBWatchLimit summaryFor:CBStr(p, @"id") ?: @""]];
                    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return c;
                }
                default: {
                    UITableViewCell *c = [self cell:tv text:@"Xoá người xem này…" detail:nil];
                    c.textLabel.textColor = [CBTheme dangerText];
                    return c;
                }
            }
        case CBSecSites: {
            if (ip.row == 0) {
                // Hồ sơ trẻ em luôn dùng trang chủ tổng hợp (như bản Windows)
                UITableViewCell *c = [self switchCell:tv text:@"Trang chủ tổng hợp" on:[CBPrefs homeMix] tag:2];
                [(UISwitch *)c.accessoryView setEnabled:![CBPrefs kids]];
                return c;
            }
            if (ip.row == 1) return [self switchCell:tv text:@"Hồ sơ trẻ em" on:[CBPrefs kids] tag:7];
            if (ip.row == 2 + (NSInteger)_sites.count) {
                UITableViewCell *c = [self cell:tv text:@"Đo tốc độ các trang" detail:nil];
                c.textLabel.textColor = [CBTheme accent];
                return c;
            }
            NSString *url = _sites[ip.row - 2];
            // Tên trang đã kèm tên miền khi cần (vd «CLB Phim Xưa (sc.k-20.xyz)») — không lặp ở cột phải; đã đo thì hiện kết quả
            NSString *name = [self siteName:url], *host = CBHostOf(url);
            NSString *detail = _checks[url] ?: ((host && [name rangeOfString:host].location == NSNotFound) ? host : nil);
            UITableViewCell *c = [self cell:tv text:name detail:detail];
            c.accessoryType = [url isEqualToString:[CBPrefs baseUrl]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return c;
        }
        case CBSecPlayer:
            if (ip.row == 0) return [self switchCell:tv text:@"Tự chuyển tập" on:[CBPrefs autoNext] tag:3];
            if (ip.row == 1) {
                return [self cell:tv text:@"Bước tua (chạm đúp)" detail:[NSString stringWithFormat:@"%ld giây", (long)[CBPrefs seekStep]]];
            }
            if (ip.row == 2) return [self switchCell:tv text:@"Lấp đầy màn hình" on:[CBPrefs videoFill] tag:4];
            if (ip.row == 3) return [self switchCell:tv text:@"Xem riêng (không lưu lịch sử)" on:[CBPrefs privateMode] tag:8];
            if (ip.row == 4) return [self switchCell:tv text:@"Server dự phòng KKPhim" on:[CBPrefs kkBackup] tag:9];
            {
                NSUInteger n = [CBPrefs chosenServerCount];
                return [self cell:tv text:@"Đặt lại server đã chọn"
                           detail:n ? [NSString stringWithFormat:@"%lu trang", (unsigned long)n] : @"chưa có"];
            }
        case CBSecNet:
            if (ip.row == 0) return [self switchCell:tv text:@"DNS mã hoá" on:[CBPrefs secureDns] tag:5];
            if (ip.row == 1) {
                UITableViewCell *c = [self cell:tv text:@"Vượt chặn nhà mạng" detail:@[@"Tắt", @"Mức 1", @"Mức 2"][[CBPrefs unblockLevel]]];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            {
                UITableViewCell *c = [self cell:tv text:@"Proxy" detail:[CBProxyViewController summary]];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
        case CBSecData: {
            if (ip.row == 0) {
                id peers = [CBCore sync:@"sync.peers" args:nil];
                NSUInteger n = CBIsArr(peers) ? [peers count] : 0;
                UITableViewCell *c = [self cell:tv text:@"Đồng bộ trong nhà"
                                          detail:n ? [NSString stringWithFormat:@"%lu máy", (unsigned long)n] : @"Chưa ghép"];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            if (ip.row == 3) {
                NSUInteger n = [CBIPTV lists].count;
                UITableViewCell *c = [self cell:tv text:@"Truyền hình (IPTV)"
                                          detail:n ? [NSString stringWithFormat:@"%lu danh sách kênh", (unsigned long)n] : @"Chưa có kênh"];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            if (ip.row == 2) {
                UITableViewCell *c = [self cell:tv text:@"Xoá ảnh đã lưu…"
                                          detail:[NSString stringWithFormat:@"%.1f MB", _imageBytes / 1048576.0]];
                c.textLabel.textColor = [CBTheme dangerText];
                return c;
            }
            UITableViewCell *c = [self cell:tv text:@"Xoá lịch sử xem…" detail:[NSString stringWithFormat:@"%lu phim",
                                                                                (unsigned long)[CBPrefs history].count]];
            c.textLabel.textColor = [CBTheme dangerText];
            return c;
        }
        default: {
            if (ip.row == 0) {
                NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                NSString *core = CBIsStr([CBCore sync:@"app.version" args:nil]) ? [CBCore sync:@"app.version" args:nil] : @"?";
                UITableViewCell *c = [self cell:tv text:@"Phiên bản" detail:[NSString stringWithFormat:@"%@ (lõi %@)", v, core]];
                return c;  // chạm: kiểm tra bản mới (CBUpdate)
            }
            if (ip.row == 1) {
                UITableViewCell *c = [self cell:tv text:@"Miễn trừ trách nhiệm" detail:nil];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            if (ip.row == 3) return [self switchCell:tv text:@"Tự kiểm tra bản mới" on:[CBPrefs autoUpdate] tag:10];
            UITableViewCell *c = [self cell:tv text:@"Liên hệ" detail:@"t.me/tivikit"];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;  // chạm: mở trang Telegram
            return c;
        }
    }
}

- (void)switched:(UISwitch *)sw {
    switch (sw.tag) {
        case 1: [CBPrefs setAskProfile:sw.on]; break;
        case 2: [CBPrefs setHomeMix:sw.on]; break;
        case 3: [CBPrefs setAutoNext:sw.on]; break;
        case 4: [CBPrefs setVideoFill:sw.on]; break;
        case 5: [CBPrefs setSecureDns:sw.on]; break;
        case 6: [CBPrefs setUnblock:sw.on]; break;
        case 8: [CBPrefs setPrivateMode:sw.on]; break;
        case 9: [CBPrefs setKkBackup:sw.on]; break;
        case 10: [CBPrefs setAutoUpdate:sw.on]; break;
        case 7:
            if (sw.on) {
                [CBPrefs setKids:YES];
                [self.tableView reloadData];
            } else if (![CBPrefs hasParentPin]) {
                [CBPrefs setKids:NO];
                [self.tableView reloadData];
            } else {
                // Trẻ không tự tắt được: phải nhập mã PIN phụ huynh
                [CBParental checkParent:@"Nhập mã PIN phụ huynh để tắt hồ sơ trẻ em." done:^(BOOL ok) {
                    if (ok) [CBPrefs setKids:NO];
                    CBLog(@"Hồ sơ trẻ em: %@", [CBPrefs kids] ? @"vẫn bật" : @"tắt");
                    [self.tableView reloadData];
                }];
                return;
            }
            break;
    }
    CBLog(@"Cài đặt %ld → %d", (long)sw.tag, sw.on);
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index < 0 || index > 2) return;
    [CBPrefs setUnblockLevel:index];
    CBLog(@"Vượt chặn: mức %ld", (long)index);
    [self.tableView reloadData];
}

/// «Đo tốc độ các trang» (site.check của lõi, như nút «Đo» bản Windows): thời gian trả lời + số phim đọc được ở trang chủ
- (void)measureSites {
    [_checkMs removeAllObjects];
    __block NSUInteger left = _sites.count;
    for (NSString *url in _sites) {
        _checks[url] = @"đang đo…";
        [CBCore call:@"site.check" args:@{@"baseUrl": url} done:^(id ok, NSString *err) {
            long ms = (long)CBNum(ok, @"ms", 0), films = (long)CBNum(ok, @"films", 0);
            if (err) {
                self->_checks[url] = [@"lỗi: " stringByAppendingString:err.length > 30 ? [[err substringToIndex:30] stringByAppendingString:@"…"] : err];
            } else if (films > 0) {
                self->_checks[url] = [NSString stringWithFormat:@"%ld ms · %ld phim", ms, films];
                self->_checkMs[url] = @(ms);
            } else {
                self->_checks[url] = [NSString stringWithFormat:@"%ld ms · không thấy phim", ms];
            }
            CBLog(@"Đo %@: %@", url, self->_checks[url]);
            if (--left == 0 && self->_checkMs.count > 1) {  // xong hết: ★ trang nhanh nhất
                NSString *best = [[self->_checkMs keysSortedByValueUsingSelector:@selector(compare:)] firstObject];
                if (best) self->_checks[best] = [@"★ " stringByAppendingString:self->_checks[best]];
            }
            [self.tableView reloadData];
        }];
    }
    [self.tableView reloadData];
}

- (UIAlertView *)ask:(NSString *)title message:(NSString *)msg tag:(NSInteger)tag style:(UIAlertViewStyle)style ok:(NSString *)ok {
    UIAlertView *a = [[CBAlert alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:@"Huỷ" otherButtonTitles:ok, nil];
    a.alertViewStyle = style;
    a.tag = tag;
    return a;
}

/// Đang có giới hạn giờ xem thì thêm / xoá người xem cần mã PIN phụ huynh (như bản Windows)
- (void)parentIfLimited:(NSString *)why then:(void (^)(void))then {
    if (![CBWatchLimit anyLimits]) {
        then();
        return;
    }
    [CBParental checkParent:why done:^(BOOL ok) {
        if (ok) then();
    }];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *p = [CBPrefs currentProfile];
    if (ip.section == CBSecProfile) {
        if (ip.row == 0) {
            CBProfilesViewController *vc = [[CBProfilesViewController alloc] init];
            vc.closable = YES;
            __weak CBSettingsViewController *weakSelf = self;
            vc.onDone = ^{ [weakSelf.tableView reloadData]; };
            [self presentViewController:vc animated:YES completion:nil];
        } else if (ip.row == 1) {
            [self parentIfLimited:@"Đang có giới hạn giờ xem — nhập mã PIN phụ huynh để thêm người xem." then:^{
                [[self ask:@"Thêm người xem" message:@"Tên người xem" tag:CBAlertAdd style:UIAlertViewStylePlainTextInput ok:@"Thêm"] show];
            }];
        } else if (ip.row == 2) {
            UIAlertView *a = [self ask:@"Đổi tên" message:nil tag:CBAlertRename style:UIAlertViewStylePlainTextInput ok:@"Lưu"];
            [a textFieldAtIndex:0].text = CBStr(p, @"name");
            [a show];
        } else if (ip.row == 3) {
            if (CBStr(p, @"pin")) {
                // Bỏ khoá phải nhập đúng mã đang dùng (trẻ khỏi tự mở khoá người xem của bố mẹ)
                UIAlertView *a = [self ask:@"Bỏ mã PIN" message:@"Nhập mã PIN đang dùng của người này" tag:CBAlertPinRemove
                                     style:UIAlertViewStyleSecureTextInput ok:@"Bỏ khoá"];
                [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
                [a show];
            } else {
                UIAlertView *a = [self ask:@"Đặt mã PIN" message:@"4 chữ số — khoá cho trẻ khỏi vào nhầm người xem" tag:CBAlertPin
                                     style:UIAlertViewStyleSecureTextInput ok:@"Đặt"];
                [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
                [a show];
            }
        } else if (ip.row == 5) {
            [CBParental checkParent:@"Nhập mã PIN phụ huynh để đặt giới hạn giờ xem." done:^(BOOL ok) {
                if (ok) [self.navigationController pushViewController:[[CBLimitsViewController alloc] initWithProfile:nil] animated:YES];
            }];
        } else if (ip.row == 6) {
            [self parentIfLimited:@"Đang có giới hạn giờ xem — nhập mã PIN phụ huynh để xoá người xem." then:^{
                [[self ask:@"Xoá người xem này?" message:[NSString stringWithFormat:@"Xoá «%@» cùng lịch sử, phim theo dõi của người này.",
                                                                                     CBStr(p, @"name")]
                       tag:CBAlertDelete style:UIAlertViewStyleDefault ok:@"Xoá"] show];
            }];
        }
    } else if (ip.section == CBSecSites && ip.row == 2 + (NSInteger)_sites.count) {
        [self measureSites];
    } else if (ip.section == CBSecSites && ip.row > 1) {
        [CBPrefs setBaseUrl:_sites[ip.row - 2]];
        [tv reloadData];
    } else if (ip.section == CBSecPlayer && ip.row == 5) {
        NSUInteger n = [CBPrefs chosenServerCount];
        [CBPrefs resetChosenServers];
        [CBTheme toast:n ? [NSString stringWithFormat:@"Đã quên server đã chọn của %lu trang — lần xem sau app tự chọn lại.", (unsigned long)n]
                         : @"Chưa có server nào được nhớ."];
        [tv reloadData];
    } else if (ip.section == CBSecNet && ip.row == 1) {
        UIActionSheet *s = [[CBSheet alloc] initWithTitle:@"Vượt chặn nhà mạng" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
        NSInteger cur = [CBPrefs unblockLevel];
        NSArray *names = @[@"Tắt", @"Mức 1 — chia nhỏ gói bắt tay", @"Mức 2 — chia nhỏ hơn nữa"];
        for (NSInteger i = 0; i < 3; i++) [s addButtonWithTitle:i == cur ? [@"✓ " stringByAppendingString:names[i]] : names[i]];
        s.cancelButtonIndex = [s addButtonWithTitle:@"Huỷ"];
        [s showInView:self.view];
    } else if (ip.section == CBSecPlayer && ip.row == 1) {
        NSArray *steps = @[@5, @10, @15, @30];
        NSUInteger i = [steps indexOfObject:@([CBPrefs seekStep])];
        [CBPrefs setSeekStep:[steps[i == NSNotFound ? 1 : (i + 1) % steps.count] integerValue]];
        [tv reloadData];
    } else if (ip.section == CBSecNet && ip.row == 2) {
        [self.navigationController pushViewController:[[CBProxyViewController alloc] init] animated:YES];
    } else if (ip.section == CBSecData && ip.row == 0) {
        [self.navigationController pushViewController:[[CBSyncViewController alloc] init] animated:YES];
    } else if (ip.section == CBSecData && ip.row == 3) {
        [self.navigationController pushViewController:[[CBTVSettingsViewController alloc] init] animated:YES];
    } else if (ip.section == CBSecData && ip.row == 1) {
        [[self ask:@"Xoá lịch sử xem?" message:@"Xoá danh sách «Xem tiếp» và chỗ đang xem của mọi tập (người xem hiện tại)."
               tag:CBAlertClear style:UIAlertViewStyleDefault ok:@"Xoá"] show];
    } else if (ip.section == CBSecData && ip.row == 2) {
        [[self ask:@"Xoá ảnh đã lưu?" message:@"Xoá ảnh bìa lưu trên máy (giải phóng bộ nhớ). Ảnh sẽ tải lại khi cần."
               tag:CBAlertClearImages style:UIAlertViewStyleDefault ok:@"Xoá"] show];
    } else if (ip.section == CBSecAbout && ip.row == 2) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://t.me/tivikit"]];
    } else if (ip.section == CBSecAbout && ip.row == 0) {
        [CBUpdate checkManual];
    } else if (ip.section == CBSecAbout && ip.row == 1) {
        [self.navigationController pushViewController:[[CBDisclaimerViewController alloc] initGate:NO] animated:YES];
    }
}

- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)index {
    if (index == a.cancelButtonIndex) return;
    NSDictionary *p = [CBPrefs currentProfile];
    NSString *pid = CBStr(p, @"id") ?: @"";
    NSString *text = a.alertViewStyle == UIAlertViewStyleDefault ? nil : [a textFieldAtIndex:0].text;
    switch (a.tag) {
        case CBAlertAdd: {
            NSDictionary *np = [CBPrefs addProfile:text ?: @""];
            CBLog(@"Thêm người xem %@", CBStr(np, @"name"));
            break;
        }
        case CBAlertRename: [CBPrefs renameProfile:pid name:text ?: @""]; break;
        case CBAlertPin: {
            NSString *pin = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (pin.length == 4 && [pin rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location ==
                                       NSNotFound) {
                // Nhập lại lần nữa (gõ nhầm một lần là khoá luôn người xem bằng mã không ai biết)
                _pinDraft = pin;
                UIAlertView *again = [self ask:@"Nhập lại mã PIN" message:nil tag:CBAlertPinConfirm
                                         style:UIAlertViewStyleSecureTextInput ok:@"Đặt"];
                [again textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
                [again show];
            } else {
                [[[CBAlert alloc] initWithTitle:@"Mã PIN phải là 4 chữ số" message:nil delegate:nil cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
            }
            break;
        }
        case CBAlertPinConfirm: {
            NSString *pin = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (_pinDraft && [pin isEqualToString:_pinDraft]) {
                [CBPrefs setProfilePin:pid pin:pin];
                [CBTheme toast:@"Đã đặt mã PIN."];
            } else {
                [[[CBAlert alloc] initWithTitle:@"Hai lần nhập không khớp" message:@"Mã PIN chưa được đặt." delegate:nil
                                  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
            _pinDraft = nil;
            break;
        }
        case CBAlertPinRemove:
            if ([CBPrefs checkPin:text ?: @"" profile:p]) {
                [CBPrefs setProfilePin:pid pin:nil];
                [CBTheme toast:@"Đã bỏ mã PIN."];
            } else {
                [[[CBAlert alloc] initWithTitle:@"Sai mã PIN" message:nil delegate:nil cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
            }
            break;
        case CBAlertDelete:
            if ([CBPrefs deleteProfile:pid]) {
                // Đã chuyển sang người xem khác: người đó có khoá / còn nhiều người → hỏi «Ai đang xem?» (không vào thẳng)
                if ([CBPrefs profiles].count > 1 || CBStr([CBPrefs currentProfile], @"pin")) {
                    CBProfilesViewController *vc = [[CBProfilesViewController alloc] init];
                    __weak CBSettingsViewController *weakSelf = self;
                    vc.onDone = ^{ [weakSelf.tableView reloadData]; };
                    dispatch_async(dispatch_get_main_queue(), ^{ [self presentViewController:vc animated:YES completion:nil]; });
                }
            }
            break;
        case CBAlertClear: [CBPrefs clearHistory]; break;
        case CBAlertClearImages:
            [CBImages clearDisk];
            _imageBytes = 0;
            [CBTheme toast:@"Đã xoá ảnh đã lưu."];
            break;
    }
    [self.tableView reloadData];
}

@end
