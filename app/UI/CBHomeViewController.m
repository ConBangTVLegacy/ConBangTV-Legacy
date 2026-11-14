#import "CBHomeViewController.h"
#import "CBCore.h"
#import "CBDetailViewController.h"
#import "CBGridViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBProfilesViewController.h"
#import "CBRowCell.h"
#import "CBSettingsViewController.h"
#import "CBTheme.h"

@interface CBHomeViewController () <UIActionSheetDelegate>
@end

@implementation CBHomeViewController {
    NSArray *_headRows;     // «Có tập mới», «Xem tiếp» (từ dữ liệu người xem)
    NSArray *_feedRows;     // hàng của trang chủ: {id, title, items, more}
    NSArray *_categories;   // {title, url}
    NSString *_note;
    NSInteger _token;
    NSMutableDictionary *_offsets;  // id hàng → chỗ đã cuộn ngang
    NSDictionary *_longItem;
    NSString *_profileShown;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Côn Bằng TV Legacy";
        _offsets = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [CBTheme dim];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    UIBarButtonItem *search = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self
                                                                            action:@selector(openSearch)];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithTitle:@"Cài đặt" style:UIBarButtonItemStyleBordered target:self
                                                                action:@selector(openSettings)];
    self.navigationItem.rightBarButtonItems = @[settings, search];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Trang chủ" style:UIBarButtonItemStyleBordered
                                                                            target:nil action:nil];
    // Tên app dài: tự thu nhỏ chữ cho vừa thanh tiêu đề (iPhone dọc bị cắt «Côn Bằng TV Le…»)
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
    title.backgroundColor = [UIColor clearColor];
    title.textColor = [CBTheme text];
    title.font = [CBTheme bold:18];
    title.textAlignment = NSTextAlignmentCenter;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.6;
    title.text = self.title;
    self.navigationItem.titleView = title;
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateProfileButton];
    // Đổi người xem (màn khác) → tải lại cả trang chủ; không thì chỉ làm mới «Xem tiếp» / «Có tập mới»
    if (_profileShown && ![_profileShown isEqualToString:[CBPrefs profileId]]) {
        [self reload];
    } else {
        [self rebuildHead];
        [self.tableView reloadData];
    }
}

- (void)updateProfileButton {
    NSDictionary *p = [CBPrefs currentProfile];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 30, 30);
    UIView *avatar = [CBTheme avatarFor:p size:28];
    avatar.frame = CGRectMake(1, 1, 28, 28);
    avatar.userInteractionEnabled = NO;
    [b addSubview:avatar];
    [b addTarget:self action:@selector(openProfiles) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:b];
}

#pragma mark - Dữ liệu

- (void)rebuildHead {
    NSMutableArray *rows = [NSMutableArray array];
    // Có tập mới: phim theo dõi có tập chưa xem
    NSMutableArray *fresh = [NSMutableArray array];
    for (NSDictionary *f in [CBPrefs follows]) {
        NSInteger n = (NSInteger)CBNum(f, @"count", 0) - (NSInteger)CBNum(f, @"seen", 0);
        if (n <= 0 || !CBStr(f, @"filmUrl")) continue;
        NSMutableDictionary *item = [@{@"url": CBStr(f, @"filmUrl"), @"title": CBStr(f, @"title") ?: @"",
                                       @"badge": [NSString stringWithFormat:@"+%ld tập", (long)n], @"kind": @"follow"} mutableCopy];
        if (CBStr(f, @"poster")) item[@"poster"] = CBStr(f, @"poster");
        if (CBStr(f, @"latest")) item[@"sub"] = CBStr(f, @"latest");
        [fresh addObject:item];
    }
    if (fresh.count) [rows addObject:@{@"id": @"new-eps", @"title": @"Có tập mới", @"items": fresh}];
    // Xem tiếp: lịch sử (bấm là phát tiếp)
    NSMutableArray *cont = [NSMutableArray array];
    for (NSDictionary *h in [CBPrefs history]) {
        if (!CBStr(h, @"filmUrl") || !CBStr(h, @"epUrl")) continue;
        NSMutableDictionary *item = [@{@"url": CBStr(h, @"filmUrl"), @"title": CBStr(h, @"title") ?: @"",
                                       @"epUrl": CBStr(h, @"epUrl"), @"sub": CBStr(h, @"epTitle") ?: @"", @"kind": @"continue"}
                                     mutableCopy];
        if (CBStr(h, @"poster")) item[@"poster"] = CBStr(h, @"poster");
        [cont addObject:item];
        if (cont.count >= 20) break;
    }
    if (cont.count) [rows addObject:@{@"id": @"continue", @"title": @"Xem tiếp", @"items": cont}];
    _headRows = rows;
}

