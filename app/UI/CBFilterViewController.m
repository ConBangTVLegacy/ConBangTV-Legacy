#import "CBFilterViewController.h"
#import "CBCore.h"
#import "CBGridViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"

@implementation CBFilterViewController {
    BOOL _genres;
    NSArray *_items;  // [{title, url}]
    NSMutableArray *_buttons;
    UIScrollView *_scroll;
    UILabel *_message;
    UIActivityIndicatorView *_spinner;
    UIButton *_retryButton;
}

+ (BOOL)isApi:(NSString *)base {
    id v = [CBCore sync:@"api.isKnown" args:@{@"url": base ?: @""}];
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

+ (BOOL)isNext:(NSString *)base {
    id v = [CBCore sync:@"next.isKnown" args:@{@"url": base ?: @""}];
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

+ (BOOL)available {
    NSString *b = [CBPrefs baseUrl];
    return [self isApi:b] || [self isNext:b];
}

/// Tên bộ lọc thứ hai của trang đang chọn: «Quốc gia»; dexter.pw (phim Âu Mỹ) lọc theo thập niên
+ (NSString *)secondName {
    return [CBHostOf([CBPrefs baseUrl] ?: @"") isEqualToString:@"dexter.pw"] ? @"Thập niên" : @"Quốc gia";
}

- (instancetype)initGenres:(BOOL)genres {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _genres = genres;
        // Bộ lọc là của trang phim đang chọn (cả khi trang chủ tổng hợp) — ghi tên trang cho khỏi nhầm
        NSString *host = [[NSURL URLWithString:[CBPrefs baseUrl] ?: @""].host stringByReplacingOccurrencesOfString:@"www." withString:@""];
        self.title = [NSString stringWithFormat:@"%@%@", genres ? @"Thể loại" : [CBFilterViewController secondName],
                                                host.length ? [@" · " stringByAppendingString:host] : @""];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];
    _message = [CBTheme messageLabel];
    [self.view addSubview:_message];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
    _buttons = [NSMutableArray array];
    _retryButton = [CBTheme button:@"Thử lại" primary:YES];
    [_retryButton addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.hidden = YES;
    [self.view addSubview:_retryButton];
    [self load];
}

- (void)apply:(id)f error:(NSString *)err {
    [_spinner stopAnimating];
    NSArray *list = CBArr(f, _genres ? @"genres" : @"countries") ?: @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id c in list) if (CBStr(c, @"title") && CBStr(c, @"url")) [items addObject:c];
    _items = items;
    _message.text = items.count ? nil : [NSString stringWithFormat:@"Không tải được danh sách.%@", err ? [@"\n" stringByAppendingString:err] : @""];
    _retryButton.hidden = items.count > 0;
    [self.view setNeedsLayout];
    CBLog(@"%@ của %@: %lu mục%@", self.title, [CBPrefs baseUrl], (unsigned long)items.count, err ? [@" — LỖI " stringByAppendingString:err] : @"");
    for (UIView *b in _buttons) [b removeFromSuperview];
    [_buttons removeAllObjects];
    for (NSUInteger i = 0; i < items.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        b.titleLabel.font = [CBTheme font:[CBTheme isPad] ? 17 : 15];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.7;
        [b setTitle:CBStr(items[i], @"title") forState:UIControlStateNormal];
        [b setTitleColor:[CBTheme text] forState:UIControlStateNormal];
        [b setBackgroundImage:[CBTheme imageWithColor:[CBTheme surface]] forState:UIControlStateNormal];
        [b setBackgroundImage:[CBTheme imageWithColor:[CBTheme surface2]] forState:UIControlStateHighlighted];
        b.layer.cornerRadius = 10;
        b.clipsToBounds = YES;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:b];
        [_buttons addObject:b];
    }
    [self.view setNeedsLayout];
}

- (void)load {
    _retryButton.hidden = YES;
    _message.text = nil;
    NSString *base = [CBPrefs baseUrl];
    if ([CBFilterViewController isApi:base]) {
        [self apply:[CBCore sync:@"api.filters" args:@{@"baseUrl": base}] error:nil];
        return;
    }
    [_spinner startAnimating];
    [CBCore call:@"next.filters" args:@{@"baseUrl": base} done:^(id ok, NSString *err) {
        [self apply:ok error:err];
    }];
}

/// Lưới nút đều cột (iPhone dọc 2 cột, iPad 4–5 cột)
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    _message.frame = CGRectMake(20, 30, w - 40, 100);
    _spinner.center = CGPointMake(w / 2, 40);
    CGSize rs = [_retryButton sizeThatFits:CGSizeMake(300, 44)];
    _retryButton.frame = CGRectMake((w - rs.width - 40) / 2, 140, rs.width + 40, 44);
    CGFloat pad = 12, gap = 10, bh = [CBTheme isPad] ? 52 : 46;
    NSInteger cols = MAX(2, (NSInteger)floor((w - 2 * pad + gap) / ([CBTheme isPad] ? 170 : 140)));
    CGFloat bw = floor((w - 2 * pad - gap * (cols - 1)) / cols);
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        NSInteger r = (NSInteger)i / cols, c = (NSInteger)i % cols;
        [_buttons[i] setFrame:CGRectMake(pad + c * (bw + gap), pad + r * (bh + gap), bw, bh)];
    }
    NSInteger rows = ((NSInteger)_buttons.count + cols - 1) / cols;
    _scroll.contentSize = CGSizeMake(w, pad * 2 + rows * (bh + gap));
}

- (void)tapped:(UIButton *)b {
    [self openAt:b.tag];
}

- (void)openAt:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_items.count) return;
    NSDictionary *c = _items[i];
    [self.navigationController pushViewController:[[CBGridViewController alloc] initWithListUrl:CBStr(c, @"url") title:CBStr(c, @"title")]
                                         animated:YES];
}

@end
