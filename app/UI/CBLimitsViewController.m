#import "CBLimitsViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBSync.h"
#import "CBTheme.h"
#import "CBWatchLimit.h"

@implementation CBLimitsViewController {
    NSString *_pid;  // nil = danh sách người xem
}

- (instancetype)initWithProfile:(NSString *)pid {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _pid = [pid copy];
        NSString *name = nil;
        for (NSDictionary *p in [CBPrefs profiles]) {
            if ([(CBStr(p, @"id") ?: @"") isEqualToString:pid ?: @"\x01"]) name = CBStr(p, @"name");
        }
        self.title = pid ? [NSString stringWithFormat:@"Giới hạn — %@", name ?: @"?"] : @"Giới hạn giờ xem";
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
    [self.tableView reloadData];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!_pid) return section == 0 ? (NSInteger)[CBPrefs profiles].count : 2;
    return (NSInteger)(section == 0 ? [CBWatchLimit dailyChoices] : [CBWatchLimit bedtimeChoices]).count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!_pid) return section == 0 ? @"Người xem" : @"Mã PIN phụ huynh";
    return section == 0 ? @"Mỗi ngày được xem" : @"Giờ đi ngủ (không xem được tới 6 giờ sáng)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!_pid) {
        return section == 0 ? @"Chọn người xem để đặt số phút mỗi ngày và giờ đi ngủ. Nên khoá người lớn bằng mã PIN (Cài đặt → "
                              @"Mã PIN) để trẻ không đổi sang người không bị giới hạn."
                            : @"Mã phụ huynh dùng chung cả nhà: đặt giới hạn, cho xem thêm khi hết giờ, thêm / xoá người xem khi "
                              @"đang có giới hạn.";
    }
    if (section == 0) return nil;
    NSString *text = @"Đếm thời gian phim thật sự chạy (dừng / đang tải không tính). Hết giờ: phim dừng, xem thêm phải nhập mã PIN "
                     @"phụ huynh. Tính theo từng máy.";
    if ([_pid isEqualToString:[CBPrefs profileId]]) {
        NSInteger r = [CBWatchLimit remaining];
        if (r != NSNotFound) text = [text stringByAppendingFormat:@"\n\nHôm nay còn %@.", r > 0 ? [CBWatchLimit minutesText:r] : @"0 phút"];
    }
    return text;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        c.backgroundColor = [CBTheme surface];
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.detailTextLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.font = [CBTheme font:16];
        c.detailTextLabel.font = [CBTheme font:15];
        c.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        c.detailTextLabel.minimumScaleFactor = 0.7;
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [CBTheme surface2];
        c.selectedBackgroundView = sel;
    }
    c.textLabel.textColor = [CBTheme text];
    c.detailTextLabel.textColor = [CBTheme dim];
    c.detailTextLabel.text = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    if (!_pid) {
        if (ip.section == 0) {
            NSDictionary *p = [CBPrefs profiles][ip.row];
            c.textLabel.text = CBStr(p, @"name");
            c.detailTextLabel.text = [CBWatchLimit summaryFor:CBStr(p, @"id") ?: @""];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 0) {
            c.textLabel.text = @"Đổi mã PIN phụ huynh…";
        } else {
            c.textLabel.text = @"Xoá mã PIN phụ huynh";
            c.textLabel.textColor = CBRGB(0xE5533D);
        }
        return c;
    }
    NSArray *choices = ip.section == 0 ? [CBWatchLimit dailyChoices] : [CBWatchLimit bedtimeChoices];
    NSInteger v = [choices[ip.row] integerValue];
    NSInteger cur = ip.section == 0 ? [CBWatchLimit dailyLimitFor:_pid] : [CBWatchLimit bedtimeFor:_pid];
    c.textLabel.text = ip.section == 0 ? [CBWatchLimit dailyLabel:v] : [CBWatchLimit bedtimeLabel:v];
    c.accessoryType = v == cur ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!_pid) {
        if (ip.section == 0) {
            NSDictionary *p = [CBPrefs profiles][ip.row];
            [self.navigationController pushViewController:[[CBLimitsViewController alloc] initWithProfile:CBStr(p, @"id") ?: @""]
                                                 animated:YES];
        } else if (ip.row == 0) {
            [CBParental askNewParentPin:^(BOOL ok) {}];
        } else if ([CBWatchLimit anyLimits]) {
            [CBTheme toast:@"Đang có giới hạn giờ xem — bỏ hết giới hạn trước rồi mới xoá được mã phụ huynh."];
        } else {
            [CBPrefs setParentPin:nil];
            CBLog(@"Đã xoá mã PIN phụ huynh");
            [CBTheme toast:@"Đã xoá mã PIN phụ huynh."];
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }
    NSArray *choices = ip.section == 0 ? [CBWatchLimit dailyChoices] : [CBWatchLimit bedtimeChoices];
    NSInteger v = [choices[ip.row] integerValue];
    if (ip.section == 0) [CBWatchLimit setDailyLimit:v for:_pid];
    else [CBWatchLimit setBedtime:v for:_pid];
    CBLog(@"Giới hạn của %@: %@", _pid.length ? _pid : @"(người đầu)", [CBWatchLimit summaryFor:_pid]);
    [CBSync soon:3];
    [tv reloadData];
}

@end
