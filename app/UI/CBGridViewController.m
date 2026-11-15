#import "CBGridViewController.h"
#import "CBCore.h"
#import "CBDetailViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPosterCell.h"
#import "CBPrefs.h"
#import "CBRowCell.h"
#import "CBTheme.h"

@interface CBGridHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *label;
@end

@implementation CBGridHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _label = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 12, 0)];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [CBTheme text];
        _label.font = [CBTheme bold:17];
        [self addSubview:_label];
    }
    return self;
}
@end

@interface CBGridViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout,
                                    UISearchBarDelegate, UIActionSheetDelegate>
@end

@implementation CBGridViewController {
    NSString *_listUrl;
    NSString *_nextUrl;
    BOOL _searchMode;
    BOOL _loading;
    NSArray *_sections;  // @[@{title, items}]
    NSString *_special;  // @"follows" / @"history": dựng từ dữ liệu người xem
    BOOL _checking;      // đang kiểm tập mới của phim theo dõi
    NSDictionary *_longItem;
    NSInteger _token;
    UICollectionView *_cv;
    UISearchBar *_searchBar;
    UILabel *_message;
    UIActivityIndicatorView *_spinner;
    UIButton *_retryButton;
    NSString *_lastQuery;
    long long _pageFailedAt;  // trang sau vừa tải lỗi (ms) — chờ 5 giây mới tự thử lại khi cuộn
}

- (instancetype)initWithListUrl:(NSString *)url title:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _listUrl = url;
        self.title = title;
    }
    return self;
}

- (instancetype)initSearch {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _searchMode = YES;
        self.title = @"Tìm phim";
    }
    return self;
}

- (instancetype)initWithItems:(NSArray *)items title:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _sections = @[@{@"items": items ?: @[]}];
        self.title = title;
    }
    return self;
}

- (instancetype)initFollows {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _special = @"follows";
        self.title = @"Phim theo dõi";
    }
    return self;
}

- (instancetype)initHistory {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _special = @"history";
        self.title = @"Xem tiếp / Lịch sử";
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_special) [self rebuildSpecial];
}

#pragma mark - Theo dõi / lịch sử

- (void)rebuildSpecial {
    NSMutableArray *items = [NSMutableArray array];
    if ([_special isEqualToString:@"follows"]) {
        // Phim có tập mới lên trước
        NSMutableArray *fresh = [NSMutableArray array], *rest = [NSMutableArray array];
        for (NSDictionary *f in [CBPrefs follows]) {
            if (!CBStr(f, @"filmUrl")) continue;
            NSInteger n = (NSInteger)CBNum(f, @"count", 0) - (NSInteger)CBNum(f, @"seen", 0);
            NSMutableDictionary *it = [@{@"url": CBStr(f, @"filmUrl"), @"title": CBStr(f, @"title") ?: @""} mutableCopy];
            if (CBStr(f, @"poster")) it[@"poster"] = CBStr(f, @"poster");
            if ([CBStr(f, @"latest") length]) it[@"sub"] = CBStr(f, @"latest");
            if (n > 0) it[@"badge"] = [NSString stringWithFormat:@"+%ld tập", (long)n];
            [(n > 0 ? fresh : rest) addObject:it];
        }
        [items addObjectsFromArray:fresh];
        [items addObjectsFromArray:rest];
        [self showMessage:items.count ? nil : @"Chưa theo dõi phim nào. Mở một phim rồi bấm «Theo dõi» để biết khi có tập mới."];
    } else {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"dd/MM HH:mm";
        for (NSDictionary *h in [CBPrefs history]) {
            if (!CBStr(h, @"filmUrl") || !CBStr(h, @"epUrl")) continue;
            NSMutableDictionary *it = [@{@"url": CBStr(h, @"filmUrl"), @"title": CBStr(h, @"title") ?: @"", @"epUrl": CBStr(h, @"epUrl"),
                                         @"kind": @"continue"} mutableCopy];
            if (CBStr(h, @"poster")) it[@"poster"] = CBStr(h, @"poster");
            double t = CBNum(h, @"time", 0);
            NSString *when = t > 0 ? [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:t / 1000.0]] : nil;
            it[@"sub"] = when ? [NSString stringWithFormat:@"%@ · %@", CBStr(h, @"epTitle") ?: @"", when] : (CBStr(h, @"epTitle") ?: @"");
            [items addObject:it];
        }
        [self showMessage:items.count ? nil : @"Chưa xem phim nào."];
    }
    _sections = items.count ? @[@{@"items": items}] : @[];
    [_cv reloadData];
}

