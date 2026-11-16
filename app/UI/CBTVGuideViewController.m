#import "CBTVGuideViewController.h"
#import "CBImages.h"
#import "CBIPTV.h"
#import "CBJSON.h"
#import "CBLivePlayerViewController.h"
#import "CBLog.h"
#import "CBTheme.h"

@implementation CBTVGuideViewController {
    NSDictionary *_channel;
    NSArray *_all, *_rows;
    UISegmentedControl *_days;
    NSInteger _day;   // -1 hôm qua, 0 hôm nay, 1 ngày mai
    NSTimer *_timer;
}

- (instancetype)initWithChannel:(NSDictionary *)channel {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _channel = channel;
        self.title = @"Lịch phát sóng";
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorColor = CBRGB(0x23272D);
    self.tableView.rowHeight = 54;
    if (self.fromPlayer) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Đóng" style:UIBarButtonItemStyleBordered
                                                                                target:self action:@selector(dismissSelf)];
    }
    [self buildHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:CBIPTVChangedNotification object:nil];
    _timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(reload) userInfo:nil repeats:YES];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) [_timer invalidate];
}

- (void)dismissSelf {
    [_timer invalidate];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)buildHeader {
    CGFloat w = self.tableView.bounds.size.width;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 128)];
    h.backgroundColor = [CBTheme bg];
    h.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *logoBox = [[UIView alloc] initWithFrame:CGRectMake(14, 12, 84, 56)];
    logoBox.backgroundColor = CBRGB(0x262B32);
    logoBox.layer.cornerRadius = 8;
    logoBox.clipsToBounds = YES;
    UILabel *abbr = [[UILabel alloc] initWithFrame:logoBox.bounds];
    abbr.backgroundColor = [UIColor clearColor];
    abbr.textColor = [CBTheme text];
    abbr.font = [CBTheme bold:15];
    abbr.textAlignment = NSTextAlignmentCenter;
    abbr.adjustsFontSizeToFitWidth = YES;
    abbr.text = CBStr(_channel, @"n");
    [logoBox addSubview:abbr];
    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectInset(logoBox.bounds, 4, 4)];
    logo.contentMode = UIViewContentModeScaleAspectFit;
    [logoBox addSubview:logo];
    if (CBStr(_channel, @"logo")) [CBImages load:CBStr(_channel, @"logo") size:logo.bounds.size into:logo];
    [h addSubview:logoBox];
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(110, 14, w - 290, 26)];
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.backgroundColor = [UIColor clearColor];
    name.textColor = [CBTheme text];
    name.font = [CBTheme bold:20];
    name.text = CBStr(_channel, @"n");
    [h addSubview:name];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(110, 40, w - 290, 20)];
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sub.backgroundColor = [UIColor clearColor];
    sub.textColor = [CBTheme dim];
    sub.font = [CBTheme font:14];
    sub.text = [NSString stringWithFormat:@"Kênh %@ · %@%@", CBStr(_channel, @"num") ?: @"", CBStr(_channel, @"g") ?: @"",
                                          [CBIPTV isFavorite:_channel] ? @" · ★ Yêu thích" : @""];
    [h addSubview:sub];
    UIButton *watch = [CBTheme button:[NSString stringWithFormat:@"%@ Xem trực tiếp", CBPlayIcon()] primary:YES];
    watch.frame = CGRectMake(w - 170, 18, 156, 44);
    watch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [watch addTarget:self action:@selector(watch) forControlEvents:UIControlEventTouchUpInside];
    [h addSubview:watch];
    _days = [[UISegmentedControl alloc] initWithItems:@[@"Hôm qua", @"Hôm nay", @"Ngày mai"]];
    _days.segmentedControlStyle = UISegmentedControlStyleBar;
    _days.tintColor = CBRGB(0x2A2F36);
    _days.frame = CGRectMake(14, 82, w - 28, 34);
    _days.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _days.selectedSegmentIndex = 1;
    [_days addTarget:self action:@selector(dayChanged) forControlEvents:UIControlEventValueChanged];
    [h addSubview:_days];
    self.tableView.tableHeaderView = h;
}

- (void)dayChanged {
    _day = _days.selectedSegmentIndex - 1;
    [self reload];
    [self scrollToNow];
}

- (void)watch {
    if (self.fromPlayer) {
        [self dismissSelf];
        return;
    }
    NSArray *channels = [CBIPTV channels];
    NSInteger idx = (NSInteger)[channels indexOfObject:_channel];
    if (idx == NSNotFound) {
        channels = @[_channel];
        idx = 0;
    }
    CBLivePlayerViewController *p = [[CBLivePlayerViewController alloc] initWithChannels:channels index:idx];
    [self presentViewController:p animated:YES completion:nil];
}

- (NSTimeInterval)dayStart:(NSInteger)offset {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    NSDate *midnight = [cal dateFromComponents:c];
    return [midnight timeIntervalSince1970] + offset * 86400;
}

