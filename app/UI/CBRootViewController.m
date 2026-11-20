#import "CBRootViewController.h"
#import "CBGlass.h"
#import "CBGridViewController.h"
#import "CBHomeViewController.h"
#import "CBIcon.h"
#import "CBLog.h"
#import "CBNavController.h"
#import "CBSettingsViewController.h"
#import "CBTVViewController.h"
#import "CBTheme.h"

static void *kOffsetKVO = &kOffsetKVO;
static const CGFloat kBarH = 52, kGap = 8, kSide = 10;   // iPhone: thanh tab / nút tìm / thanh thu nhỏ cao 52, cách nhau 8
static const CGFloat kPadBarH = 46;                     // iPad: thanh tab ở mép trên

static NSString *CBTabTitle(NSInteger i) {
    return @[@"Trang chủ", @"Truyền hình", @"Theo dõi", @"Cài đặt"][i];
}

static NSString *CBTabIcon(NSInteger i) {
    return @[@"home", @"tv", @"bookmark", @"gear"][i];
}

#pragma mark - Một ô của thanh tab

@interface CBTabItem : UIControl
@property (nonatomic) NSInteger index;
@property (nonatomic) BOOL on;
@property (nonatomic) BOOL badge;
@end

@implementation CBTabItem {
    UIImageView *_icon;
    UILabel *_label;
    UIView *_dot;
}

- (instancetype)initWithIndex:(NSInteger)i {
    if ((self = [super initWithFrame:CGRectZero])) {
        _index = i;
        BOOL pad = [CBTheme isPad];
        if (!pad) {
            _icon = [[UIImageView alloc] init];
            _icon.contentMode = UIViewContentModeCenter;
            [self addSubview:_icon];
        }
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.text = i < 4 ? CBTabTitle(i) : @"";
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.8;
        [self addSubview:_label];
        _dot = [[UIView alloc] init];
        _dot.hidden = YES;
        [self addSubview:_dot];
        self.accessibilityLabel = _label.text;
        [self update];
    }
    return self;
}

- (void)update {
    UIColor *c = _on ? [CBTheme accent] : CBRGB(0xE4E8EE);
    _label.textColor = c;
    _label.font = [CBTheme isPad] ? (_on ? [CBTheme bold:15] : [CBTheme medium:15]) : [CBTheme medium:10];
    if (_icon && _index < 4) {
        // Tab đang chọn: biểu tượng tô kín (trừ bánh răng — tô kín thì mất lỗ giữa)
        _icon.image = [CBIcon named:CBTabIcon(_index) size:21 color:c filled:_on && _index != 3];
    }
    if (_dot.hidden == _badge) {
        _dot.hidden = !_badge;
        if (_badge && ![(UIImageView *)_dot.subviews.firstObject image]) {
            UIImageView *img = [[UIImageView alloc] initWithImage:[CBTheme imageWithColor:[CBTheme accent] radius:4]];
            img.frame = CGRectMake(0, 0, 8, 8);
            [_dot addSubview:img];
        }
    }
}

- (void)setOn:(BOOL)on {
    _on = on;
    [self update];
}

- (void)setBadge:(BOOL)badge {
    _badge = badge;
    [self update];
}

- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    self.alpha = h ? 0.6 : 1;
}

- (CGFloat)padWidth {
    return ceil([_label.text sizeWithFont:[CBTheme bold:15]].width) + 36;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    if ([CBTheme isPad]) {
        _label.frame = self.bounds;
        _dot.frame = CGRectMake(s.width - 14, 7, 8, 8);
        return;
    }
    _icon.frame = CGRectMake(0, round((s.height - 35) / 2), s.width, 21);
    _label.frame = CGRectMake(1, CGRectGetMaxY(_icon.frame) + 2, s.width - 2, 12);
    _dot.frame = CGRectMake(round(s.width / 2 + 9), _icon.frame.origin.y - 1, 8, 8);
}

