#import "CBTVSettingsViewController.h"
#import "CBIPTV.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBTVViewController.h"
#import "CBTheme.h"

enum { CBTVSecLists = 0, CBTVSecGuide, CBTVSecPlay, CBTVSecCount };

@interface CBTVSettingsViewController () <UIActionSheetDelegate>
@end

@implementation CBTVSettingsViewController {
    NSDictionary *_sheetList;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Truyền hình";
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorColor = [CBTheme surface2];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed) name:CBIPTVChangedNotification object:nil];
}

- (void)changed {
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UITableViewCell *)cell:(UITableView *)tv text:(NSString *)text detail:(NSString *)detail {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        c.backgroundColor = [CBTheme surface];
        c.textLabel.backgroundColor = c.detailTextLabel.backgroundColor = [UIColor clearColor];
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

- (void)switched:(UISwitch *)sw {
    if (sw.tag == 1) [CBIPTV setHideBad:sw.on];
    if (sw.tag == 2) [CBIPTV setAutoSource:sw.on];
    [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CBTVSecCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CBTVSecLists: return [CBIPTV lists].count + 1;
        case CBTVSecGuide: return 2;
        default: return 3;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Danh sách kênh", @"Lịch phát sóng", @"Phát"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == CBTVSecLists) {
        return @"App không kèm sẵn kênh. Thêm danh sách M3U / M3U8 mà anh có quyền xem: dán địa chỉ, gửi tệp từ máy tính qua "
               @"Wi-Fi, hoặc chọn tệp .m3u có trên máy; app đọc nhóm, logo, đài radio và địa chỉ lịch phát sóng ghi trong danh sách. "
               @"Danh sách theo địa chỉ tự tải lại khi cũ; danh sách từ tệp thì thêm lại khi có tệp mới.";
    }
    if (section == CBTVSecGuide) {
        return @"Lịch phát sóng (EPG, dạng XMLTV — .xml hoặc .xml.gz) lấy theo địa chỉ ghi trong danh sách; danh sách không ghi "
               @"thì đặt ở đây. App chỉ giữ lịch của các kênh trong danh sách, từ hôm qua tới ngày mai.";
    }
    return @"iOS 5 / 6 chỉ giải mã H.264 tới 1920×1080: kênh H.265 (HEVC) hay khổ lớn hơn được ghi là «không phát được» sau lần "
           @"mở đầu tiên. Luồng FLV và TS liền (IPTV kiểu Xtream) app tự đổi sang HLS; tiếng MP2 thì phát hình không tiếng. Hình xen "
           @"kẽ dạng trường của đài phát sóng (1080i) hay DASH (.mpd) thì máy cũ không phát.";
}

- (NSString *)listDetail:(NSDictionary *)l {
    if (CBStr(l, @"err")) return @"Lỗi";
    if (!CBNum(l, @"updated", 0)) return @"Chưa tải";
    return [NSString stringWithFormat:@"%ld kênh · %@", (long)CBNum(l, @"count", 0), [CBIPTV clock:CBNum(l, @"updated", 0) / 1000]];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == CBTVSecLists) {
        NSArray *lists = [CBIPTV lists];
        if (ip.row < (NSInteger)lists.count) {
            NSDictionary *l = lists[ip.row];
            BOOL active = [CBStr(l, @"id") isEqualToString:CBStr([CBIPTV activeList], @"id")];
            UITableViewCell *c = [self cell:tv text:[NSString stringWithFormat:@"%@%@", active ? @"✓ " : @"", CBStr(l, @"name")]
                                     detail:[self listDetail:l]];
            if (active) c.textLabel.textColor = [CBTheme brand];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        UITableViewCell *c = [self cell:tv text:@"+ Thêm danh sách (địa chỉ / tệp M3U)" detail:nil];
        c.textLabel.textColor = [CBTheme brand];
        return c;
    }
    if (ip.section == CBTVSecGuide) {
        if (ip.row == 0) {
            NSString *d = [CBIPTV epgOverride] ? @"Tự đặt" : (CBStr([CBIPTV activeList], @"epg") ? @"Lấy từ danh sách" : @"Không có");
            UITableViewCell *c = [self cell:tv text:@"Địa chỉ EPG (XMLTV)" detail:d];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        long long at = [CBIPTV guideUpdated];
        NSString *d = [CBIPTV loading] && [CBIPTV status] ? @"Đang tải…"
            : (at ? [NSString stringWithFormat:@"%lu kênh có lịch · %@", (unsigned long)[CBIPTV guideChannelCount], [CBIPTV clock:at / 1000]]
                  : @"Chưa tải");
        return [self cell:tv text:@"Tải lại lịch ngay" detail:d];
    }
    if (ip.row == 0) return [self switchCell:tv text:@"Ẩn kênh máy không phát được" on:[CBIPTV hideBad] tag:1];
    if (ip.row == 1) return [self switchCell:tv text:@"Nguồn lỗi thì tự sang nguồn khác" on:[CBIPTV autoSource] tag:2];
    UITableViewCell *c = [self cell:tv text:@"Xoá dấu «không phát được»" detail:nil];
    c.textLabel.textColor = CBRGB(0xE5533D);
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == CBTVSecLists) {
        NSArray *lists = [CBIPTV lists];
        if (ip.row >= (NSInteger)lists.count) {
            [CBTVViewController askAddList:^(NSDictionary *l) { [tv reloadData]; }];
            return;
        }
        _sheetList = lists[ip.row];
        NSString *from = CBStr(_sheetList, @"url") ?: [NSString stringWithFormat:@"Tệp «%@»", CBStr(_sheetList, @"src") ?: @"?"];
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@\n%@", CBStr(_sheetList, @"name"), from]
                                                           delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
                                                  otherButtonTitles:nil];
        [sheet addButtonWithTitle:@"Dùng danh sách này"];
        [sheet addButtonWithTitle:@"Tải lại"];
        [sheet addButtonWithTitle:@"Đổi tên…"];
        sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Xoá danh sách"];
        sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Huỷ"];
        UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
        if ([CBTheme isPad] && cell) [sheet showFromRect:cell.bounds inView:cell animated:YES];
        else [sheet showInView:self.view];
        return;
    }
    if (ip.section == CBTVSecGuide && ip.row == 0) {
        CBAlert *a = [CBAlert title:@"Địa chỉ lịch phát sóng" message:@"XMLTV (.xml / .xml.gz). Để trống = lấy từ danh sách kênh."
                             cancel:@"Huỷ" others:@[@"Lưu"] done:^(CBAlert *alert, NSInteger index) {
            if (index == alert.cancelButtonIndex) return;
            [CBIPTV setEpgOverride:[alert textFieldAtIndex:0].text];
            [CBIPTV refreshGuide:YES done:^(NSString *err) { if (err) [CBTheme toast:err]; }];
            [tv reloadData];
        }];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *f = [a textFieldAtIndex:0];
        f.text = [CBIPTV epgOverride] ?: @"";
        f.placeholder = CBStr([CBIPTV activeList], @"epg") ?: @"http://…/epg.xml.gz";
        f.keyboardType = UIKeyboardTypeURL;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [a show];
        return;
    }
    if (ip.section == CBTVSecGuide && ip.row == 1) {
        [CBIPTV refreshGuide:YES done:^(NSString *err) {
            [CBTheme toast:err ?: [NSString stringWithFormat:@"Đã tải lịch: %lu kênh có lịch.", (unsigned long)[CBIPTV guideChannelCount]]];
            [tv reloadData];
        }];
        [tv reloadData];
        return;
    }
    if (ip.section == CBTVSecPlay && ip.row == 2) {
        [CBIPTV clearBad];
        [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
        [CBTheme toast:@"Đã xoá — lần mở sau app thử lại các kênh đó."];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    NSDictionary *l = _sheetList;
    _sheetList = nil;
    if (!l || index < 0 || index == sheet.cancelButtonIndex) return;
    NSString *t = [sheet buttonTitleAtIndex:index];
    NSString *lid = CBStr(l, @"id");
    if ([t isEqualToString:@"Dùng danh sách này"]) {
        [CBIPTV setActive:lid];
        [CBIPTV refresh:NO done:^(NSString *err) { if (err) [CBTheme toast:err]; }];
    } else if ([t isEqualToString:@"Tải lại"]) {
        [CBIPTV setActive:lid];
        [CBIPTV refresh:YES done:^(NSString *err) {
            [CBTheme toast:err ?: [NSString stringWithFormat:@"Đã tải %lu kênh.", (unsigned long)[CBIPTV channels].count]];
        }];
    } else if ([t isEqualToString:@"Đổi tên…"]) {
        CBAlert *a = [CBAlert title:@"Đổi tên danh sách" message:nil cancel:@"Huỷ" others:@[@"Lưu"] done:^(CBAlert *alert, NSInteger i) {
            if (i == alert.cancelButtonIndex) return;
            [CBIPTV renameList:lid name:[[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
            [self.tableView reloadData];
        }];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        [a textFieldAtIndex:0].text = CBStr(l, @"name");
        [a show];
        return;
    } else if (index == sheet.destructiveButtonIndex) {
        [CBIPTV removeList:lid];
        CBLog(@"Truyền hình: xoá danh sách %@", CBStr(l, @"url"));
    }
    [self.tableView reloadData];
}

@end