- (void)reload {
    NSInteger t = ++_token;
    _profileShown = [CBPrefs profileId];
    [self rebuildHead];
    if (!_feedRows.count) _note = @"Đang tải trang chủ…";
    [self.tableView reloadData];
    if ([CBPrefs homeMix]) {
        NSDictionary *plan = [CBCore sync:@"home.makePlan" args:@{@"tagsKnownOnly": @NO}];
        id handle = CBVal(plan, @"handle");
        if (!handle) {
            [self finishWithError:@"Không lập được trang chủ" token:t];
            return;
        }
        id cached = [CBCore sync:@"home.cached" args:@{@"plan": handle}];
        if (CBIsDict(cached)) [self applySnapshot:cached];
        long long t0 = CBNowMs();
        [CBCore call:@"home.load" args:@{@"plan": handle} done:^(id ok, NSString *err) {
            if (t != self->_token) return;
            CBLog(@"Trang chủ tổng hợp: %lld ms, %lu hàng%@", CBNowMs() - t0, (unsigned long)CBArr(ok, @"rows").count,
                  CBBool(ok, @"pending", NO) ? @" (còn nguồn chậm)" : @"");
            [self.refreshControl endRefreshing];
            if (CBIsDict(ok)) {
                [self applySnapshot:ok];
                if (CBBool(ok, @"pending", NO)) [self late:CBVal(ok, @"handle") token:t tries:3];
            } else {
                [self finishWithError:err token:t];
            }
        }];
    } else {
        NSString *base = [CBPrefs baseUrl];
        [CBCore call:@"site.homeOf" args:@{@"baseUrl": base} done:^(id ok, NSString *err) {
            if (t != self->_token) return;
            [self.refreshControl endRefreshing];
            if (!CBIsDict(ok)) {
                [self finishWithError:err token:t];
                return;
            }
            NSMutableArray *rows = [NSMutableArray array];
            for (id s in CBArr(ok, @"sections") ?: @[]) {
                NSMutableArray *items = [NSMutableArray array];
                for (id f in CBArr(s, @"films") ?: @[]) [items addObject:CBItemFromFilm(f)];
                if (items.count) {
                    [rows addObject:@{@"id": [NSString stringWithFormat:@"s%lu", (unsigned long)rows.count],
                                      @"title": CBStr(s, @"title") ?: @"", @"items": items}];
                }
            }
            self->_feedRows = rows;
            self->_categories = CBArr(ok, @"categories");
            self->_note = rows.count ? nil : @"Trang này chưa đọc được phim nào.";
            [self.tableView reloadData];
        }];
    }
}

- (void)late:(id)snap token:(NSInteger)t tries:(int)tries {
    if (!snap || tries <= 0) return;
    [CBCore call:@"home.late" args:@{@"snap": snap} done:^(id ok, NSString *err) {
        if (t != self->_token || !CBIsDict(ok)) return;
        [self applySnapshot:ok];
        if (CBBool(ok, @"pending", NO)) [self late:CBVal(ok, @"handle") token:t tries:tries - 1];
    }];
}

- (void)finishWithError:(NSString *)err token:(NSInteger)t {
    if (t != _token) return;
    [self.refreshControl endRefreshing];
    if (!_feedRows.count) _note = [NSString stringWithFormat:@"Không tải được trang chủ.\n%@\nKéo xuống để thử lại.", err ?: @""];
    [self.tableView reloadData];
}