@end

#pragma mark - Thanh tab

@interface CBTabBar : UIView
@property (nonatomic) NSInteger selected;   // -1 = không tab nào (đang ở Tìm kiếm)
@property (nonatomic) BOOL compact;
@property (nonatomic, copy) void (^onTap)(NSInteger index);   // 0…3 tab, 4 = tìm (iPad), -1 = nút thu gọn
- (CGFloat)padWidth;
- (CBTabItem *)item:(NSInteger)i;
@end

@implementation CBTabBar {
    CBGlassView *_glass;
    UIImageView *_pill;
    NSMutableArray *_items;
    UIImageView *_compactIcon;
    UIButton *_padSearch;
    UIView *_padLine;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = NO;
        _glass = [[CBGlassView alloc] initWithFrame:self.bounds radius:-1 style:CBGlassBar];
        [self addSubview:_glass];
        _pill = [[UIImageView alloc] init];
        [self addSubview:_pill];
        _items = [NSMutableArray array];
        for (NSInteger i = 0; i < 4; i++) {
            CBTabItem *it = [[CBTabItem alloc] initWithIndex:i];
            [it addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:it];
            [_items addObject:it];
        }
        if ([CBTheme isPad]) {
            _padLine = [[UIView alloc] init];
            _padLine.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
            [self addSubview:_padLine];
            _padSearch = [UIButton buttonWithType:UIButtonTypeCustom];
            _padSearch.accessibilityLabel = @"Tìm kiếm";
            [_padSearch addTarget:self action:@selector(searchTapped) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:_padSearch];
        } else {
            _compactIcon = [[UIImageView alloc] init];
            _compactIcon.contentMode = UIViewContentModeCenter;
            _compactIcon.alpha = 0;
            [self addSubview:_compactIcon];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(compactTapped)];
            [_compactIcon addGestureRecognizer:tap];
        }
        _selected = 0;
        [self updateSelection];
    }
    return self;
}

- (CBTabItem *)item:(NSInteger)i {
    return i >= 0 && i < (NSInteger)_items.count ? _items[i] : nil;
}

- (void)itemTapped:(CBTabItem *)it {
    if (self.onTap) self.onTap(it.index);
}

- (void)searchTapped {
    if (self.onTap) self.onTap(4);
}

- (void)compactTapped {
    if (self.onTap) self.onTap(-1);
}

- (void)setSelected:(NSInteger)selected {
    _selected = selected;
    [self updateSelection];
    [self setNeedsLayout];
}

- (void)updateSelection {
    for (CBTabItem *it in _items) it.on = it.index == _selected;
    if (_padSearch) {
        UIColor *c = _selected < 0 ? [CBTheme accent] : CBRGB(0xE4E8EE);
        [_padSearch setImage:[CBIcon named:@"search" size:20 color:c] forState:UIControlStateNormal];
    }
    NSInteger s = MAX(0, _selected);
    _compactIcon.image = [CBIcon named:CBTabIcon(s) size:22 color:_selected >= 0 ? [CBTheme accent] : CBRGB(0xE4E8EE)
                                filled:_selected >= 0 && s != 3];
    _compactIcon.userInteractionEnabled = _compact;
}

- (void)setCompact:(BOOL)compact {
    _compact = compact;
    _compactIcon.userInteractionEnabled = compact;
    [self setNeedsLayout];
}

