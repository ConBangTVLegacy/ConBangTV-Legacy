#import "CBHomeViewController.h"
#import "CBCore.h"
#import "CBDetailViewController.h"
#import "CBFilterViewController.h"
#import "CBGridViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBProfilesViewController.h"
#import "CBRowCell.h"
#import "CBSettingsViewController.h"
#import "CBSync.h"
#import "CBIPTV.h"
#import "CBTVViewController.h"
#import "CBGlass.h"
#import "CBIcon.h"
#import "CBRootViewController.h"
#import "CBSheet.h"
#import "CBTabHeader.h"
#import "CBTheme.h"

@interface CBHomeViewController () <UIActionSheetDelegate>
@end

@implementation CBHomeViewController {
    NSArray *_headRows;     // «Có tập mới», «Xem tiếp» (từ dữ liệu người xem)
    NSArray *_feedRows;     // hàng của trang chủ: {id, title, items, more}
    NSArray *_categories;   // danh mục (dải nút đầu trang): {title, url} hoặc {title, kind: genres|countries} (xem menuWith:)
    UIView *_head;          // đầu trang (tableHeaderView): tiêu đề lớn + nút người xem (CBTabHeader), dải nút danh mục
    CBTabHeader *_titleRow;
    UIScrollView *_chips;   // dải nút danh mục cuộn ngang ở đầu trang chủ
    NSArray *_chipTitles;   // chữ trên các nút lần dựng trước — giống thì khỏi dựng lại
    BOOL _refreshOnAppear;  // quay về trang chủ: làm mới «Xem tiếp» / «Có tập mới» sau khi cú trượt xong
    NSString *_note;
    NSInteger _token;
    NSMutableDictionary *_offsets;  // id hàng → chỗ đã cuộn ngang
    NSDictionary *_longItem;
    NSString *_profileShown;
    NSString *_contFirst, *_freshFirst;  // phim đầu hàng «Xem tiếp» / «Có tập mới» lần dựng trước
    NSArray *_fresh;       // «fresh» của lõi: phim đang xem dở có tập mới ở bất kỳ nguồn nào [{c: thẻ, k: tên chuẩn, e: tập}]
    long long _loadedAt;   // lần tải trang chủ gần nhất (ms) — quay lại app sau 20 phút thì tải lại
    // iOS 5 (chưa có UIRefreshControl): «kéo xuống để tải lại» tự vẽ phía trên bảng
    UIView *_pull;
    UILabel *_pullLabel;
    UIActivityIndicatorView *_pullSpin;
    BOOL _pullLoading;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Côn Bằng TV";  // tên ngắn: «… Legacy» không vừa dưới biểu tượng iPad
        _offsets = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (NSClassFromString(@"UIRefreshControl")) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        self.refreshControl.tintColor = [CBTheme dim];
        [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    } else {
        [self buildPull];  // iOS 5: chưa có UIRefreshControl
    }
    // Đồng bộ vừa gộp dữ liệu của máy khác: vẽ lại «Có tập mới» / «Xem tiếp» (người xem có thể đã đổi)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncDataChanged) name:CBSyncDataChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActive)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    // Tìm kiếm / Cài đặt / Truyền hình / Theo dõi là tab (CBRootViewController); thanh điều hướng ẩn ở màn này — tiêu đề lớn
    // nằm trong đầu trang (cuộn đi cùng nội dung)
    _head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, [CBTabHeader height])];
    _head.backgroundColor = [UIColor clearColor];
    _titleRow = [[CBTabHeader alloc] initWithTitle:self.title];
    _titleRow.frame = _head.bounds;
    [_head addSubview:_titleRow];
    _chips = [[UIScrollView alloc] initWithFrame:CGRectMake(0, [CBTabHeader height], self.view.bounds.size.width, 0)];
    _chips.backgroundColor = [UIColor clearColor];
    _chips.showsHorizontalScrollIndicator = NO;
    _chips.scrollsToTop = NO;
    _chips.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_head addSubview:_chips];
    self.tableView.tableHeaderView = _head;
    [self reload];
}

#pragma mark - Kéo xuống để tải lại (iOS 5)

