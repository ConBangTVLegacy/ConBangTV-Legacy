#import "CBNavController.h"
#import "CBGlass.h"
#import "CBRootViewController.h"
#import "CBTheme.h"
#import <objc/runtime.h>

static char kGlassedKey;

@interface CBRootViewController (CBNav)
- (void)topChanged:(UINavigationController *)nav animated:(BOOL)animated;
- (void)willLeave:(UIViewController *)vc;
- (void)navWillShow:(UIViewController *)vc;
@end

@implementation CBNavController

- (instancetype)initWithRootViewController:(UIViewController *)root {
    if ((self = [super initWithRootViewController:root])) {
        self.delegate = self;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    if ([self.navigationBar respondsToSelector:@selector(setTranslucent:)] && [[UIDevice currentDevice].systemVersion floatValue] >= 7) {
        // iOS 7+: thanh đặc → màn đẩy vào nằm dưới thanh như iOS 5 / 6 (không phải chỉnh lề trên từng màn)
        self.navigationBar.translucent = NO;
    }
    if ([self respondsToSelector:@selector(interactivePopGestureRecognizer)]) {
        self.interactivePopGestureRecognizer.delegate = self;   // nút quay lại tự vẽ vẫn vuốt mép trái để lùi được (iOS 7+)
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return self.viewControllers.count > 1;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [CBTheme isPad] ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

// iOS 5 hỏi hàm này (iOS 6 dùng supportedInterfaceOrientations): UINavigationController của iOS 5 hỏi màn trên cùng —
// các màn trong thanh điều hướng không tự khai báo chiều nên quyết ở đây, giống iOS 6
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return ([self supportedInterfaceOrientations] & (1u << o)) != 0;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [CBTheme isPad] ? [UIApplication sharedApplication].statusBarOrientation : UIInterfaceOrientationPortrait;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Đổi màn

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    [vc view];   // nút của màn đặt trong viewDidLoad
    if ([vc respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) vc.automaticallyAdjustsScrollViewInsets = NO;
    BOOL hide = self.tabRoot && vc == self.viewControllers.firstObject;
    if (self.navigationBarHidden != hide) [self setNavigationBarHidden:hide animated:animated];
    [CBNavController glassify:vc inNav:self];
    // Màn đang rời (bị lùi ra thì sắp giải phóng): bỏ theo dõi danh sách của nó — mọi kiểu đổi màn (đẩy, lùi, lùi về gốc…)
    CBRootViewController *root = [CBRootViewController current];
    if (root.content == self) [root navWillShow:vc];
}

- (void)navigationController:(UINavigationController *)nav didShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (self.tabRoot) [[CBRootViewController current] topChanged:self animated:animated];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    [[CBRootViewController current] willLeave:self.topViewController];
    return [super popViewControllerAnimated:animated];
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated {
    for (UIViewController *c in self.viewControllers) if (c != self.viewControllers.firstObject) [[CBRootViewController current] willLeave:c];
    return [super popToRootViewControllerAnimated:animated];
}

- (NSArray *)popToViewController:(UIViewController *)target animated:(BOOL)animated {
    NSUInteger i = [self.viewControllers indexOfObject:target];
    if (i != NSNotFound) {
        for (NSUInteger k = i + 1; k < self.viewControllers.count; k++) [[CBRootViewController current] willLeave:self.viewControllers[k]];
    }
    return [super popToViewController:target animated:animated];
}

- (void)backTapped {
    [self popViewControllerAnimated:YES];
}

#pragma mark - Nút kính

/// Chữ quen thuộc → biểu tượng (nút tròn); chữ khác giữ chữ trên viên kính
static NSString *CBIconForTitle(NSString *t) {
    static NSDictionary *map;
    if (!map) map = @{@"Cài đặt": @"gear", @"Đóng": @"close", @"Xong": @"check", @"Tìm": @"search", @"Thêm": @"plus", @"Sửa": @"pencil"};
    return t ? map[t] : nil;
}

+ (UIBarButtonItem *)glassItem:(UIBarButtonItem *)item {
    if (!item || item.customView || objc_getAssociatedObject(item, &kGlassedKey)) return item;
    NSString *icon = CBIconForTitle(item.title);
    CBPillButton *b;
    if (icon) {
        b = [CBPillButton circle:icon diameter:36];
        b.accessibilityLabel = item.title;
    } else if (item.title.length) {
        b = [CBPillButton pill:item.title style:CBPillGlass];
        b.titleLabel.font = [CBTheme medium:15];
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        CGSize s = [b sizeThatFits:CGSizeMake(220, 36)];
        b.frame = CGRectMake(0, 0, MAX(52, s.width), 36);
    } else if (item.image) {
        b = [CBPillButton circle:nil diameter:36];
        [b setImage:item.image forState:UIControlStateNormal];
    } else {
        return item;
    }
    if (item.target && item.action) [b addTarget:item.target action:item.action forControlEvents:UIControlEventTouchUpInside];
    b.enabled = item.enabled;
    UIBarButtonItem *g = [[UIBarButtonItem alloc] initWithCustomView:b];
    g.tag = item.tag;
    objc_setAssociatedObject(g, &kGlassedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return g;
}

/// iOS 5 / 6 đặt nút tự vẽ sát mép (5 điểm) — chèn khoảng trống cho cách mép ~10 điểm như bản mẫu
+ (NSArray *)withEdgeSpace:(NSArray *)items {
    if (!items.count || [[UIDevice currentDevice].systemVersion floatValue] >= 7) return items;
    UIBarButtonItem *first = items.firstObject;
    if (first.width > 0 && !first.customView && objc_getAssociatedObject(first, &kGlassedKey)) return items;
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    space.width = 5;
    objc_setAssociatedObject(space, &kGlassedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [@[space] arrayByAddingObjectsFromArray:items];
}

+ (BOOL)alreadyGlass:(NSArray *)items {
    for (UIBarButtonItem *i in items) if (!objc_getAssociatedObject(i, &kGlassedKey)) return NO;
    return YES;
}

+ (void)glassify:(UIViewController *)vc inNav:(UINavigationController *)nav {
    UINavigationItem *ni = vc.navigationItem;
    NSArray *right = ni.rightBarButtonItems;
    if (right.count && ![self alreadyGlass:right]) {
        NSMutableArray *out = [NSMutableArray array];
        for (UIBarButtonItem *i in right) {
            if (objc_getAssociatedObject(i, &kGlassedKey) && !i.customView) continue;   // khoảng trống đã chèn
            [out addObject:[self glassItem:i]];
        }
        ni.rightBarButtonItems = [self withEdgeSpace:out];
    }
    NSArray *left = ni.leftBarButtonItems;
    if (left.count && ![self alreadyGlass:left]) {
        NSMutableArray *out = [NSMutableArray array];
        for (UIBarButtonItem *i in left) {
            if (objc_getAssociatedObject(i, &kGlassedKey) && !i.customView) continue;
            [out addObject:[self glassItem:i]];
        }
        ni.leftBarButtonItems = [self withEdgeSpace:out];
    } else if (!left.count && !ni.hidesBackButton && nav.viewControllers.count > 1 && vc != nav.viewControllers.firstObject &&
               [nav isKindOfClass:[CBNavController class]]) {
        // Nút quay lại tròn kính «‹» thay nút mũi tên của hệ thống
        CBPillButton *b = [CBPillButton circle:@"back" diameter:36];
        [b setIcon:@"back" size:18];
        b.accessibilityLabel = @"Quay lại";
        [b addTarget:nav action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
        UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithCustomView:b];
        objc_setAssociatedObject(back, &kGlassedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ni.leftBarButtonItems = [self withEdgeSpace:@[back]];
    }
}

@end
