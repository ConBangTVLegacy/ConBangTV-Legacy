#import "CBSheet.h"
#import "CBGlass.h"
#import "CBIcon.h"
#import "CBTheme.h"

static NSMutableArray *gSheets;   // bảng đang hiện (giữ sống tới khi đóng hẳn)

static UIWindow *CBSheetMainWindow(void) {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    return [d respondsToSelector:@selector(window)] ? d.window : nil;
}

static UIViewController *CBSheetTopController(void) {
    UIViewController *vc = CBSheetMainWindow().rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

@interface CBSheet ()
- (void)layoutCard;
- (void)outsideTapped;
@end

/// Màn gốc của cửa sổ bảng chọn: xoay như màn đang mở bên dưới
@interface CBSheetController : UIViewController
@property (nonatomic, weak) CBSheet *sheet;
@end

@implementation CBSheetController
- (BOOL)shouldAutorotate {
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *top = CBSheetTopController();
    return top ? [top supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return ([self supportedInterfaceOrientations] & (1u << o)) != 0;
}
- (UIStatusBarStyle)preferredStatusBarStyle {
    return [UIApplication sharedApplication].statusBarStyle;
}
- (BOOL)prefersStatusBarHidden {
    return [UIApplication sharedApplication].statusBarHidden;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.sheet layoutCard];
}
@end

@implementation CBSheet {
    UIWindow *_window;
    UIView *_dim;
    CBGlassView *_card, *_cancelCard;
    UIScrollView *_scroll;
    UILabel *_titleLabel;
    UIView *_titleLine;
    NSMutableArray *_rows;
    UIButton *_cancelButton;
    CGRect _sourceRect;
    __weak UIView *_sourceView;
    BOOL _shown, _closing;
}

+ (CBSheet *)visibleSheet {
    for (CBSheet *s in [gSheets reverseObjectEnumerator]) if (!s->_closing) return s;
    return nil;
}

- (BOOL)isVisible {
    return _shown && !_closing;
}

- (void)showInView:(UIView *)view {
    [self presentFromRect:CGRectNull inView:nil];
}

- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    [self presentFromRect:rect inView:view];
}

- (void)showFromBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated {
    [self presentFromRect:CGRectNull inView:nil];
}

- (void)showFromToolbar:(UIToolbar *)view {
    [self presentFromRect:CGRectNull inView:nil];
}

- (void)showFromTabBar:(UITabBar *)view {
    [self presentFromRect:CGRectNull inView:nil];
}

- (BOOL)usesPopover {
    return [CBTheme isPad];
}

- (UIButton *)rowButton:(NSString *)title index:(NSInteger)i {
    BOOL checked = [title hasPrefix:@"✓ "];
    if (checked) title = [title substringFromIndex:2];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = i;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [CBTheme font:16];
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, checked ? 40 : 14);
    UIColor *color = i == self.destructiveButtonIndex ? [CBTheme dangerText] : [CBTheme text];
    [b setTitleColor:color forState:UIControlStateNormal];
    [b setBackgroundImage:[CBGlass pill:18 color:[UIColor colorWithWhite:1 alpha:0.12] sheen:NO] forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    if (checked) {
        UIImageView *mark = [[UIImageView alloc] initWithImage:[CBIcon named:@"check" size:18 color:[CBTheme accent]]];
        mark.tag = 77;
        mark.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [b addSubview:mark];
    }
    return b;
}