/// Mở trang theo dõi: kiểm lại số tập của từng phim (3 phim cùng lúc), như FollowsPage của bản Windows
- (void)checkFollows {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *f in [CBPrefs follows]) if (CBStr(f, @"filmUrl")) [urls addObject:CBStr(f, @"filmUrl")];
    if (_checking || !urls.count) return;
    _checking = YES;
    [_spinner startAnimating];
    long long t0 = CBNowMs();
    __block NSUInteger next = 0, done = 0;
    __weak CBGridViewController *weakSelf = self;
    __block void (^one)(void);
    void (^run)(void) = ^{
        if (next >= urls.count) return;
        NSString *url = urls[next++];
        [CBCore call:@"site.detail" args:@{@"url": url} done:^(id ok, NSString *err) {
            if (CBIsDict(ok)) {
                [CBPrefs updateFollow:url count:CBDetailEpisodeCount(ok) latest:CBStr(CBDetailLatestEpisode(ok), @"title") seen:NO];
            }
            CBGridViewController *s = weakSelf;
            if (++done >= urls.count) {
                CBLog(@"Kiểm tập mới %lu phim theo dõi: %lld ms", (unsigned long)urls.count, CBNowMs() - t0);
                one = nil;  // bỏ vòng giữ khối
                if (s) {
                    s->_checking = NO;
                    [s->_spinner stopAnimating];
                    [s rebuildSpecial];
                }
                return;
            }
            if (one) one();
        }];
    };
    one = run;
    for (int i = 0; i < 3; i++) run();
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || !_special) return;
    NSIndexPath *ip = [_cv indexPathForItemAtPoint:[g locationInView:_cv]];
    if (!ip || ip.section >= (NSInteger)_sections.count) return;
    [self askRemove:CBArr(_sections[ip.section], @"items")[ip.item]];
}

/// Nhấn giữ: bỏ theo dõi / xoá khỏi lịch sử (gỡ lỗi: lệnh «pick <số>» trên màn này)
- (void)askRemove:(NSDictionary *)item {
    _longItem = item;
    BOOL follows = [_special isEqualToString:@"follows"];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:CBStr(item, @"title") delegate:self cancelButtonTitle:@"Huỷ"
                                         destructiveButtonTitle:follows ? @"Bỏ theo dõi" : @"Xoá khỏi lịch sử" otherButtonTitles:nil];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index != sheet.destructiveButtonIndex || !_longItem) return;
    NSString *url = CBStr(_longItem, @"url");
    BOOL follows = [_special isEqualToString:@"follows"];
    if (follows) [CBPrefs unfollow:url];
    else [CBPrefs removeHistory:url];
    CBLog(@"%@: %@", follows ? @"Bỏ theo dõi" : @"Xoá khỏi lịch sử", CBStr(_longItem, @"title"));
    _longItem = nil;
    [self rebuildSpecial];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 14;
    layout.minimumInteritemSpacing = 8;
    _cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _cv.backgroundColor = [CBTheme bg];
    _cv.alwaysBounceVertical = YES;
    _cv.dataSource = self;
    _cv.delegate = self;
    _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_cv registerClass:[CBPosterCell class] forCellWithReuseIdentifier:@"poster"];
    [_cv registerClass:[CBGridHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"head"];
    [self.view addSubview:_cv];

    _message = [CBTheme messageLabel];
    _message.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_message];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_spinner];
    _retryButton = [CBTheme button:@"Thử lại" primary:YES];
    [_retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.hidden = YES;
    [self.view addSubview:_retryButton];

    if (_searchMode) {
        _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _searchBar.placeholder = @"Tên phim (tìm trên mọi trang)";
        _searchBar.delegate = self;
        _searchBar.tintColor = [CBTheme surface];
        // Tên phim gõ không dấu / tên riêng: không để bàn phím tự sửa / tự viết hoa
        _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
        _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self.view addSubview:_searchBar];
        _cv.frame = CGRectMake(0, 44, self.view.bounds.size.width, self.view.bounds.size.height - 44);
        [self showMessage:@"Gõ tên phim rồi bấm Tìm."];
    } else if (_listUrl) {
        [self loadPage:_listUrl];
    }
    if (_special) {
        [_cv addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
        [self rebuildSpecial];
        if ([_special isEqualToString:@"follows"]) [self checkFollows];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_searchMode && !_sections.count && !_loading) [_searchBar becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = _searchBar ? 44 : 0;
    _message.frame = CGRectMake(20, top + 30, self.view.bounds.size.width - 40, 100);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, top + 40);
    CGSize rs = [_retryButton sizeThatFits:CGSizeMake(300, 44)];
    _retryButton.frame = CGRectMake((self.view.bounds.size.width - rs.width - 40) / 2, top + 140, rs.width + 40, 44);
    [_cv.collectionViewLayout invalidateLayout];
}