/// Snapshot của lõi: {rows: [{id, title, cards: [{film, chip}], more}], categories, note, empty, pending, handle}
- (void)applySnapshot:(NSDictionary *)snap {
    NSMutableArray *rows = [NSMutableArray array];
    for (id r in CBArr(snap, @"rows") ?: @[]) {
        NSString *rid = CBStr(r, @"id") ?: @"";
        if ([rid isEqualToString:@"continue"] || [rid isEqualToString:@"new-eps"]) continue;  // app tự dựng hai hàng này
        NSMutableArray *items = [NSMutableArray array];
        for (id card in CBArr(r, @"cards") ?: @[]) {
            NSMutableDictionary *item = [CBItemFromFilm(CBDict(card, @"film")) mutableCopy];
            if (CBStr(card, @"chip")) item[@"badge"] = CBStr(card, @"chip");
            if (item[@"url"]) [items addObject:item];
        }
        if (!items.count) continue;
        NSMutableDictionary *row = [@{@"id": rid, @"title": CBStr(r, @"title") ?: @"", @"items": items} mutableCopy];
        if (CBStr(r, @"more")) row[@"more"] = CBStr(r, @"more");
        [rows addObject:row];
    }
    _feedRows = rows;
    NSArray *cats = CBArr(snap, @"categories");
    _categories = cats.count ? cats : [CBCore sync:@"site.menu" args:@{@"baseUrl": [CBPrefs baseUrl]}];
    NSString *note = CBStr(snap, @"note");
    _note = rows.count ? note : (note ?: (CBBool(snap, @"empty", NO) ? @"Chưa đọc được phim nào — kéo xuống để thử lại." : nil));
    [self.tableView reloadData];
}

- (NSArray *)allRows {
    return [_headRows arrayByAddingObjectsFromArray:_feedRows ?: @[]];
}

- (NSArray *)rows {
    return [self allRows];
}