- (void)presentFromRect:(CGRect)rect inView:(UIView *)view {
    if (_shown) return;
    _shown = YES;
    if (!gSheets) gSheets = [NSMutableArray array];
    [gSheets addObject:self];
    _sourceRect = rect;
    _sourceView = view;

    CBSheetController *vc = [[CBSheetController alloc] init];
    vc.sheet = self;
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.windowLevel = UIWindowLevelAlert;
    _window.backgroundColor = [UIColor clearColor];
    _window.rootViewController = vc;
    UIView *root = vc.view;
    root.backgroundColor = [UIColor clearColor];
    _dim = [[UIView alloc] initWithFrame:root.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:[self usesPopover] ? 0.18 : 0.35];
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(outsideTapped)]];
    [root addSubview:_dim];

    _card = [[CBGlassView alloc] initWithFrame:CGRectZero radius:26 style:CBGlassHeavy];
    [root addSubview:_card];
    if (self.title.length) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [CBTheme medium:13];
        _titleLabel.textColor = [CBTheme dim];
        _titleLabel.numberOfLines = 0;
        _titleLabel.text = self.title;
        [_card addSubview:_titleLabel];
        _titleLine = [[UIView alloc] init];
        _titleLine.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        [_card addSubview:_titleLine];
    }
    _scroll = [[UIScrollView alloc] init];
    _scroll.backgroundColor = [UIColor clearColor];
    _scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _scroll.scrollsToTop = NO;
    [_card addSubview:_scroll];
    _rows = [NSMutableArray array];
    for (NSInteger i = 0; i < self.numberOfButtons; i++) {
        if (i == self.cancelButtonIndex) continue;
        UIButton *b = [self rowButton:[self buttonTitleAtIndex:i] index:i];
        [_scroll addSubview:b];
        [_rows addObject:b];
    }
    if (self.cancelButtonIndex >= 0 && ![self usesPopover]) {
        _cancelCard = [[CBGlassView alloc] initWithFrame:CGRectZero radius:-1 style:CBGlassHeavy];
        _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_cancelButton setTitle:[self buttonTitleAtIndex:self.cancelButtonIndex] forState:UIControlStateNormal];
        _cancelButton.titleLabel.font = [CBTheme bold:17];
        [_cancelButton setTitleColor:[CBTheme text] forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
        _cancelButton.tag = self.cancelButtonIndex;
        [_cancelButton addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_cancelCard addSubview:_cancelButton];
        [root addSubview:_cancelCard];
    }
    _window.hidden = NO;   // không lấy quyền bàn phím của cửa sổ app
    [self layoutCard];

    _dim.alpha = 0;
    if ([self usesPopover]) {
        _card.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } else {
        CGFloat dy = root.bounds.size.height - _card.frame.origin.y;
        _card.transform = CGAffineTransformMakeTranslation(0, dy);
        _cancelCard.transform = CGAffineTransformMakeTranslation(0, dy);
    }
    UIView *dim = _dim, *card = _card, *cancel = _cancelCard;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        dim.alpha = 1;
        card.alpha = 1;
        card.transform = CGAffineTransformIdentity;
        cancel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)layoutCard {
    UIView *root = _window.rootViewController.view;
    if (!root || !_card) return;
    CGRect b = root.bounds;
    BOOL pop = [self usesPopover];
    CGFloat w = pop ? 300 : MIN(b.size.width - 20, 420), pad = 6, rowH = 48, inner = w - pad * 2;
    CGFloat titleH = 0;
    if (_titleLabel) {
        titleH = [CBTheme heightOf:_titleLabel.text font:_titleLabel.font width:w - 36];
        _titleLabel.frame = CGRectMake(18, 14, w - 36, titleH);
        _titleLine.frame = CGRectMake(18, 14 + titleH + 10, w - 36, 1);
        titleH += 25;
    }
    CGFloat listH = _rows.count * rowH;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        UIButton *r = _rows[i];
        r.frame = CGRectMake(0, i * rowH, inner, rowH);
        UIView *mark = [r viewWithTag:77];
        mark.frame = CGRectMake(inner - 32, (rowH - 18) / 2, 18, 18);
    }
    CGFloat cancelH = _cancelCard ? 54 : 0, gap = _cancelCard ? 8 : 0;
    CGFloat maxH = b.size.height - 30 - cancelH - gap;
    CGFloat cardH = MIN(titleH + pad * 2 + listH, maxH);
    CGFloat scrollH = cardH - titleH - pad * 2;
    _scroll.frame = CGRectMake(pad, titleH + pad, inner, scrollH);
    _scroll.contentSize = CGSizeMake(inner, listH);
    _scroll.scrollEnabled = listH > scrollH + 0.5;

    CGAffineTransform ct = _card.transform, kt = _cancelCard.transform;
    _card.transform = CGAffineTransformIdentity;
    _cancelCard.transform = CGAffineTransformIdentity;
    if (pop) {
        // Cạnh ô / nút gọi ra: ưu tiên bên dưới, thiếu chỗ thì bên trên, không vừa cả hai thì giữa màn hình
        CGRect src = CGRectNull;
        if (_sourceView.window && !CGRectIsNull(_sourceRect)) {
            src = [root convertRect:[_sourceView.window convertRect:[_sourceView convertRect:_sourceRect toView:nil] toWindow:nil] fromView:nil];
        }
        CGFloat x, y;
        if (CGRectIsNull(src)) {
            x = (b.size.width - w) / 2;
            y = (b.size.height - cardH) / 2;
        } else {
            x = MIN(MAX(12, CGRectGetMidX(src) - w / 2), b.size.width - w - 12);
            if (CGRectGetMaxY(src) + 8 + cardH <= b.size.height - 12) y = CGRectGetMaxY(src) + 8;
            else if (CGRectGetMinY(src) - 8 - cardH >= 12) y = CGRectGetMinY(src) - 8 - cardH;
            else y = (b.size.height - cardH) / 2;
        }
        _card.frame = CGRectMake(round(x), round(y), w, cardH);
    } else {
        CGFloat x = round((b.size.width - w) / 2);
        CGFloat bottom = b.size.height - 10;
        if (_cancelCard) {
            _cancelCard.frame = CGRectMake(x, bottom - cancelH, w, cancelH);
            _cancelButton.frame = _cancelCard.bounds;
            bottom -= cancelH + gap;
        }
        _card.frame = CGRectMake(x, bottom - cardH, w, cardH);
    }
    _card.transform = ct;
    _cancelCard.transform = kt;
}

- (void)rowTapped:(UIButton *)b {
    [self tapIndex:b.tag];
}

- (void)outsideTapped {
    [self tapIndex:self.cancelButtonIndex];
}

- (void)tapIndex:(NSInteger)index {
    if (_closing) return;
    id<UIActionSheetDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [d actionSheet:self clickedButtonAtIndex:index];
    [self dismissWithClickedButtonIndex:index animated:YES];
}

- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    if (!_shown || _closing) return;
    _closing = YES;
    id<UIActionSheetDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(actionSheet:willDismissWithButtonIndex:)]) [d actionSheet:self willDismissWithButtonIndex:index];
    UIView *dim = _dim, *card = _card, *cancel = _cancelCard;
    CGFloat dy = _window.rootViewController.view.bounds.size.height - _card.frame.origin.y;
    BOOL pop = [self usesPopover];
    void (^finish)(BOOL) = ^(BOOL finished) {
        self->_window.hidden = YES;
        self->_window.rootViewController = nil;
        self->_window = nil;
        if ([d respondsToSelector:@selector(actionSheet:didDismissWithButtonIndex:)]) [d actionSheet:self didDismissWithButtonIndex:index];
        [gSheets removeObject:self];
    };
    if (!animated) {
        finish(YES);
        return;
    }
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        dim.alpha = 0;
        if (pop) {
            card.alpha = 0;
        } else {
            card.transform = CGAffineTransformMakeTranslation(0, dy);
            cancel.transform = CGAffineTransformMakeTranslation(0, dy);
        }
    } completion:finish];
}

@end