- (void)showMessage:(NSString *)text {
    _message.text = text;
    _message.hidden = text == nil;
    _retryButton.hidden = YES;
}

/// Lỗi tải (danh sách trống): kèm nút «Thử lại» — trước phải lùi ra rồi vào lại
- (void)showError:(NSString *)text {
    [self showMessage:text];
    _retryButton.hidden = NO;
}

- (void)retryTapped {
    _retryButton.hidden = YES;
    if (_searchMode) [self search:_lastQuery ?: _searchBar.text];
    else if (_listUrl) [self loadPage:_listUrl];
}

#pragma mark - Tải

/// FilmPage của lõi: {films, nextUrl, sections: [{title, films}]}
- (NSArray *)sectionsOfPage:(NSDictionary *)page {
    NSMutableArray *out = [NSMutableArray array];
    for (id s in CBArr(page, @"sections") ?: @[]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id f in CBArr(s, @"films") ?: @[]) [items addObject:CBItemFromFilm(f)];
        if (items.count) [out addObject:@{@"title": CBStr(s, @"title") ?: @"", @"items": items}];
    }
    if (!out.count) {
        NSMutableArray *items = [NSMutableArray array];
        for (id f in CBArr(page, @"films") ?: @[]) [items addObject:CBItemFromFilm(f)];
        if (items.count) [out addObject:@{@"items": items}];
    }
    return out;
}