- (CGFloat)padWidth {
    CGFloat w = 4;
    for (CBTabItem *it in _items) w += [it padWidth] + 2;
    return w + 9 + 40 + 4;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    _glass.frame = self.bounds;
    if ([CBTheme isPad]) {
        CGFloat x = 4, ih = s.height - 8;
        for (CBTabItem *it in _items) {
            CGFloat w = [it padWidth];
            it.frame = CGRectMake(x, 4, w, ih);
            x += w + 2;
        }
        _padLine.frame = CGRectMake(x + 3, round((s.height - 22) / 2), 1, 22);
        _padSearch.frame = CGRectMake(x + 9, 4, 40, ih);
        CBTabItem *on = [self item:_selected];
        _pill.hidden = !on;
        if (on) {
            _pill.image = [CBGlass pill:ih / 2 color:[UIColor colorWithWhite:1 alpha:0.15] sheen:NO];
            _pill.frame = on.frame;
        }
        return;
    }
    CGFloat ih = s.height - 8;
    if (_compact) {
        for (CBTabItem *it in _items) it.alpha = 0;
        _pill.alpha = 0;
        _compactIcon.alpha = 1;
        _compactIcon.frame = self.bounds;
        // ô tab vẫn đặt theo khổ đầy đủ (thu nhỏ dần trong hiệu ứng) — nằm trong khung tròn, đã ẩn
        return;
    }
    _compactIcon.alpha = 0;
    _compactIcon.frame = self.bounds;
    CGFloat iw = (s.width - 8) / _items.count;
    for (CBTabItem *it in _items) {
        it.alpha = 1;
        it.frame = CGRectMake(4 + it.index * iw, 4, iw, ih);
    }
    CBTabItem *on = [self item:_selected];
    _pill.alpha = on ? 1 : 0;
    if (on) {
        _pill.image = [CBGlass pill:ih / 2 color:[UIColor colorWithWhite:1 alpha:0.14] sheen:NO];
        _pill.frame = on.frame;
    }
}

@end

#pragma mark - Màn gốc

@interface CBRootViewController ()
@end

@implementation CBRootViewController {
    NSMutableArray *_navs;          // CBNavController hoặc NSNull, theo CBTab
    CBTab _selected;
    CBTabBar *_tabBar;
    CBPillButton *_searchButton;    // iPhone
    UIView *_bar;                   // thanh thu nhỏ (iPhone)
    CGFloat _barH;
    CGFloat _kbTop;
    UIImageView *_fadeBottom, *_fadeTop;
    BOOL _compact;
    // Danh sách đang theo dõi cuộn (KVO contentOffset). Giữ CHẶT: danh sách bị giải phóng lúc còn bị theo dõi thì KVO của
    // iOS 5 / 6 hỏng → văng khi bố cục (đã gặp: popToRoot từ trang phim, 20/11/2026). Gỡ ngay khi thanh điều hướng đổi màn.
    UIScrollView *_watched;
    CGFloat _lastY;
    BOOL _padBarHidden;
}

+ (CBRootViewController *)current {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    UIWindow *w = [d respondsToSelector:@selector(window)] ? d.window : nil;
    return [w.rootViewController isKindOfClass:self] ? (CBRootViewController *)w.rootViewController : nil;
}