- (void)buildPull {
    CGFloat w = self.tableView.bounds.size.width;
    _pull = [[UIView alloc] initWithFrame:CGRectMake(0, -60, w, 60)];
    _pull.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _pull.backgroundColor = [UIColor clearColor];
    _pullLabel = [[UILabel alloc] initWithFrame:_pull.bounds];
    _pullLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _pullLabel.backgroundColor = [UIColor clearColor];
    _pullLabel.textColor = [CBTheme dim];
    _pullLabel.font = [CBTheme font:13];
    _pullLabel.textAlignment = NSTextAlignmentCenter;
    _pullLabel.text = @"↓ Kéo xuống để tải lại";
    [_pull addSubview:_pullLabel];
    _pullSpin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _pullSpin.hidesWhenStopped = YES;
    _pullSpin.center = CGPointMake(w / 2 - 80, 30);
    _pullSpin.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_pull addSubview:_pullSpin];
    [self.tableView addSubview:_pull];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (!_pull || _pullLoading) return;
    _pullLabel.text = sv.contentOffset.y < -65 ? @"↑ Thả ra để tải lại" : @"↓ Kéo xuống để tải lại";
}

- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate {
    if (!_pull || _pullLoading || sv.contentOffset.y >= -65) return;
    _pullLoading = YES;
    _pullLabel.text = @"Đang tải lại…";
    [_pullSpin startAnimating];
    CGFloat bottom = sv.contentInset.bottom;   // lề dưới của thanh tab (CBRootViewController)
    [UIView animateWithDuration:0.2 animations:^{ sv.contentInset = UIEdgeInsetsMake(60, 0, bottom, 0); }];
    [self reload];
}

/// Tải trang chủ xong (được / lỗi): tắt vòng xoay của UIRefreshControl (iOS 6) hoặc phần kéo tự vẽ (iOS 5)
- (void)endRefresh {
    if (!_pull) {
        [self.refreshControl endRefreshing];
        return;
    }
    if (!_pullLoading) return;
    _pullLoading = NO;
    [_pullSpin stopAnimating];
    _pullLabel.text = @"↓ Kéo xuống để tải lại";
    CGFloat bottom = self.tableView.contentInset.bottom;
    [UIView animateWithDuration:0.25 animations:^{ self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0); }];
}

#pragma mark - Danh mục

/// Dải nút danh mục ở đầu trang chủ (★ Điểm IMDb cao, Thể loại, Quốc gia, danh mục của trang) — trước đây nằm tận cuối trang
- (void)buildChips {
    // Chữ trên các nút («Theo dõi» kèm số phim có tập mới) — giống lần dựng trước thì giữ nguyên dải nút (dựng lại ~20 nút mỗi lần
    // quay về trang chủ tốn ~0,1–0,2 s trên iPad 1)
    NSMutableArray *titles = [NSMutableArray array];
    NSInteger fresh = -1;
    for (NSDictionary *c in _categories) {
        NSString *t = CBStr(c, @"title") ?: @"";
        if ([t hasSuffix:@"…"]) t = [t substringToIndex:t.length - 1];
        if ([CBStr(c, @"kind") isEqualToString:@"follows"]) {
            if (fresh < 0) {
                fresh = 0;
                for (NSDictionary *f in [CBPrefs follows]) fresh += CBNum(f, @"count", 0) > CBNum(f, @"seen", 0);
            }
            if (fresh) t = [t stringByAppendingFormat:@" (%ld mới)", (long)fresh];
        }
        [titles addObject:t];
    }
    // Chấm báo ở tab «Theo dõi»: có phim theo dõi ra tập mới
    NSInteger freshFollows = 0;
    for (NSDictionary *f in [CBPrefs follows]) freshFollows += CBNum(f, @"count", 0) > CBNum(f, @"seen", 0);
    [[CBRootViewController current] setBadge:freshFollows > 0 forTab:CBTabFollows];
    if (titles.count && [titles isEqualToArray:_chipTitles ?: @[]]) return;
    _chipTitles = titles;
    for (UIView *v in _chips.subviews) [v removeFromSuperview];
    BOOL pad = [CBTheme isPad];
    CGFloat x = pad ? 20 : 16, h = pad ? 36 : 32;
    UIFont *font = [CBTheme medium:pad ? 14 : 13];
    for (NSUInteger i = 0; i < _categories.count; i++) {
        NSString *t = titles[i];
        BOOL star = [t hasPrefix:@"★ "] || [t hasPrefix:@"☆ "];
        if (star) t = [t substringFromIndex:2];
        CBPillButton *b = [CBPillButton pill:t style:CBPillSubtle];
        b.tag = (NSInteger)i;
        b.titleLabel.font = font;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, star ? 12 : 14, 0, 14);
        CGFloat w = ceil([t sizeWithFont:font].width) + 28;
        if (star) {
            [b setImage:[CBIcon named:@"star" size:13 color:[CBTheme focus] filled:YES] forState:UIControlStateNormal];
            b.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
            b.titleEdgeInsets = UIEdgeInsetsMake(0, 3, 0, -3);
            w += 18;
        }
        b.frame = CGRectMake(x, 0, w, h);
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chips addSubview:b];
        x += w + 8;
    }
    _chips.contentSize = CGSizeMake(x + 8, h);
    CGFloat headH = [CBTabHeader height];
    _chips.frame = CGRectMake(0, headH, self.tableView.bounds.size.width, _categories.count ? h : 0);
    _head.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, headH + (_categories.count ? h + 4 : 0));
    self.tableView.tableHeaderView = _head;   // gán lại cho bảng đọc chiều cao mới
}