- (void)loadPage:(NSString *)url {
    if (_loading) return;
    _loading = YES;
    NSInteger t = ++_token;
    if (!_sections.count) {
        [self showMessage:nil];
        [_spinner startAnimating];
    }
    // «imdb:top» = trang «Điểm IMDb cao» của lõi (các nhóm phim KKPhim xếp theo IMDb), không phải địa chỉ trang
    BOOL imdb = [url isEqualToString:@"imdb:top"];
    long long t0 = CBNowMs();
    [CBCore call:imdb ? @"imdb.page" : @"site.list" args:imdb ? @{@"kids": @([CBPrefs kids])} : @{@"url": url}
            done:^(id ok, NSString *err) {
        if (imdb) CBLog(@"Điểm IMDb cao: %@ sau %lld ms", CBIsDict(ok) ? [NSString stringWithFormat:@"%lu nhóm",
                         (unsigned long)CBArr(ok, @"sections").count] : [@"LỖI " stringByAppendingString:err ?: @"?"], CBNowMs() - t0);
        if (t != self->_token) return;
        self->_loading = NO;
        [self->_spinner stopAnimating];
        if (!CBIsDict(ok)) {
            if (!self->_sections.count) {
                [self showError:[NSString stringWithFormat:@"Không tải được danh sách.\n%@", err ?: @""]];
            } else {
                // Trang sau lỗi: báo một lần, khỏi tự thử lại liên tục mỗi lần cuộn (thử lại sau 5 giây)
                self->_pageFailedAt = CBNowMs();
                [CBTheme toast:[NSString stringWithFormat:@"Không tải được trang sau: %@", err ?: @"lỗi mạng"]];
            }
            return;
        }
        NSArray *more = [self sectionsOfPage:ok];
        NSString *next = CBStr(ok, @"nextUrl");
        self->_nextUrl = [next isEqualToString:url] ? nil : next;
        if (self->_sections.count == 1 && more.count == 1 && !CBStr(self->_sections[0], @"title")) {
            // Trang sau của cùng danh sách: nối vào
            NSArray *items = [CBArr(self->_sections[0], @"items") arrayByAddingObjectsFromArray:CBArr(more[0], @"items")];
            self->_sections = @[@{@"items": items}];
        } else {
            self->_sections = [(self->_sections ?: @[]) arrayByAddingObjectsFromArray:more];
        }
        [self showMessage:self->_sections.count ? nil : @"Danh sách trống."];
        [self->_cv reloadData];
    }];
}

- (void)search:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    _lastQuery = q;
    _searchBar.text = q;
    [_searchBar resignFirstResponder];
    NSInteger t = ++_token;
    _sections = nil;
    [_cv reloadData];
    [self showMessage:nil];
    [_spinner startAnimating];
    [self showMessage:[NSString stringWithFormat:@"Đang tìm «%@» trên mọi trang…", q]];
    _loading = YES;
    long long t0 = CBNowMs();
    CBLog(@"Tìm «%@»", q);
    [CBCore call:@"site.searchAll" args:@{@"query": q} done:^(id ok, NSString *err) {
        if (t != self->_token) return;
        self->_loading = NO;
        [self->_spinner stopAnimating];
        self->_sections = CBIsDict(ok) ? [self dropJunk:[self sectionsOfPage:ok] query:q] : @[];
        NSUInteger n = 0;
        for (NSDictionary *s in self->_sections) n += CBArr(s, @"items").count;
        CBLog(@"Tìm «%@»: %lu phim, %lu nhóm sau %lld ms%@", q, (unsigned long)n, (unsigned long)self->_sections.count,
              CBNowMs() - t0, err ? [@" — LỖI " stringByAppendingString:err] : @"");
        if (!self->_sections.count && err) [self showError:[NSString stringWithFormat:@"Không tìm được.\n%@", err]];
        else [self showMessage:self->_sections.count ? nil : [NSString stringWithFormat:@"Không thấy phim nào tên «%@».", q]];
        [self->_cv reloadData];
    }];
}

