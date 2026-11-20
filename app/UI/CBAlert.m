#import "CBAlert.h"
#import "CBGlass.h"
#import "CBTheme.h"

/// Từ giao diện iOS 26 (20/11/2026) mọi bản iOS dùng hộp tự vẽ (xem CBAlert.h)
static BOOL CBOwnDialogs(void) {
    return YES;
}

/// Hộp tự vẽ đang hiện (giữ sống tới khi đóng hẳn), cái mở sau ở cuối
static NSMutableArray *gShown;

static UIWindow *CBMainWindow(void) {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    return [d respondsToSelector:@selector(window)] ? d.window : nil;
}

/// Màn đang ở trên cùng của cửa sổ chính (màn được trình bày, nếu có)
static UIViewController *CBTopController(void) {
    UIViewController *vc = CBMainWindow().rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

@interface CBAlert ()
- (void)layoutBox;
@end

/// Ô nhập của hộp tự vẽ: chữ gợi ý màu sáng hơn (mặc định xám đậm, gần như không thấy trên nền tối)
@interface CBAlertField : UITextField
@end

@implementation CBAlertField
- (void)drawPlaceholderInRect:(CGRect)rect {
    UIFont *font = self.font;
    CGSize s = [self.placeholder sizeWithFont:font];
    [[CBTheme dim] setFill];
    [self.placeholder drawInRect:CGRectMake(rect.origin.x, rect.origin.y + (rect.size.height - s.height) / 2, rect.size.width, s.height)
                        withFont:font lineBreakMode:NSLineBreakByTruncatingTail alignment:self.textAlignment];
}
@end

/// Màn gốc của cửa sổ hộp thoại: xoay như màn đang mở bên dưới, thanh trạng thái giữ như cũ
@interface CBAlertController : UIViewController
@property (nonatomic, weak) CBAlert *alert;
@end

@implementation CBAlertController
- (BOOL)shouldAutorotate {
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *top = CBTopController();
    return top ? [top supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}
// iOS 5 hỏi hàm này
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
    [self.alert layoutBox];
}
@end

@implementation CBAlert {
    void (^_done)(CBAlert *, NSInteger);
    NSInteger _firstOther;
    NSMutableArray *_after;
    BOOL _dismissed;
    // ---- Hộp tự vẽ (iOS 7+)
    UIAlertViewStyle _style;
    NSMutableArray *_fields;
    UIWindow *_window;
    UIView *_dim;
    CBGlassView *_box;
    UIScrollView *_textScroll;
    UILabel *_titleLabel, *_messageLabel;
    NSMutableArray *_buttonViews;
    BOOL _shown, _closing;
    CGFloat _keyboardTop;   // mép trên bàn phím trong màn hộp thoại; 0 = không có bàn phím
}

+ (CBAlert *)title:(NSString *)title message:(NSString *)message cancel:(NSString *)cancel others:(NSArray *)others
              done:(void (^)(CBAlert *, NSInteger))done {
    CBAlert *a = [[CBAlert alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:cancel otherButtonTitles:nil];
    a->_firstOther = a.numberOfButtons;   // các nút «others» đứng sau nút huỷ (nếu có)
    for (NSString *o in others) [a addButtonWithTitle:o];
    a.delegate = a;
    a->_done = [done copy];
    return a;
}

- (NSInteger)otherIndex:(NSInteger)index {
    return index >= _firstOther && index < self.numberOfButtons ? index - _firstOther : -1;
}

/// Nút chính (in đậm, nền xanh; phím Xong của bàn phím): nút đầu tiên không phải nút huỷ — cả hộp tạo thẳng bằng initWithTitle:…
- (NSInteger)preferredIndex {
    for (NSInteger i = 0; i < self.numberOfButtons; i++) if (i != self.cancelButtonIndex) return i;
    return -1;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
    void (^done)(CBAlert *, NSInteger) = _done;
    _done = nil;  // bỏ vòng giữ nhau (khối giữ hộp thoại)
    if (done) done(self, index);
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)index {
    _dismissed = YES;
    NSArray *blocks = _after;
    _after = nil;
    for (dispatch_block_t b in blocks) b();
}

- (void)afterDismiss:(dispatch_block_t)block {
    if (!block) return;
    if (_dismissed) {
        dispatch_async(dispatch_get_main_queue(), block);
        return;
    }
    if (!_after) _after = [NSMutableArray array];
    [_after addObject:[block copy]];
}

+ (CBAlert *)visibleOwnAlert {
    for (CBAlert *a in [gShown reverseObjectEnumerator]) if (!a->_closing) return a;
    return nil;
}

+ (void)askPin:(NSString *)title message:(NSString *)message done:(void (^)(NSString *))done {
    CBAlert *a = [self title:title message:message cancel:@"Huỷ" others:@[@"OK"] done:^(CBAlert *alert, NSInteger index) {
        if (index == alert.cancelButtonIndex) {
            done(nil);
            return;
        }
        done([[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"");
    }];
    a.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
    [a show];
}

#pragma mark - Hộp tự vẽ (iOS 7+)

- (void)setAlertViewStyle:(UIAlertViewStyle)style {
    if (!CBOwnDialogs()) {
        [super setAlertViewStyle:style];
        return;
    }
    _style = style;
    NSInteger n = style == UIAlertViewStyleLoginAndPasswordInput ? 2 : (style == UIAlertViewStyleDefault ? 0 : 1);
    _fields = [NSMutableArray array];
    for (NSInteger i = 0; i < n; i++) {
        UITextField *f = [[CBAlertField alloc] init];
        f.font = [CBTheme font:16];
        f.textColor = [CBTheme text];
        f.borderStyle = UITextBorderStyleNone;
        f.background = [CBTheme imageWithColor:[UIColor colorWithWhite:0 alpha:0.28] radius:12 border:[UIColor colorWithWhite:1 alpha:0.12] width:1];
        f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
        f.leftViewMode = UITextFieldViewModeAlways;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        f.keyboardAppearance = UIKeyboardAppearanceDark;
        f.secureTextEntry = style == UIAlertViewStyleSecureTextInput || (style == UIAlertViewStyleLoginAndPasswordInput && i == 1);
        f.returnKeyType = i + 1 < n ? UIReturnKeyNext : UIReturnKeyDone;
        f.delegate = self;
        [_fields addObject:f];
    }
}

- (UIAlertViewStyle)alertViewStyle {
    return CBOwnDialogs() ? _style : [super alertViewStyle];
}

- (UITextField *)textFieldAtIndex:(NSInteger)index {
    if (!CBOwnDialogs()) return [super textFieldAtIndex:index];
    return index >= 0 && index < (NSInteger)_fields.count ? _fields[index] : nil;
}

- (BOOL)isVisible {
    return CBOwnDialogs() ? _shown && !_closing : [super isVisible];
}

- (void)setMessage:(NSString *)message {
    [super setMessage:message];
    if (_shown && !_closing) {
        _messageLabel.text = message;
        [self layoutBox];
    }
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    if (_shown && !_closing) {
        _titleLabel.text = title;
        [self layoutBox];
    }
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentLeft;   // iOS 26: hộp thoại canh trái
    [_textScroll addSubview:l];
    return l;
}

- (void)show {
    if (!CBOwnDialogs()) {
        [super show];
        return;
    }
    if (_shown) return;
    _shown = YES;
    if (!gShown) gShown = [NSMutableArray array];
    [gShown addObject:self];

    CBAlertController *vc = [[CBAlertController alloc] init];
    vc.alert = self;
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.windowLevel = UIWindowLevelAlert;
    _window.backgroundColor = [UIColor clearColor];
    _window.rootViewController = vc;
    UIView *root = vc.view;
    root.backgroundColor = [UIColor clearColor];
    _dim = [[UIView alloc] initWithFrame:root.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [root addSubview:_dim];

    // Khung kính (ảnh kéo giãn — không layer.cornerRadius, xem CBGlass)
    _box = [[CBGlassView alloc] initWithFrame:CGRectZero radius:28 style:CBGlassHeavy];
    _textScroll = [[UIScrollView alloc] init];
    _textScroll.backgroundColor = [UIColor clearColor];
    _textScroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [_box addSubview:_textScroll];
    _titleLabel = [self label:[CBTheme bold:17] color:[CBTheme text]];
    _titleLabel.text = self.title;
    _messageLabel = [self label:[CBTheme font:14] color:[UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:0.82]];
    _messageLabel.text = self.message;
    for (UITextField *f in _fields) [_box addSubview:f];

    _buttonViews = [NSMutableArray array];
    NSInteger main = [self preferredIndex];
    for (NSInteger i = 0; i < self.numberOfButtons; i++) {
        BOOL preferred = i == main;
        NSString *t = [self buttonTitleAtIndex:i];
        // Nút chính xoá / bỏ dữ liệu → đỏ; nút chính khác → xanh; còn lại (huỷ…) nền trắng mờ
        BOOL danger = preferred && ([t hasPrefix:@"Xoá"] || [t hasPrefix:@"Xóa"] || [t hasPrefix:@"Bỏ"] || [t hasPrefix:@"Quên"]);
        CBPillButton *b = [CBPillButton pill:t style:danger ? CBPillDanger : (preferred ? CBPillProminent : CBPillSubtle)];
        b.tag = i;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.7;
        [b addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_box addSubview:b];
        [_buttonViews addObject:b];
    }
    [root addSubview:_box];

    if (_fields.count) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                     name:UIKeyboardWillChangeFrameNotification object:nil];
        [_window makeKeyAndVisible];   // ô nhập cần cửa sổ chính (key) để hiện bàn phím
    } else {
        _window.hidden = NO;           // không lấy quyền bàn phím của cửa sổ app
    }
    [self layoutBox];
    _dim.alpha = 0;
    _box.alpha = 0;
    _box.transform = CGAffineTransformMakeScale(1.08, 1.08);
    UIView *dim = _dim, *box = _box;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        dim.alpha = 1;
        box.alpha = 1;
        box.transform = CGAffineTransformIdentity;
    } completion:nil];
    if (_fields.count) [_fields[0] becomeFirstResponder];
}

/// Thứ tự nút như UIAlertView: hai nút — huỷ bên trái; nhiều hơn — các nút xếp dọc, huỷ ở cuối
- (NSArray *)orderedButtons {
    NSInteger cancel = self.cancelButtonIndex;
    NSMutableArray *rest = [NSMutableArray array];
    UIButton *cancelButton = nil;
    for (UIButton *b in _buttonViews) {
        if (b.tag == cancel) cancelButton = b;
        else [rest addObject:b];
    }
    if (!cancelButton) return rest;
    if (_buttonViews.count == 2) return @[cancelButton, rest[0]];
    [rest addObject:cancelButton];
    return rest;
}

- (void)layoutBox {
    UIView *root = _window.rootViewController.view;
    if (!root || !_box) return;
    CGRect area = root.bounds;
    if (_keyboardTop > 0) area.size.height = MIN(area.size.height, _keyboardTop);
    CGFloat w = MIN([CBTheme isPad] ? 340 : 288, root.bounds.size.width - 28), pad = 20, inner = w - pad * 2;
    // Chữ: tiêu đề + nội dung, cuộn được khi dài (ghi chú bản mới…)
    CGFloat th = [CBTheme heightOf:_titleLabel.text font:_titleLabel.font width:inner];
    CGFloat mh = [CBTheme heightOf:_messageLabel.text font:_messageLabel.font width:inner];
    CGFloat gap = th && mh ? 6 : 0, textH = th + gap + mh;
    _titleLabel.frame = CGRectMake(0, 0, inner, th);
    _messageLabel.frame = CGRectMake(0, th + gap, inner, mh);
    _textScroll.contentSize = CGSizeMake(inner, textH);
    CGFloat fieldsH = _fields.count ? _fields.count * 40 + (_fields.count - 1) * 8 : 0;
    NSArray *buttons = [self orderedButtons];
    BOOL row = buttons.count == 2;
    CGFloat buttonsH = buttons.count ? (row ? 44 : buttons.count * 44 + (buttons.count - 1) * 8) : 0;
    CGFloat top = pad + 2, bottom = 14;
    CGFloat fixed = top + (fieldsH ? 14 + fieldsH : 0) + (buttonsH ? 18 + buttonsH : 0) + bottom;
    CGFloat textMax = MAX(44, area.size.height - 40 - fixed);
    CGFloat shownText = MIN(textH, textMax);
    _textScroll.frame = CGRectMake(pad, top, inner, shownText);
    _textScroll.scrollEnabled = textH > shownText;
    CGFloat y = top + shownText;
    if (fieldsH) {
        y += 14;
        for (UITextField *f in _fields) {
            f.frame = CGRectMake(pad, y, inner, 40);
            y += 48;
        }
        y -= 8;
    }
    // Nút: cách mép hộp 14 điểm (góc nút đồng tâm với góc hộp)
    CGFloat bpad = 14, binner = w - bpad * 2;
    if (buttonsH) {
        y += 18;
        if (row) {
            CGFloat bw = floor((binner - 10) / 2);
            [buttons[0] setFrame:CGRectMake(bpad, y, bw, 44)];
            [buttons[1] setFrame:CGRectMake(bpad + binner - bw, y, bw, 44)];
            y += 44;
        } else {
            for (UIButton *b in buttons) {
                b.frame = CGRectMake(bpad, y, binner, 44);
                y += 52;
            }
            y -= 8;
        }
    }
    CGFloat h = y + bottom;
    CGAffineTransform t = _box.transform;
    _box.transform = CGAffineTransformIdentity;
    _box.frame = CGRectMake(round((root.bounds.size.width - w) / 2), round(area.origin.y + MAX(10, (area.size.height - h) / 2)), w, h);
    _box.transform = t;
}

- (void)keyboardChanged:(NSNotification *)n {
    UIView *root = _window.rootViewController.view;
    CGRect kb = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kb = [root convertRect:[_window convertRect:kb fromWindow:nil] fromView:nil];
    _keyboardTop = CGRectIntersectsRect(kb, root.bounds) && kb.origin.y > 0 ? kb.origin.y : 0;
    [UIView animateWithDuration:[n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] animations:^{ [self layoutBox]; }];
}

- (void)buttonTapped:(UIButton *)b {
    [self tapIndex:b.tag];
}

- (void)tapIndex:(NSInteger)index {
    if (_closing) return;
    id<UIAlertViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [d alertView:self clickedButtonAtIndex:index];
    [self dismissWithClickedButtonIndex:index animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    NSUInteger i = [_fields indexOfObject:f];
    if (i != NSNotFound && i + 1 < _fields.count) {
        [_fields[i + 1] becomeFirstResponder];
    } else if ([self preferredIndex] >= 0) {
        [self tapIndex:[self preferredIndex]];   // như UIAlertView: phím Xong = nút đầu tiên không phải huỷ
    }
    return NO;
}

- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    if (!CBOwnDialogs()) {
        [super dismissWithClickedButtonIndex:index animated:animated];
        return;
    }
    if (!_shown || _closing) return;
    _closing = YES;
    id<UIAlertViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(alertView:willDismissWithButtonIndex:)]) [d alertView:self willDismissWithButtonIndex:index];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [_box endEditing:YES];
    UIView *dim = _dim, *box = _box;
    void (^finish)(BOOL) = ^(BOOL finished) {
        BOOL wasKey = self->_window.isKeyWindow;
        self->_window.hidden = YES;
        self->_window.rootViewController = nil;
        self->_window = nil;
        [gShown removeObject:self];
        if (wasKey) {
            // Trả quyền bàn phím: hộp còn đang hiện có ô nhập, không thì cửa sổ app
            CBAlert *top = [CBAlert visibleOwnAlert];
            UIWindow *next = top && top->_fields.count ? top->_window : CBMainWindow();
            [next makeKeyWindow];
        }
        if ([d respondsToSelector:@selector(alertView:didDismissWithButtonIndex:)]) [d alertView:self didDismissWithButtonIndex:index];
    };
    if (!animated) {
        finish(YES);
        return;
    }
    [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        dim.alpha = 0;
        box.alpha = 0;
    } completion:finish];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