+ (CGFloat)statusInset {
    static int inset = -1;
    if (inset < 0) inset = [[UIDevice currentDevice].systemVersion floatValue] >= 7 ? 20 : 0;
    return inset;
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _navs = [NSMutableArray array];
        for (int i = 0; i <= CBTabSearch; i++) [_navs addObject:[NSNull null]];
        _selected = CBTabHome;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [nc addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [self unwatch];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIViewController *)content {
    return [self navForTab:_selected];
}

- (CBTab)selectedTab {
    return _selected;
}

- (UIView *)bottomBar {
    return _bar;
}

- (CGFloat)keyboardTop {
    return _kbTop;
}

- (BOOL)compact {
    return _compact;
}

- (CBNavController *)navForTab:(CBTab)tab {
    if (tab < 0 || tab > CBTabSearch) return nil;
    id n = _navs[tab];
    if (n != [NSNull null]) return n;
    UIViewController *root;
    switch (tab) {
        case CBTabHome: root = [[CBHomeViewController alloc] init]; break;
        case CBTabTV: root = [[CBTVViewController alloc] init]; break;
        case CBTabFollows: root = [[CBGridViewController alloc] initFollows]; break;
        case CBTabSettings: root = [[CBSettingsViewController alloc] init]; break;
        default: root = [[CBGridViewController alloc] initSearch]; break;
    }
    CBNavController *nav = [[CBNavController alloc] initWithRootViewController:root];
    nav.tabRoot = YES;
    [self addChildViewController:nav];
    [nav didMoveToParentViewController:self];
    _navs[tab] = nav;
    return nav;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    v.backgroundColor = [CBTheme bg];
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL pad = [CBTheme isPad];
    // Mép nội dung mờ dần dưới thanh tab (thay cho nền thanh liền) — ảnh dải màu nền, giãn ngang
    _fadeBottom = [[UIImageView alloc] initWithImage:[self fadeImage:NO]];
    _fadeBottom.userInteractionEnabled = NO;
    _fadeTop = [[UIImageView alloc] initWithImage:[self fadeImage:YES]];
    _fadeTop.userInteractionEnabled = NO;
    [self.view addSubview:_fadeBottom];
    [self.view addSubview:_fadeTop];
    _tabBar = [[CBTabBar alloc] initWithFrame:CGRectMake(0, 0, 200, pad ? kPadBarH : kBarH)];
    __weak CBRootViewController *weakSelf = self;
    _tabBar.onTap = ^(NSInteger i) {
        CBRootViewController *s = weakSelf;
        if (i < 0) [s setCompact:NO animated:YES];
        else [s tabTapped:(CBTab)i];
    };
    [self.view addSubview:_tabBar];
    if (!pad) {
        _searchButton = [CBPillButton circle:@"search" diameter:kBarH];
        [_searchButton setIcon:@"search" size:22];
        _searchButton.accessibilityLabel = @"Tìm kiếm";
        [_searchButton addTarget:self action:@selector(searchTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:_searchButton];
    }
    [self showTab:_selected];
}

- (UIImage *)fadeImage:(BOOL)top {
    UIColor *bg = [CBTheme bg];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [bg getRed:&r green:&g blue:&b alpha:&a];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 64), NO, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {r, g, b, top ? 0.94 : 0, r, g, b, top ? 0.55 : 0.72, r, g, b, top ? 0 : 0.92};
    CGFloat locs[] = {0, 0.6, 1};
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, locs, 3);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), grad, CGPointZero, CGPointMake(0, 64), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Chọn tab

- (void)tabTapped:(CBTab)tab {
    if (tab == _selected) {
        // Chạm lại tab đang chọn: về màn gốc của tab; đang ở màn gốc thì cuộn lên đầu
        CBNavController *nav = [self navForTab:tab];
        if (nav.viewControllers.count > 1) {
            [nav popToRootViewControllerAnimated:YES];
        } else {
            UIScrollView *sv = [self mainScrollOf:nav.topViewController];
            [sv setContentOffset:CGPointMake(0, -sv.contentInset.top) animated:YES];
        }
        return;
    }
    [self selectTab:tab];
}

- (void)searchTapped {
    [self tabTapped:CBTabSearch];
}

- (void)selectTab:(CBTab)tab {
    if (tab < 0 || tab > CBTabSearch || tab == _selected) return;
    [self showTab:tab];
}