- (void)chipTapped:(UIButton *)b {
    if (b.tag < (NSInteger)_categories.count) [self openCategory:_categories[b.tag]];
}

/// Mở một mục danh mục (gỡ lỗi: lệnh «chip <số>»)
- (void)openCategoryAt:(NSInteger)i {
    if (i >= 0 && i < (NSInteger)_categories.count) [self openCategory:_categories[i]];
}

- (void)openCategory:(NSDictionary *)cat {
    NSString *kind = CBStr(cat, @"kind");
    if ([kind isEqualToString:@"tv"]) {
        [[CBRootViewController current] selectTab:CBTabTV];
        return;
    }
    if ([kind isEqualToString:@"follows"]) {
        [self.navigationController pushViewController:[[CBGridViewController alloc] initFollows] animated:YES];
        return;
    }
    if (kind) {
        [self.navigationController pushViewController:[[CBFilterViewController alloc] initGenres:[kind isEqualToString:@"genres"]]
                                             animated:YES];
        return;
    }
    if (!CBStr(cat, @"url")) return;
    NSString *title = [CBStr(cat, @"url") isEqualToString:@"imdb:top"] ? @"Điểm IMDb cao" : CBStr(cat, @"title");
    [self.navigationController pushViewController:[[CBGridViewController alloc] initWithListUrl:CBStr(cat, @"url") title:title]
                                         animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateProfileButton];
    // Đổi người xem / kiểu trang chủ / hồ sơ trẻ em / trang phim (màn khác) → tải lại cả trang chủ; không thì chỉ làm mới
    // «Xem tiếp» / «Có tập mới»
    if ((_profileShown && ![_profileShown isEqualToString:[self homeSignature]]) || [self stale]) {
        [self reload];
    } else {
        // Làm sau khi cú trượt quay về xong: dựng lại dải nút + nạp lại bảng ngay lúc này làm cú trượt bắt đầu chậm ~0,2 s và giật
        // (iPad 1: 550 ms, 31 khung/s)
        _refreshOnAppear = YES;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_refreshOnAppear) return;
    _refreshOnAppear = NO;
    NSArray *old = _headRows;
    [self saveVisibleOffsets];
    [self rebuildHead];
    [self buildChips];
    if (![old isEqual:_headRows]) [self.tableView reloadData];   // «Xem tiếp» / «Có tập mới» không đổi thì khỏi nạp lại cả bảng
}