- (void)reload {
    _all = [CBIPTV programmesFor:_channel];
    NSTimeInterval from = [self dayStart:_day], to = from + 86400;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *p in _all) {
        double s = CBNum(p, @"s", 0);
        if (s >= from && s < to) [rows addObject:p];
    }
    _rows = rows;
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scrollToNow];
}

- (void)scrollToNow {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (NSUInteger i = 0; i < _rows.count; i++) {
        if (CBNum(_rows[i], @"e", 0) > now) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]
                                  atScrollPosition:UITableViewScrollPositionTop animated:NO];
            return;
        }
    }
}

#pragma mark - Nhắc

- (UILocalNotification *)reminderFor:(NSDictionary *)p {
    double s = CBNum(p, @"s", 0);
    for (UILocalNotification *n in [UIApplication sharedApplication].scheduledLocalNotifications) {
        if ([n.userInfo[@"iptv"] isEqualToString:CBStr(_channel, @"k")] && fabs([n.userInfo[@"s"] doubleValue] - s) < 1) return n;
    }
    return nil;
}

- (void)toggleReminder:(UIButton *)b {
    if (b.tag < 0 || b.tag >= (NSInteger)_rows.count) return;
    NSDictionary *p = _rows[b.tag];
    UILocalNotification *old = [self reminderFor:p];
    if (old) {
        [[UIApplication sharedApplication] cancelLocalNotification:old];
        [CBTheme toast:@"Đã bỏ nhắc."];
    } else {
        double s = CBNum(p, @"s", 0), now = [[NSDate date] timeIntervalSince1970];
        UILocalNotification *n = [[UILocalNotification alloc] init];
        n.fireDate = [NSDate dateWithTimeIntervalSince1970:MAX(now + 5, s - 300)];
        n.timeZone = [NSTimeZone defaultTimeZone];
        n.alertBody = [NSString stringWithFormat:@"%@ lúc %@ trên %@", CBStr(p, @"t"), [CBIPTV clock:s], CBStr(_channel, @"n")];
        n.alertAction = @"Xem";
        n.soundName = UILocalNotificationDefaultSoundName;
        n.userInfo = @{@"iptv": CBStr(_channel, @"k") ?: @"", @"s": @(s)};
        [[UIApplication sharedApplication] scheduleLocalNotification:n];
        CBLog(@"Truyền hình: nhắc «%@» %@ lúc %@", CBStr(p, @"t"), CBStr(_channel, @"n"), [CBIPTV clock:s]);
        [CBTheme toast:[NSString stringWithFormat:@"Sẽ nhắc lúc %@ (5 phút trước giờ phát).", [CBIPTV clock:MAX(now, s - 300)]]];
    }
    [self.tableView reloadData];
}

#pragma mark - Bảng

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)_rows.count);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"p"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"p"];
        cell.textLabel.backgroundColor = cell.detailTextLabel.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    if (!_rows.count) {
        cell.backgroundColor = [CBTheme bg];
        cell.textLabel.textColor = [CBTheme dim];
        cell.textLabel.font = [CBTheme font:15];
        cell.textLabel.numberOfLines = 0;
        BOOL any = _all.count > 0;
        cell.textLabel.text = any ? @"Ngày này chưa có lịch."
            : ([CBIPTV epgUrl] ? @"Kênh này chưa có lịch phát sóng (lịch của danh sách không có kênh này)."
                               : @"Danh sách kênh không ghi địa chỉ lịch phát sóng. Đặt trong Cài đặt › Truyền hình.");
        cell.detailTextLabel.text = nil;
        cell.accessoryView = nil;
        return cell;
    }
    NSDictionary *p = _rows[ip.row];
    double s = CBNum(p, @"s", 0), e = CBNum(p, @"e", 0), now = [[NSDate date] timeIntervalSince1970];
    BOOL live = s <= now && now < e, past = e <= now;
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.font = [CBTheme bold:16];
    cell.textLabel.text = [NSString stringWithFormat:@"%@    %@", [CBIPTV clock:s], CBStr(p, @"t")];
    cell.textLabel.textColor = live ? [CBTheme brand] : (past ? [CBTheme dim] : [CBTheme text]);
    cell.detailTextLabel.font = [CBTheme font:12];
    cell.detailTextLabel.textColor = live ? CBRGB(0xFF6B6F) : [CBTheme dim];
    cell.detailTextLabel.text = live ? [NSString stringWithFormat:@"ĐANG PHÁT · còn %ld phút", (long)MAX(1, ceil((e - now) / 60))]
                                     : [NSString stringWithFormat:@"%@–%@", [CBIPTV clock:s], [CBIPTV clock:e]];
    cell.backgroundColor = live ? CBRGB(0x1B2B26) : [CBTheme bg];
    if (s > now) {
        BOOL on = [self reminderFor:p] != nil;
        UIButton *b = [CBTheme button:on ? @"Đã đặt nhắc" : @"Nhắc tôi" primary:on];
        b.titleLabel.font = [CBTheme bold:13];
        b.frame = CGRectMake(0, 0, 112, 34);
        b.tag = ip.row;
        [b addTarget:self action:@selector(toggleReminder:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = b;
    } else {
        cell.accessoryView = nil;
    }
    return cell;
}

@end