- (void)showTab:(CBTab)tab {
    CBNavController *old = _navs[_selected] != [NSNull null] ? _navs[_selected] : nil;
    _selected = tab;
    CBNavController *nav = [self navForTab:tab];
    if (old != nav) [old.view removeFromSuperview];
    if (self.isViewLoaded) {
        nav.view.frame = self.view.bounds;
        nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (nav.view.superview != self.view) [self.view insertSubview:nav.view atIndex:0];
    }
    _tabBar.selected = tab == CBTabSearch ? -1 : tab;
    [_searchButton setIcon:@"search" size:22];
    _searchButton.tintColor = nil;
    [_searchButton setImage:[CBIcon named:@"search" size:22 color:tab == CBTabSearch ? [CBTheme accent] : [CBTheme text]]
                   forState:UIControlStateNormal];
    _compact = NO;
    _tabBar.compact = NO;
    [self topChanged:nav animated:NO];
    [self layoutOverlay];
    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setBadge:(BOOL)on forTab:(CBTab)tab {
    [_tabBar item:tab].badge = on;
}

#pragma mark - Màn trên cùng của tab đổi (CBNavController báo)

/// Thanh điều hướng `nav` vừa đổi màn trên cùng (hoặc vừa được chọn): đặt lề danh sách, theo dõi cuộn, iPad ẩn / hiện thanh tab
- (void)topChanged:(UINavigationController *)nav animated:(BOOL)animated {
    if (nav != [self content]) return;
    UIViewController *top = nav.topViewController;
    [self applyInsetsTo:top];
    [self watch:[self mainScrollOf:top]];
    if ([CBTheme isPad]) {
        BOOL hide = nav.viewControllers.count > 1;
        if (hide != _padBarHidden) {
            _padBarHidden = hide;
            [UIView animateWithDuration:animated ? 0.25 : 0 animations:^{ [self layoutOverlay]; }];
        }
    } else if (_compact) {
        [self setCompact:NO animated:animated];
    }
}

/// Danh sách chính của màn: khai báo qua cbMainScrollView, không thì bảng của UITableViewController / UIScrollView to nhất
- (UIScrollView *)mainScrollOf:(UIViewController *)vc {
    if (!vc || !vc.isViewLoaded) return nil;
    if ([vc respondsToSelector:@selector(cbMainScrollView)]) return [(id<CBTabContent>)vc cbMainScrollView];
    if ([vc isKindOfClass:[UITableViewController class]]) return [(UITableViewController *)vc tableView];
    if ([vc.view isKindOfClass:[UIScrollView class]]) return (UIScrollView *)vc.view;
    UIScrollView *best = nil;
    for (UIView *v in vc.view.subviews) {
        if (![v isKindOfClass:[UIScrollView class]] || v.hidden || [v isKindOfClass:[UITextView class]]) continue;
        if (v.bounds.size.height < vc.view.bounds.size.height * 0.5) continue;
        if (!best || v.bounds.size.height > best.bounds.size.height) best = (UIScrollView *)v;
    }
    return best;
}

- (void)applyInsetsTo:(UIViewController *)vc {
    UIScrollView *sv = [self mainScrollOf:vc];
    if (!sv) return;
    CGFloat bottom = self.overlayBottom;
    UIEdgeInsets i = sv.contentInset;
    if (fabs(i.bottom - bottom) > 0.5) {
        i.bottom = bottom;
        sv.contentInset = i;
        UIEdgeInsets s = sv.scrollIndicatorInsets;
        s.bottom = bottom;
        sv.scrollIndicatorInsets = s;
    }
}

#pragma mark - Thu gọn thanh tab khi cuộn (iPhone)

- (void)watch:(UIScrollView *)sv {
    if (sv == _watched) return;
    [self unwatch];
    if (!sv || [CBTheme isPad]) return;
    _watched = sv;
    _lastY = sv.contentOffset.y;
#ifdef DEBUG
    CBLog(@"[tab] theo dõi cuộn %@ (%@)", NSStringFromClass([sv class]), NSStringFromClass([sv.delegate class]));
#endif
    [sv addObserver:self forKeyPath:@"contentOffset" options:0 context:kOffsetKVO];
}

- (void)unwatch {
    UIScrollView *sv = _watched;
    if (sv) [sv removeObserver:self forKeyPath:@"contentOffset" context:kOffsetKVO];
    _watched = nil;
}

/// Màn sắp bỏ đi (thanh điều hướng báo trước khi đổi màn): thôi theo dõi danh sách của nó trước khi nó bị giải phóng
- (void)willLeave:(UIViewController *)vc {
    if (_watched && [self mainScrollOf:vc] == _watched) [self unwatch];
}

/// Thanh điều hướng sắp hiện `vc` (đẩy, lùi, lùi về gốc…): danh sách đang theo dõi không phải của `vc` thì gỡ ngay
- (void)navWillShow:(UIViewController *)vc {
    if (_watched && [self mainScrollOf:vc] != _watched) [self unwatch];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kOffsetKVO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    UIScrollView *sv = object;
    if (sv != _watched || _kbTop > 0) return;
    CGFloat y = sv.contentOffset.y + sv.contentInset.top;
    // Đoạn nảy ở hai đầu (cuộn quá đáy rồi bật lại) không tính là cuộn lên / xuống
    CGFloat maxY = MAX(0, sv.contentSize.height + sv.contentInset.top + sv.contentInset.bottom - sv.bounds.size.height);
    y = MIN(MAX(y, 0), maxY);
    if (!sv.dragging && !sv.decelerating) {
        _lastY = y;
        return;
    }
    // Chỉ thu gọn khi nội dung đủ dài để cuộn
    BOOL scrollable = sv.contentSize.height > sv.bounds.size.height - sv.contentInset.bottom + 80;
    if (!_compact && scrollable && y > 80 && y - _lastY > 12) {
        [self setCompact:YES animated:YES];
        _lastY = y;
    } else if (_compact && (_lastY - y > 12 || y < 40)) {
        [self setCompact:NO animated:YES];
        _lastY = y;
    } else if ((_compact && y > _lastY) || (!_compact && y < _lastY)) {
        _lastY = y;   // cùng chiều với trạng thái hiện tại: dời mốc theo
    }
}

- (void)setCompact:(BOOL)compact animated:(BOOL)animated {
    if (compact == _compact || [CBTheme isPad]) return;
    _compact = compact;
    _tabBar.compact = compact;
#ifdef DEBUG
    CBLog(@"[tab] thanh tab %@", compact ? @"thu gọn" : @"đầy đủ");
#endif
    [UIView animateWithDuration:animated ? 0.3 : 0 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        [self layoutOverlay];
        [self->_tabBar layoutIfNeeded];
        [self->_bar layoutIfNeeded];
    } completion:nil];
}