/// Giữ vị trí cuộn ngang của các hàng đang hiện (trước khi dựng lại hàng)
- (void)saveVisibleOffsets {
    for (UITableViewCell *c in self.tableView.visibleCells) {
        if ([c isKindOfClass:[CBRowCell class]] && [(CBRowCell *)c rowId]) {
            _offsets[[(CBRowCell *)c rowId]] = @([(CBRowCell *)c offset]);
        }
    }
}

/// Để app lâu (≥ 20 phút) rồi quay lại: trang chủ cũ — tải lại (như bản Windows / iPad). Chỉ khi đang ở trang chủ.
- (BOOL)stale {
    return _loadedAt && CBNowMs() - _loadedAt > 20 * 60 * 1000;
}

- (void)appActive {
    if (![self stale] || self.navigationController.topViewController != self || self.presentedViewController) return;
    CBLog(@"Quay lại app sau %lld phút — tải lại trang chủ", (CBNowMs() - _loadedAt) / 60000);
    [self reload];
}

- (void)updateProfileButton {
    NSDictionary *p = [CBPrefs currentProfile];
    NSString *sig = [NSString stringWithFormat:@"%@|%@|%@", CBStr(p, @"id"), CBStr(p, @"name"), p[@"color"]];
    if ([sig isEqualToString:_titleRow.accessibilityHint ?: @""]) return;
    _titleRow.accessibilityHint = sig;
    UIButton *b = [CBTabHeader avatarButton:p target:self action:@selector(openProfiles)];
    if ([CBTheme isPad]) _titleRow.leftItems = @[b];
    else _titleRow.rightItems = @[b];
}

#pragma mark - Dữ liệu

- (void)syncDataChanged {
    [self saveVisibleOffsets];
    [self rebuildHead];
    [self.tableView reloadData];
}

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
    // + phim đang xem dở (không theo dõi) có tập mới ở bất kỳ nguồn nào (fresh của lõi); đã mở phim từ lúc đó thì thôi
    if (_fresh.count) {
        NSMutableSet *followed = [NSMutableSet set], *shown = [NSMutableSet set];
        for (NSDictionary *f in [CBPrefs follows]) {
            id n = [CBCore sync:@"kk.norm" args:@{@"s": CBStr(f, @"title") ?: @""}];
            if (CBIsStr(n)) [followed addObject:n];
        }
        for (NSDictionary *it in fresh) if (CBStr(it, @"url")) [shown addObject:CBStr(it, @"url")];
        id seenAll = [CBPrefs get:[CBPrefs k:@"seen_eps"]];
        for (id a in _fresh) {
            NSString *key = CBStr(a, @"k");
            if (!key.length || [followed containsObject:key]) continue;
            id seen = CBIsDict(seenAll) ? seenAll[key] : nil;
            if ([seen respondsToSelector:@selector(doubleValue)] && [seen doubleValue] >= CBNum(a, @"e", 0)) continue;
            NSDictionary *card = CBDict(a, @"c");
            NSMutableDictionary *item = [CBItemFromFilm(CBDict(card, @"film")) mutableCopy];
            if (!item[@"url"] || [shown containsObject:item[@"url"]]) continue;
            if (CBStr(card, @"chip")) item[@"badge"] = CBStr(card, @"chip");
            if (CBArr(card, @"links").count > 1) item[@"links"] = CBArr(card, @"links");
            [shown addObject:item[@"url"]];
            [fresh addObject:item];
        }
    }
    if (_fresh.count) CBLog(@"Có tập mới: %lu phim theo dõi + tự động (lõi đưa %lu)", (unsigned long)fresh.count, (unsigned long)_fresh.count);
    if (fresh.count) [rows addObject:@{@"id": @"new-eps", @"title": @"Có tập mới", @"items": fresh, @"more": @"follows:"}];
    // Kênh vừa xem (truyền hình): kênh còn trong danh sách đang chọn
    NSMutableArray *tv = [NSMutableArray array];
    if ([CBIPTV activeList]) {
        for (NSDictionary *r in [CBIPTV recent]) {
            NSDictionary *c = [CBIPTV channelForKey:CBStr(r, @"k")];
            if (c) [tv addObject:c];
        }
    }
    if (tv.count) [rows addObject:@{@"id": @"tv-recent", @"title": @"Kênh vừa xem", @"items": tv, @"more": @"tv:"}];
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
    if (cont.count) [rows addObject:@{@"id": @"continue", @"title": @"Xem tiếp", @"items": cont, @"more": @"history:"}];
    // Phim vừa xem lên đầu «Xem tiếp» / có tập mới khác đầu hàng: cuộn hàng về đầu (giữ vị trí cũ thì phim vừa xem bị khuất)
    NSString *contFirst = cont.count ? CBStr(cont[0], @"url") : nil, *freshFirst = fresh.count ? CBStr(fresh[0], @"url") : nil;
    if (!(contFirst == _contFirst || [contFirst isEqualToString:_contFirst])) [_offsets removeObjectForKey:@"continue"];
    if (!(freshFirst == _freshFirst || [freshFirst isEqualToString:_freshFirst])) [_offsets removeObjectForKey:@"new-eps"];
    _contFirst = contFirst;
    _freshFirst = freshFirst;
    _headRows = rows;
}

