#import "CBGridViewController.h"
#import "CBCore.h"
#import "CBDetailViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPosterCell.h"
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
                                    UISearchBarDelegate>
@end

@implementation CBGridViewController {
    NSString *_listUrl;
    NSString *_nextUrl;
    BOOL _searchMode;
    BOOL _loading;
    NSArray *_sections;  // @[@{title, items}]
    NSInteger _token;
    UICollectionView *_cv;
    UISearchBar *_searchBar;
    UILabel *_message;
    UIActivityIndicatorView *_spinner;
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

    if (_searchMode) {
        _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _searchBar.placeholder = @"Tên phim (tìm trên mọi trang)";
        _searchBar.delegate = self;
        _searchBar.tintColor = [CBTheme surface];
        [self.view addSubview:_searchBar];
        _cv.frame = CGRectMake(0, 44, self.view.bounds.size.width, self.view.bounds.size.height - 44);
        [self showMessage:@"Gõ tên phim rồi bấm Tìm."];
    } else if (_listUrl) {
        [self loadPage:_listUrl];
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
    [_cv.collectionViewLayout invalidateLayout];
}

- (void)showMessage:(NSString *)text {
    _message.text = text;
    _message.hidden = text == nil;
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
    if (!_sections.count) [_spinner startAnimating];
    [CBCore call:@"site.list" args:@{@"url": url} done:^(id ok, NSString *err) {
        if (t != self->_token) return;
        self->_loading = NO;
        [self->_spinner stopAnimating];
        if (!CBIsDict(ok)) {
            if (!self->_sections.count) [self showMessage:[NSString stringWithFormat:@"Không tải được danh sách.\n%@", err ?: @""]];
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
        self->_sections = CBIsDict(ok) ? [self sectionsOfPage:ok] : @[];
        NSUInteger n = 0;
        for (NSDictionary *s in self->_sections) n += CBArr(s, @"items").count;
        CBLog(@"Tìm «%@»: %lu phim, %lu nhóm sau %lld ms%@", q, (unsigned long)n, (unsigned long)self->_sections.count,
              CBNowMs() - t0, err ? [@" — LỖI " stringByAppendingString:err] : @"");
        [self showMessage:self->_sections.count ? nil
                                               : (err ? [NSString stringWithFormat:@"Không tìm được.\n%@", err]
                                                      : [NSString stringWithFormat:@"Không thấy phim nào tên «%@».", q])];
        [self->_cv reloadData];
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self search:searchBar.text];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (_nextUrl && !_loading && sv.contentOffset.y + sv.bounds.size.height > sv.contentSize.height - 400) {
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
    [self.navigationController pushViewController:[[CBDetailViewController alloc] initWithItem:item] animated:YES];
}

@end
