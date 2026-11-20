#import "CBTabHeader.h"
#import "CBGlass.h"
#import "CBIcon.h"
#import "CBRootViewController.h"
#import "CBTheme.h"

@implementation CBTabHeader {
    UILabel *_label;
}

+ (CGFloat)height {
    return [CBRootViewController statusInset] + ([CBTheme isPad] ? 66 : 54);
}

- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, [CBTabHeader height])])) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [CBTheme text];
        _label.font = [CBTheme bold:30];
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.6;
        _label.hidden = [CBTheme isPad];
        [self addSubview:_label];
        self.title = title;
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.text = title;
}

- (void)setLeftItems:(NSArray *)items {
    for (UIView *v in _leftItems) [v removeFromSuperview];
    _leftItems = [items copy];
    for (UIView *v in items) [self addSubview:v];
    [self setNeedsLayout];
}

- (void)setRightItems:(NSArray *)items {
    for (UIView *v in _rightItems) [v removeFromSuperview];
    _rightItems = [items copy];
    for (UIView *v in items) [self addSubview:v];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, top = [CBRootViewController statusInset];
    if ([CBTheme isPad]) {
        // Ngang hàng thanh tab (CBRootViewController: thanh tab cao 46, cách đỉnh 10)
        CGFloat cy = top + 10 + 23, x = 20;
        for (UIView *v in _leftItems) {
            v.frame = CGRectMake(x, round(cy - v.bounds.size.height / 2), v.bounds.size.width, v.bounds.size.height);
            x += v.bounds.size.width + 10;
        }
        x = w - 20;
        for (UIView *v in [_rightItems reverseObjectEnumerator]) {
            x -= v.bounds.size.width;
            v.frame = CGRectMake(x, round(cy - v.bounds.size.height / 2), v.bounds.size.width, v.bounds.size.height);
            x -= 10;
        }
        return;
    }
    CGFloat cy = top + 8 + 20, x = w - 12;
    NSArray *all = [(_leftItems ?: @[]) arrayByAddingObjectsFromArray:_rightItems ?: @[]];
    for (UIView *v in [all reverseObjectEnumerator]) {
        x -= v.bounds.size.width;
        v.frame = CGRectMake(x, round(cy - v.bounds.size.height / 2), v.bounds.size.width, v.bounds.size.height);
        x -= 8;
    }
    _label.frame = CGRectMake(16, cy - 20, MAX(40, x - 16), 40);
}

+ (UIView *)groupWithIcons:(NSArray *)icons target:(id)target actions:(NSArray *)selectors labels:(NSArray *)labels {
    CGFloat bw = 42, h = 40;
    CBGlassView *g = [[CBGlassView alloc] initWithFrame:CGRectMake(0, 0, bw * icons.count, h) radius:-1 style:CBGlassBar];
    for (NSUInteger i = 0; i < icons.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(i * bw, 0, bw, h);
        [b setImage:[CBIcon named:icons[i] size:19 color:[CBTheme text]] forState:UIControlStateNormal];
        [b setImage:[CBIcon named:icons[i] size:19 color:[CBTheme dim]] forState:UIControlStateHighlighted];
        if (i < labels.count) b.accessibilityLabel = labels[i];
        if (i < selectors.count) [b addTarget:target action:NSSelectorFromString(selectors[i]) forControlEvents:UIControlEventTouchUpInside];
        [g addSubview:b];
    }
    return g;
}

+ (UIButton *)avatarButton:(NSDictionary *)profile target:(id)target action:(SEL)action {
    CBPillButton *b = [CBPillButton pill:nil style:CBPillGlass];
    b.contentEdgeInsets = UIEdgeInsetsZero;
    CGFloat d = [CBTheme isPad] ? 46 : 40;
    b.frame = CGRectMake(0, 0, d, d);
    UIView *avatar = [CBTheme avatarFor:profile size:d - 10];
    avatar.frame = CGRectMake(5, 5, d - 10, d - 10);
    avatar.userInteractionEnabled = NO;
    [b addSubview:avatar];
    b.accessibilityLabel = @"Ai đang xem";
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@end