/// Những gì quyết định nội dung trang chủ (như HomePage của bản Windows so HomeMixOn / Kids / BaseUrl)
- (NSString *)homeSignature {
    return [NSString stringWithFormat:@"%@|%d|%d|%@", [CBPrefs profileId], [CBPrefs homeMix], [CBPrefs kids], [CBPrefs baseUrl]];
}

- (void)reload {
    NSInteger t = ++_token;
    _loadedAt = CBNowMs();
    NSString *sig = [self homeSignature];
    if (_profileShown && ![_profileShown isEqualToString:sig]) {
        // Đổi người xem / hồ sơ trẻ em / trang phim / kiểu trang chủ: bỏ ngay hàng phim của trang chủ cũ (không để hàng của
        // người trước nằm đó tới khi tải xong — hay mãi nếu tải lỗi)
        _feedRows = nil;
        _categories = nil;
        _fresh = nil;
        [_offsets removeAllObjects];
        [self buildChips];
    }
    _profileShown = sig;
    [self saveVisibleOffsets];
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
            [self endRefresh];
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
            [self endRefresh];
            if (!CBIsDict(ok)) {
                [self finishWithError:err token:t];
                return;
            }
            [self siteMoved:base to:CBStr(ok, @"movedTo")];
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
            self->_categories = [self menuWith:CBArr(ok, @"categories")];
            [self buildChips];
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
    [self endRefresh];
    if (!_feedRows.count) _note = [NSString stringWithFormat:@"Không tải được trang chủ.\n%@\nKéo xuống để thử lại.", err ?: @""];
    else [CBTheme toast:[NSString stringWithFormat:@"Không làm mới được trang chủ: %@", err ?: @"lỗi mạng"]];
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
            if (CBArr(card, @"links").count > 1) item[@"links"] = CBArr(card, @"links");  // trang phim: «⇄ đổi nguồn»
            if (item[@"url"]) [items addObject:item];
        }
        if (!items.count) continue;
        NSMutableDictionary *row = [@{@"id": rid, @"title": CBStr(r, @"title") ?: @"", @"items": items} mutableCopy];
        if (CBStr(r, @"more")) row[@"more"] = CBStr(r, @"more");
        [rows addObject:row];
    }
    _feedRows = rows;
    NSDictionary *moved = CBDict(snap, @"movedTo");
    if (moved && [CBStr(moved, @"old") isEqualToString:[CBPrefs baseUrl]]) [self siteMoved:CBStr(moved, @"old") to:CBStr(moved, @"new")];
    _fresh = CBArr(snap, @"fresh");
    [self saveVisibleOffsets];
    [self rebuildHead];
    NSArray *cats = CBArr(snap, @"categories");
    _categories = [self menuWith:cats.count ? cats : [CBCore sync:@"site.menu" args:@{@"baseUrl": [CBPrefs baseUrl]}]];
    [self buildChips];
    NSString *note = CBStr(snap, @"note");
    _note = rows.count ? note : (note ?: (CBBool(snap, @"empty", NO) ? @"Chưa đọc được phim nào — kéo xuống để thử lại." : nil));
    [self.tableView reloadData];
}