#pragma mark - Bố cục

- (CGFloat)overlayBottom {
    if ([CBTheme isPad]) return 0;
    return kGap + kBarH + kGap + (_bar ? _barH + kGap : 0);
}

- (CGFloat)overlayTop {
    CGFloat s = [CBRootViewController statusInset];
    return [CBTheme isPad] && !_padBarHidden ? s + 10 + kPadBarH : s;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutOverlay];
}

- (void)layoutOverlay {
    if (!self.isViewLoaded) return;
    CGRect b = self.view.bounds;
    CGFloat W = b.size.width, H = b.size.height, status = [CBRootViewController statusInset];
    [self.view bringSubviewToFront:_fadeBottom];
    [self.view bringSubviewToFront:_fadeTop];
    if (_bar) [self.view bringSubviewToFront:_bar];
    [self.view bringSubviewToFront:_tabBar];
    if (_searchButton) [self.view bringSubviewToFront:_searchButton];

    if ([CBTheme isPad]) {
        CGFloat w = MIN([_tabBar padWidth], W - 160);
        _tabBar.frame = CGRectMake(round((W - w) / 2), status + 10, w, kPadBarH);
        _tabBar.alpha = _padBarHidden ? 0 : 1;
        _tabBar.userInteractionEnabled = !_padBarHidden;
        // Chỉ làm mờ dưới thanh trạng thái (iOS 7+) — dải cao hơn đè lên nút của đầu trang (ảnh người xem…)
        _fadeTop.frame = CGRectMake(0, 0, W, status + 6);
        _fadeTop.hidden = status == 0;
        _fadeBottom.hidden = YES;
        return;
    }
    BOOL kb = _kbTop > 0;
    CGFloat tabY = H - kGap - kBarH;
    if (_compact) _tabBar.frame = CGRectMake(kSide, tabY, kBarH, kBarH);
    else _tabBar.frame = CGRectMake(kSide, tabY, W - 2 * kSide - kBarH - kGap, kBarH);
    _searchButton.frame = CGRectMake(W - kSide - kBarH, tabY, kBarH, kBarH);
    _tabBar.alpha = _searchButton.alpha = kb ? 0 : 1;
    if (_bar) {
        CGRect f = _compact ? CGRectMake(kSide + kBarH + kGap, tabY, W - 2 * (kSide + kBarH + kGap), _barH)
                            : CGRectMake(kSide, tabY - kGap - _barH, W - 2 * kSide, _barH);
        if (kb) f = CGRectMake(kSide, MIN(H, _kbTop) - kGap - _barH, W - 2 * kSide, _barH);
        // bounds + center (không frame): thanh có thể đang bị kéo (transform) — đặt frame lúc có transform thì lệch
        _bar.bounds = CGRectMake(0, 0, f.size.width, f.size.height);
        _bar.center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    }
    CGFloat ob = kb ? 0 : self.overlayBottom;
    _fadeBottom.hidden = kb;
    _fadeBottom.frame = CGRectMake(0, H - ob - 26, W, ob + 26);
    _fadeTop.frame = CGRectMake(0, 0, W, status + 6);
    _fadeTop.hidden = status == 0;
}