- (void)openRow:(NSInteger)r item:(NSInteger)i {
    NSArray *rows = [self allRows];
    if (r < 0 || r >= (NSInteger)rows.count) return;
    NSArray *items = CBArr(rows[r], @"items");
    if (i >= 0 && i < (NSInteger)items.count) [self open:items[i]];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self allRows].count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < (NSInteger)[self allRows].count) return 1;
    return (_note ? 1 : 0) + (CBIsArr(_categories) ? _categories.count : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section < (NSInteger)[self allRows].count) return [CBRowCell height];
    if (_note && ip.row == 0) return MAX(60, [CBTheme heightOf:_note font:[CBTheme font:15] width:tableView.bounds.size.width - 40] + 30);
    return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section < (NSInteger)[self allRows].count) return 40;
    return CBIsArr(_categories) && _categories.count ? 40 : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray *rows = [self allRows];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    v.backgroundColor = [CBTheme bg];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, v.bounds.size.width - 120, 26)];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [CBTheme text];
    l.font = [CBTheme bold:17];
    [v addSubview:l];
    if (section >= (NSInteger)rows.count) {
        l.text = @"Danh mục";
        return v;
    }
    NSDictionary *row = rows[section];
    l.text = CBStr(row, @"title");
    if (CBArr(row, @"items").count > 4 || CBStr(row, @"more")) {
        UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
        [more setTitle:@"Xem thêm ›" forState:UIControlStateNormal];
        [more setTitleColor:[CBTheme brand] forState:UIControlStateNormal];
        [more setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
        more.titleLabel.font = [CBTheme font:14];
        more.frame = CGRectMake(v.bounds.size.width - 104, 8, 96, 30);
        more.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        more.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        more.tag = section;
        [more addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:more];
    }
    return v;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *rows = [self allRows];
    if (ip.section < (NSInteger)rows.count) {
        CBRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
        if (!cell) cell = [[CBRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
        NSDictionary *row = rows[ip.section];
        NSString *rid = CBStr(row, @"id") ?: @"";
        __weak CBHomeViewController *weakSelf = self;
        cell.onSelect = ^(NSDictionary *item) { [weakSelf open:item]; };
        cell.onLongPress = ^(NSDictionary *item) { [weakSelf longPress:item]; };
        [cell setItems:CBArr(row, @"items") offset:[_offsets[rid] floatValue]];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"plain"];
        cell.backgroundColor = [CBTheme bg];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [CBTheme surface2];
        cell.selectedBackgroundView = sel;
    }
    if (_note && ip.row == 0) {
        cell.textLabel.text = _note;
        cell.textLabel.textColor = [CBTheme dim];
        cell.textLabel.font = [CBTheme font:15];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *cat = _categories[ip.row - (_note ? 1 : 0)];
    cell.textLabel.text = CBStr(cat, @"title");
    cell.textLabel.textColor = [CBTheme text];
    cell.textLabel.font = [CBTheme font:16];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *rows = [self allRows];
    if ([cell isKindOfClass:[CBRowCell class]] && ip.section < (NSInteger)rows.count) {
        NSString *rid = CBStr(rows[ip.section], @"id");
        if (rid) _offsets[rid] = @([(CBRowCell *)cell offset]);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section < (NSInteger)[self allRows].count || (_note && ip.row == 0)) return;
    NSDictionary *cat = _categories[ip.row - (_note ? 1 : 0)];
    if (!CBStr(cat, @"url")) return;
    [self.navigationController pushViewController:[[CBGridViewController alloc] initWithListUrl:CBStr(cat, @"url")
                                                                                          title:CBStr(cat, @"title")]
                                         animated:YES];
}

#pragma mark - Thao tác

- (void)open:(NSDictionary *)item {
    if ([CBStr(item, @"kind") isEqualToString:@"continue"]) {
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:CBStr(item, @"url") detail:nil
                                                                          episode:CBStr(item, @"epUrl") resume:YES];
        [self presentViewController:p animated:YES completion:nil];
        return;
    }
    [self.navigationController pushViewController:[[CBDetailViewController alloc] initWithItem:item] animated:YES];
}

- (void)moreTapped:(UIButton *)b {
    NSArray *rows = [self allRows];
    if (b.tag >= (NSInteger)rows.count) return;
    NSDictionary *row = rows[b.tag];
    UIViewController *vc = CBStr(row, @"more")
        ? [[CBGridViewController alloc] initWithListUrl:CBStr(row, @"more") title:CBStr(row, @"title")]
        : [[CBGridViewController alloc] initWithItems:CBArr(row, @"items") title:CBStr(row, @"title")];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)longPress:(NSDictionary *)item {
    NSString *kind = CBStr(item, @"kind");
    if (!kind) return;
    _longItem = item;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:CBStr(item, @"title") delegate:self cancelButtonTitle:@"Huỷ"
                                         destructiveButtonTitle:[kind isEqualToString:@"continue"] ? @"Xoá khỏi lịch sử"
                                                                                                    : @"Bỏ theo dõi"
                                              otherButtonTitles:nil];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index != sheet.destructiveButtonIndex || !_longItem) return;
    if ([CBStr(_longItem, @"kind") isEqualToString:@"continue"]) [CBPrefs removeHistory:CBStr(_longItem, @"url")];
    else [CBPrefs unfollow:CBStr(_longItem, @"url")];
    _longItem = nil;
    [self rebuildHead];
    [self.tableView reloadData];
}

- (void)openSearch {
    [self.navigationController pushViewController:[[CBGridViewController alloc] initSearch] animated:YES];
}

- (void)openSettings {
    [self.navigationController pushViewController:[[CBSettingsViewController alloc] init] animated:YES];
}

- (void)openProfiles {
    CBProfilesViewController *p = [[CBProfilesViewController alloc] init];
    __weak CBHomeViewController *weakSelf = self;
    p.onDone = ^{ [weakSelf reload]; };
    [self presentViewController:p animated:YES completion:nil];
}

@end
