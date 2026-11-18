#import "CBRootViewController.h"
#import "CBTheme.h"

@implementation CBRootViewController {
    UIViewController *_content;
    UIView *_bar;
    CGFloat _barH;
    CGFloat _kbTop;   // đỉnh bàn phím trong toạ độ view (0 = không có bàn phím)
}

+ (CBRootViewController *)current {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    UIWindow *w = [d respondsToSelector:@selector(window)] ? d.window : nil;
    return [w.rootViewController isKindOfClass:self] ? (CBRootViewController *)w.rootViewController : nil;
}

- (instancetype)initWithContent:(UIViewController *)content {
    if ((self = [super init])) {
        _content = content;
        [self addChildViewController:content];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [nc addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIViewController *)content {
    return _content;
}

- (UIView *)bottomBar {
    return _bar;
}

- (CGFloat)keyboardTop {
    return _kbTop;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    v.backgroundColor = [CBTheme bg];
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _content.view.frame = self.view.bounds;
    [self.view addSubview:_content.view];
    [_content didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutBar];
}

- (void)layoutBar {
    CGRect b = self.view.bounds;
    CGFloat h = _bar ? _barH : 0;
    _content.view.frame = CGRectMake(0, 0, b.size.width, b.size.height - h);
    if (!_bar) return;
    CGFloat y = b.size.height - h;
    if (_kbTop > 0) y = MIN(y, _kbTop - h);
    // bounds + center (không frame): thanh có thể đang bị kéo (transform) — đặt frame lúc có transform thì lệch
    _bar.bounds = CGRectMake(0, 0, b.size.width, h);
    _bar.center = CGPointMake(b.size.width / 2, y + h / 2);
}

- (void)setBottomBar:(UIView *)bar height:(CGFloat)height {
    if (_bar != bar) [_bar removeFromSuperview];
    _bar = bar;
    _barH = bar ? height : 0;
    if (bar && self.isViewLoaded) [self.view addSubview:bar];
    if (self.isViewLoaded) [self layoutBar];
}

/// Bàn phím hiện / ẩn: thanh ở đáy nổi lên trên bàn phím (nội dung giữ nguyên — các màn của app không tự né bàn phím).
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
    if (!_bar) return;
    [UIView animateWithDuration:dur delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self layoutBar];
    } completion:nil];
}

#pragma mark - Xoay, thanh trạng thái: theo thanh điều hướng

- (BOOL)shouldAutorotate {
    return [_content shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [_content supportedInterfaceOrientations];
}

// iOS 5 hỏi hàm này (iOS 6 dùng supportedInterfaceOrientations)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return [_content shouldAutorotateToInterfaceOrientation:o];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [_content preferredInterfaceOrientationForPresentation];
}

// iOS 7+: kiểu / ẩn hiện thanh trạng thái do màn bên trong quyết
- (UIViewController *)childViewControllerForStatusBarStyle {
    return _content;
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return _content;
}

@end