- (void)setBottomBar:(UIView *)bar height:(CGFloat)height {
    if (_bar != bar) [_bar removeFromSuperview];
    _bar = bar;
    _barH = bar ? kBarH : 0;
    if (bar && self.isViewLoaded) [self.view addSubview:bar];
    [self layoutOverlay];
    // Lề dưới của danh sách đổi theo (có / không thanh thu nhỏ)
    [self applyInsetsTo:[(UINavigationController *)[self content] topViewController]];
}

/// Bàn phím hiện / ẩn: thanh tab ẩn dưới bàn phím, thanh thu nhỏ nổi lên trên bàn phím (nội dung giữ nguyên).
/// Rời màn đang gõ (vd Tìm phim → Trang chủ): iOS 6 cho bàn phím trượt NGANG ra theo màn (khung cuối vẫn cùng độ cao, chỉ lệch
/// sang phải) — phải xét bàn phím còn nằm trong màn không, không chỉ xét đỉnh của nó (thanh từng kẹt giữa màn hình).
- (void)keyboardWillChange:(NSNotification *)n {
    if (!self.isViewLoaded || !self.view.window) return;
    CGRect kb = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kb = [self.view convertRect:[self.view.window convertRect:kb fromWindow:nil] fromView:nil];
    CGRect on = CGRectIntersection(kb, self.view.bounds);
    BOOL hide = [n.name isEqualToString:UIKeyboardWillHideNotification] || CGRectIsNull(on) || on.size.width < 1 || on.size.height < 1;
    _kbTop = hide ? 0 : on.origin.y;
    double dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    if (self.keyboardChanged) self.keyboardChanged(dur);
    [UIView animateWithDuration:dur delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self layoutOverlay];
    } completion:nil];
}

#pragma mark - Xoay, thanh trạng thái: theo tab đang chọn

- (BOOL)shouldAutorotate {
    return [[self content] shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [[self content] supportedInterfaceOrientations];
}

// iOS 5 hỏi hàm này (iOS 6 dùng supportedInterfaceOrientations)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return [[self content] shouldAutorotateToInterfaceOrientation:o];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[self content] preferredInterfaceOrientationForPresentation];
}

// iOS 7+: kiểu / ẩn hiện thanh trạng thái do màn bên trong quyết
- (UIViewController *)childViewControllerForStatusBarStyle {
    return [self content];
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return [self content];
}

@end