/// Chữ thường, bỏ dấu (cả «đ»), dấu gạch → cách — để so tên phim với từ khoá
static NSString *CBFold(NSString *s) {
    NSString *f = [[s ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];
    f = [f stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
    return [[f stringByReplacingOccurrencesOfString:@"-" withString:@" "] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

/// Có trang tìm hỏng trả cả loạt phim không liên quan (phimmois.fun: ~60 phim mới nhất cho mọi từ khoá). Thận trọng để không bỏ
/// nhầm phim tìm theo tên gốc / tên tiếng Anh (tên hiển thị là tên Việt):
/// - trang kiểu «next» (họ phimmois — tìm kiếm đang hỏng) mà gần như không phim nào khớp từ khoá → chỉ giữ phim khớp;
/// - trang nào trả từ 30 phim trở lên mà không phim nào khớp → bỏ cả nhóm;
/// - còn lại giữ nguyên.
- (NSArray *)dropJunk:(NSArray *)sections query:(NSString *)q {
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [CBFold(q) componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (w.length) [words addObject:w];
    }
    if (!words.count) return sections;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in sections) {
        NSArray *items = CBArr(s, @"items") ?: @[];
        NSMutableArray *hits = [NSMutableArray array];
        for (NSDictionary *it in items) {
            NSString *slug = [[NSURL URLWithString:CBStr(it, @"url") ?: @""].path lastPathComponent];
            NSString *hay = [NSString stringWithFormat:@"%@ %@", CBFold(CBStr(it, @"title")), CBFold(slug)];
            BOOL all = YES;
            for (NSString *w in words) if ([hay rangeOfString:w].location == NSNotFound) { all = NO; break; }
            if (all) [hits addObject:it];
        }
        NSString *host = items.count ? CBHostOf(CBStr(items[0], @"url") ?: @"") : nil;
        BOOL next = host && [[CBCore sync:@"next.isKnown" args:@{@"url": [@"https://" stringByAppendingString:host]}] boolValue];
        BOOL junk = (next && items.count >= 8 && hits.count * 5 <= items.count) || (items.count >= 30 && !hits.count);
        if (!junk) {
            [out addObject:s];
            continue;
        }
        CBLog(@"Tìm «%@»: nhóm %@ trả %lu phim, chỉ %lu khớp từ khoá — bỏ phần không liên quan", q, CBStr(s, @"title"),
              (unsigned long)items.count, (unsigned long)hits.count);
        if (hits.count) {
            NSMutableDictionary *keep = [s mutableCopy];
            keep[@"items"] = hits;
            // Tiêu đề nhóm của lõi ghi số phim («phimmois.fun — 60 phim»): đếm lại theo số còn giữ
            NSString *title = CBStr(s, @"title") ?: @"";
            NSRegularExpression *count = [NSRegularExpression regularExpressionWithPattern:@"\\d+ phim" options:0 error:NULL];
            keep[@"title"] = [count stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length)
                                                         withTemplate:[NSString stringWithFormat:@"%lu phim", (unsigned long)hits.count]];
            [out addObject:keep];
        }
    }
    return out;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)sv {
    [_searchBar resignFirstResponder];  // cuộn kết quả thì cất bàn phím
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self search:searchBar.text];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (_nextUrl && !_loading && CBNowMs() - _pageFailedAt > 5000 &&
        sv.contentOffset.y + sv.bounds.size.height > sv.contentSize.height - 400) {
        [self loadPage:_nextUrl];
    }
}

#pragma mark - Lưới

- (CGFloat)cellWidth {
    CGFloat w = _cv.bounds.size.width - 24;
    CGFloat target = [CBPosterCell defaultWidth];
    // iPhone dọc: 3 cột (bề ngang 296 điểm chỉ vừa 2 ô cỡ mặc định — ô quá to, phải cuộn nhiều)
    NSInteger cols = MAX(3, (NSInteger)floor((w + 8) / (target + 8)));
    return floor((w - 8 * (cols - 1)) / cols);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    return _sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return CBArr(_sections[section], @"items").count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return [CBPosterCell sizeForWidth:[self cellWidth]];
}

- (UIEdgeInsets)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)s {
    return UIEdgeInsetsMake(8, 12, 16, 12);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)s {
    return CBStr(_sections[s], @"title") ? CGSizeMake(cv.bounds.size.width, 36) : CGSizeZero;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)ip {
    CBGridHeader *h = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"head" forIndexPath:ip];
    h.label.text = CBStr(_sections[ip.section], @"title");
    return h;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBPosterCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"poster" forIndexPath:ip];
    [cell setItem:CBArr(_sections[ip.section], @"items")[ip.item]];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *item = CBArr(_sections[ip.section], @"items")[ip.item];
    if ([CBStr(item, @"kind") isEqualToString:@"continue"]) {
        // Lịch sử: bấm là xem tiếp ngay (như «Xem tiếp» ở trang chủ)
        CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:CBStr(item, @"url") detail:nil
                                                                          episode:CBStr(item, @"epUrl") resume:YES];
        [self presentViewController:p animated:YES completion:nil];
        return;
    }
    [self.navigationController pushViewController:[[CBDetailViewController alloc] initWithItem:item] animated:YES];
}

@end
