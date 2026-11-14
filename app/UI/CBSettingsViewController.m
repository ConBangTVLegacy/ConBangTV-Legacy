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
#import "CBSyncViewController.h"
#import "CBTheme.h"

typedef NS_ENUM(NSInteger, CBSection) { CBSecProfile, CBSecSites, CBSecPlayer, CBSecNet, CBSecData, CBSecAbout, CBSecCount };
typedef NS_ENUM(NSInteger, CBSettingsAlert) { CBAlertAdd = 1, CBAlertRename, CBAlertPin, CBAlertDelete, CBAlertClear };

@interface CBSettingsViewController () <UIAlertViewDelegate>
@end

@implementation CBSettingsViewController {
    NSArray *_sites;
    NSMutableDictionary *_siteNames;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Cài đặt";
        _siteNames = [NSMutableDictionary dictionary];
    }
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
    _sites = [CBPrefs sites];
    [self.tableView reloadData];
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
        case CBSecSites: return 1 + _sites.count;
        case CBSecPlayer: return 3;
        case CBSecNet: return 2;
        case CBSecData: return 2;
        case CBSecAbout: return 3;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Người xem", @"Trang phim", @"Phát video", @"Mạng", @"Dữ liệu", @"Thông tin"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == CBSecSites) return @"Trang chủ tổng hợp gộp phim từ mọi trang. Tắt đi thì trang chủ là của trang đang chọn. "
                                      @"Trên iOS 6 chỉ phát được server có luồng HLS / tệp video (KKPhim, VSMOV, server KK Phim "
                                      @"của phimmois…); trình phát nhúng của trang (NguonC, streamfree…) không chạy được.";
    if (section == CBSecNet) return @"DNS mã hoá và vượt chặn giúp vào được trang bị nhà mạng chặn.";
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)view;
        h.textLabel.textColor = [CBTheme dim];
        h.textLabel.shadowColor = [UIColor clearColor];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [self tableView:tableView willDisplayHeaderView:view forSection:section];
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
                case 3: return [self cell:tv text:@"Mã PIN" detail:CBStr(p, @"pin") ? @"Đang khoá — bấm để bỏ" : @"Không khoá"];
                case 4: return [self switchCell:tv text:@"Hỏi người xem khi mở app" on:[CBPrefs askProfile] tag:1];
                case 5: {
                    UITableViewCell *c = [self cell:tv text:@"Giới hạn giờ xem"
                                             detail:[CBWatchLimit summaryFor:CBStr(p, @"id") ?: @""]];
                    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return c;
                }
                default: {
                    UITableViewCell *c = [self cell:tv text:@"Xoá người xem này…" detail:nil];
                    c.textLabel.textColor = CBRGB(0xE5533D);
                    return c;
                }
            }
        case CBSecSites: {
            if (ip.row == 0) return [self switchCell:tv text:@"Trang chủ tổng hợp" on:[CBPrefs homeMix] tag:2];
            NSString *url = _sites[ip.row - 1];
            // Tên trang đã kèm tên miền khi cần (vd «CLB Phim Xưa (sc.k-20.xyz)») — không lặp ở cột phải
            NSString *name = [self siteName:url], *host = CBHostOf(url);
            UITableViewCell *c = [self cell:tv text:name detail:(host && [name rangeOfString:host].location == NSNotFound) ? host : nil];
            c.accessoryType = [url isEqualToString:[CBPrefs baseUrl]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return c;
        }
        case CBSecPlayer:
            if (ip.row == 0) return [self switchCell:tv text:@"Tự chuyển tập" on:[CBPrefs autoNext] tag:3];
            if (ip.row == 1) {
                return [self cell:tv text:@"Bước tua (chạm đúp)" detail:[NSString stringWithFormat:@"%ld giây", (long)[CBPrefs seekStep]]];
            }
            return [self switchCell:tv text:@"Lấp đầy màn hình" on:[CBPrefs videoFill] tag:4];
        case CBSecNet:
            if (ip.row == 0) return [self switchCell:tv text:@"DNS mã hoá" on:[CBPrefs secureDns] tag:5];
            return [self switchCell:tv text:@"Vượt chặn nhà mạng" on:[CBPrefs unblock] tag:6];
        case CBSecData: {
            if (ip.row == 0) {
                id peers = [CBCore sync:@"sync.peers" args:nil];
                NSUInteger n = CBIsArr(peers) ? [peers count] : 0;
                UITableViewCell *c = [self cell:tv text:@"Đồng bộ trong nhà"
                                          detail:n ? [NSString stringWithFormat:@"%lu máy", (unsigned long)n] : @"Chưa ghép"];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            UITableViewCell *c = [self cell:tv text:@"Xoá lịch sử xem…" detail:[NSString stringWithFormat:@"%lu phim",
                                                                                (unsigned long)[CBPrefs history].count]];
            c.textLabel.textColor = CBRGB(0xE5533D);
            return c;
        }
        default: {
            if (ip.row == 0) {
                NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                NSString *core = CBIsStr([CBCore sync:@"app.version" args:nil]) ? [CBCore sync:@"app.version" args:nil] : @"?";
                UITableViewCell *c = [self cell:tv text:@"Phiên bản" detail:[NSString stringWithFormat:@"%@ (lõi %@)", v, core]];
                c.selectionStyle = UITableViewCellSelectionStyleNone;
                return c;
            }
            if (ip.row == 1) {
                UITableViewCell *c = [self cell:tv text:@"Miễn trừ trách nhiệm" detail:nil];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return c;
            }
            UITableViewCell *c = [self cell:tv text:@"Liên hệ" detail:@"t.me/tivikit"];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
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
    }
    CBLog(@"Cài đặt %ld → %d", (long)sw.tag, sw.on);
}

- (UIAlertView *)ask:(NSString *)title message:(NSString *)msg tag:(NSInteger)tag style:(UIAlertViewStyle)style ok:(NSString *)ok {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:@"Huỷ" otherButtonTitles:ok, nil];
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
                [CBPrefs setProfilePin:CBStr(p, @"id") ?: @"" pin:nil];
                [tv reloadData];
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
    } else if (ip.section == CBSecSites && ip.row > 0) {
        [CBPrefs setBaseUrl:_sites[ip.row - 1]];
        [tv reloadData];
    } else if (ip.section == CBSecPlayer && ip.row == 1) {
        NSArray *steps = @[@5, @10, @15, @30];
        NSUInteger i = [steps indexOfObject:@([CBPrefs seekStep])];
        [CBPrefs setSeekStep:[steps[i == NSNotFound ? 1 : (i + 1) % steps.count] integerValue]];
        [tv reloadData];
    } else if (ip.section == CBSecData && ip.row == 0) {
        [self.navigationController pushViewController:[[CBSyncViewController alloc] init] animated:YES];
    } else if (ip.section == CBSecData) {
        [[self ask:@"Xoá lịch sử xem?" message:@"Xoá danh sách «Xem tiếp» và chỗ đang xem của mọi tập (người xem hiện tại)."
               tag:CBAlertClear style:UIAlertViewStyleDefault ok:@"Xoá"] show];
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
                [CBPrefs setProfilePin:pid pin:pin];
            } else {
                [[[UIAlertView alloc] initWithTitle:@"Mã PIN phải là 4 chữ số" message:nil delegate:nil cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
            }
            break;
        }
        case CBAlertDelete: [CBPrefs deleteProfile:pid]; break;
        case CBAlertClear: [CBPrefs clearHistory]; break;
    }
    [self.tableView reloadData];
}

@end