/// Trang phim đổi tên miền (lõi đọc được chuyển hướng): đổi theo trong danh sách trang + trang đang chọn (như bản Windows)
- (void)siteMoved:(NSString *)old to:(NSString *)now {
    if (!old.length || !now.length) return;
    NSString *n = [now stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while ([n hasSuffix:@"/"]) n = [n substringToIndex:n.length - 1];
    if (![n hasPrefix:@"http://"] && ![n hasPrefix:@"https://"]) n = [@"https://" stringByAppendingString:n];
    if (![NSURL URLWithString:n].host || [n isEqualToString:old]) return;
    NSMutableArray *sites = [[CBPrefs sites] mutableCopy] ?: [NSMutableArray array];
    NSUInteger i = [sites indexOfObject:old];
    if (i != NSNotFound) sites[i] = n;
    [CBPrefs setSites:sites];
    [CBPrefs setBaseUrl:n];
    _profileShown = [self homeSignature];  // không tải lại cả trang chủ chỉ vì đổi địa chỉ
    CBLog(@"Trang %@ đã chuyển sang %@", old, n);
    [CBTheme toast:[NSString stringWithFormat:@"Trang đã chuyển sang %@ — app đã đổi theo.", [NSURL URLWithString:n].host]];
}

/// Danh mục (dải nút đầu trang, giống menu bản Windows): Điểm IMDb cao, Thể loại… / Quốc gia… (trang có bộ lọc), danh mục của trang
- (NSArray *)menuWith:(id)cats {
    // «Theo dõi», «Truyền hình» là tab (CBRootViewController) — không còn nút ở đây
    NSMutableArray *m = [NSMutableArray arrayWithObjects:@{@"title": @"★ Điểm IMDb cao", @"url": @"imdb:top"}, nil];
    if ([CBFilterViewController available]) {
        [m addObject:@{@"title": @"Thể loại…", @"kind": @"genres"}];
        [m addObject:@{@"title": [[CBFilterViewController secondName] stringByAppendingString:@"…"], @"kind": @"countries"}];
    }
    if (CBIsArr(cats)) {
        for (id c in cats) if (CBStr(c, @"title") && CBStr(c, @"url")) [m addObject:c];
    }
    return m;
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
    return _note ? 1 : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *rows = [self allRows];
    if (ip.section < (NSInteger)rows.count && [CBStr(rows[ip.section], @"id") isEqualToString:@"tv-recent"]) return [CBTVRowCell height];
    if (ip.section < (NSInteger)rows.count) return [CBRowCell height];
    if (_note && ip.row == 0) return MAX(60, [CBTheme heightOf:_note font:[CBTheme font:15] width:tableView.bounds.size.width - 40] + 30);
    return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section < (NSInteger)[self allRows].count) return [CBTheme isPad] ? 50 : 46;
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray *rows = [self allRows];
    // Kiểu iOS 26: tiêu đề hàng đậm + «›» liền sau chữ, chạm cả tiêu đề = xem thêm (thay nút «Xem thêm ›» bên phải)
    BOOL pad = [CBTheme isPad];
    CGFloat h = pad ? 50 : 46, x = pad ? 20 : 16;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, h)];
    v.backgroundColor = [CBTheme bg];
    if (section >= (NSInteger)rows.count) return nil;
    NSDictionary *row = rows[section];
    UIFont *font = [CBTheme bold:pad ? 22 : 19];
    NSString *title = CBStr(row, @"title") ?: @"";
    BOOL more = CBArr(row, @"items").count > 4 || CBStr(row, @"more");
    CGFloat maxW = v.bounds.size.width - x * 2 - (more ? 22 : 0);
    CGFloat tw = MIN(maxW, ceil([title sizeWithFont:font].width));
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(x, h - 36, tw + (more ? 22 : 0), 32);
    b.titleLabel.font = font;
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme text] forState:UIControlStateNormal];
    [b setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.userInteractionEnabled = more;
    b.tag = section;
    if (more) {
        [b setImage:[CBIcon named:@"forward" size:17 color:[CBTheme dim]] forState:UIControlStateNormal];
        // ảnh sau chữ: đổi chỗ ảnh / chữ bằng lề
        b.titleEdgeInsets = UIEdgeInsetsMake(0, -17, 0, 17);
        b.imageEdgeInsets = UIEdgeInsetsMake(1, tw + 2, 0, -tw - 2);
        b.accessibilityLabel = [title stringByAppendingString:@" — xem thêm"];
        [b addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [v addSubview:b];
    return v;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *rows = [self allRows];
    if (ip.section < (NSInteger)rows.count && [CBStr(rows[ip.section], @"id") isEqualToString:@"tv-recent"]) {
        CBTVRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tv"];
        if (!cell) cell = [[CBTVRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tv"];
        NSArray *channels = CBArr(rows[ip.section], @"items");
        __weak CBHomeViewController *weakSelf = self;
        cell.onSelect = ^(NSInteger i) {
            if (i < (NSInteger)channels.count) [CBTVViewController playKey:CBStr(channels[i], @"k") from:weakSelf];
        };
        [cell setChannels:channels];
        return cell;
    }
    if (ip.section < (NSInteger)rows.count) {
        CBRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
        if (!cell) cell = [[CBRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
        NSDictionary *row = rows[ip.section];
        NSString *rid = CBStr(row, @"id") ?: @"";
        __weak CBHomeViewController *weakSelf = self;
        cell.onSelect = ^(NSDictionary *item) { [weakSelf open:item]; };
        cell.onLongPress = ^(NSDictionary *item) { [weakSelf longPress:item]; };
        cell.rowId = rid;
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
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    // Theo mã hàng gắn trên ô: lúc này hàng có thể đã dựng lại (chỉ số dòng cũ trỏ sang hàng khác)
    if ([cell isKindOfClass:[CBRowCell class]] && [(CBRowCell *)cell rowId]) {
        _offsets[[(CBRowCell *)cell rowId]] = @([(CBRowCell *)cell offset]);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
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

- (void)openMore:(NSInteger)r {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = r;
    [self moreTapped:b];
}

- (void)moreTapped:(UIButton *)b {
    NSArray *rows = [self allRows];
    if (b.tag >= (NSInteger)rows.count) return;
    NSDictionary *row = rows[b.tag];
    if ([CBStr(row, @"more") isEqualToString:@"tv:"]) {
        [[CBRootViewController current] selectTab:CBTabTV];
        return;
    }
    if ([CBStr(row, @"more") isEqualToString:@"follows:"] || [CBStr(row, @"more") isEqualToString:@"history:"]) {
        BOOL follows = [CBStr(row, @"more") isEqualToString:@"follows:"];
        [self.navigationController pushViewController:follows ? [[CBGridViewController alloc] initFollows]
                                                              : [[CBGridViewController alloc] initHistory]
                                             animated:YES];
        return;
    }
    UIViewController *vc = CBStr(row, @"more")
        ? [[CBGridViewController alloc] initWithListUrl:CBStr(row, @"more") title:CBStr(row, @"title")]
        : [[CBGridViewController alloc] initWithItems:CBArr(row, @"items") title:CBStr(row, @"title")];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)longPress:(NSDictionary *)item {
    NSString *kind = CBStr(item, @"kind");
    if (!kind) return;
    _longItem = item;
    UIActionSheet *sheet = [[CBSheet alloc] initWithTitle:CBStr(item, @"title") delegate:self cancelButtonTitle:@"Huỷ"
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
    [self saveVisibleOffsets];
    [self rebuildHead];
    [self.tableView reloadData];
}

- (void)openSearch {
    [[CBRootViewController current] selectTab:CBTabSearch];
}

- (void)openSettings {
    [[CBRootViewController current] selectTab:CBTabSettings];
}

- (void)openProfiles {
    // Đổi người xem: viewWillAppear (khi màn chọn đóng) thấy chữ ký trang chủ đổi thì tải lại — không tải thêm lần nữa ở đây
    CBProfilesViewController *p = [[CBProfilesViewController alloc] init];
    p.closable = YES;
    [self presentViewController:p animated:YES completion:nil];
}

@end
