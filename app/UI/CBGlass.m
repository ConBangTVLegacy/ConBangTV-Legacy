#import "CBGlass.h"
#import "CBIcon.h"
#import "CBTheme.h"

/// Vệt sáng mép trên (như box-shadow inset 0 1px 0): phần nằm trong khung nhưng ngoài khung dời xuống 1 điểm
static void CBTopHighlight(CGRect box, CGFloat r, UIColor *color) {
    UIBezierPath *outer = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:r];
    UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:r];
    [edge appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(box, 0, 1) cornerRadius:r]];
    edge.usesEvenOddFillRule = YES;
    CGContextSaveGState(UIGraphicsGetCurrentContext());
    [outer addClip];
    [color setFill];
    [edge fill];
    CGContextRestoreGState(UIGraphicsGetCurrentContext());
}

/// Ánh bóng: dải sáng dần từ mép trên xuống giữa (giữ đúng khi ảnh kéo giãn ngang)
static void CBSheen(CGRect box, CGFloat r, CGFloat top, CGFloat mid, CGFloat bottom) {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:r] addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {1, 1, 1, top, 1, 1, 1, mid, 1, 1, 1, bottom};
    CGFloat locs[] = {0, 0.5, 1};
    CGGradientRef g = CGGradientCreateWithColorComponents(space, comps, locs, 3);
    CGContextDrawLinearGradient(ctx, g, CGPointMake(0, CGRectGetMinY(box)), CGPointMake(0, CGRectGetMaxY(box)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);
}

@implementation CBGlass

+ (CGFloat)margin {
    return [CBTheme lite] ? 0 : 12;
}

+ (UIImage *)image:(CGFloat)radius style:(CBGlassStyle)style {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    CGFloat r = MAX(1, round(radius * 2) / 2), m = [self margin];
    NSString *key = [NSString stringWithFormat:@"%.1f %ld %.0f", r, (long)style, m];
    UIImage *img = cache[key];
    if (img) return img;
    CGFloat side = (r + m) * 2 + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect box = CGRectMake(m, m, side - m * 2, side - m * 2);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:r];
    UIColor *fill = style == CBGlassHeavy ? [UIColor colorWithRed:34 / 255.0 green:38 / 255.0 blue:46 / 255.0 alpha:0.97]
                  : style == CBGlassPressed ? [UIColor colorWithRed:58 / 255.0 green:63 / 255.0 blue:76 / 255.0 alpha:0.96]
                  : [UIColor colorWithRed:33 / 255.0 green:37 / 255.0 blue:45 / 255.0 alpha:0.94];
    CGContextSaveGState(ctx);
    if (m > 0) {
        BOOL heavy = style == CBGlassHeavy;
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, heavy ? 5 : 3), heavy ? 16 : 11,
                                    [UIColor colorWithWhite:0 alpha:heavy ? 0.55 : 0.42].CGColor);
    }
    [fill setFill];
    [p fill];
    CGContextRestoreGState(ctx);
    CBSheen(box, r, 0.15, 0.03, 0.06);
    CBTopHighlight(box, r, [UIColor colorWithWhite:1 alpha:style == CBGlassHeavy ? 0.24 : 0.30]);
    UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(box, 0.5, 0.5) cornerRadius:MAX(0, r - 0.5)];
    rim.lineWidth = 1;
    [[UIColor colorWithWhite:1 alpha:0.10] setStroke];
    [rim stroke];
    CGFloat cap = r + m;
    img = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap)];
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

+ (UIImage *)pill:(CGFloat)radius color:(UIColor *)color sheen:(BOOL)sheen {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    CGFloat r = MAX(1, round(radius * 2) / 2);
    CGFloat cr = 0, cg = 0, cb = 0, ca = 1;
    if (![color getRed:&cr green:&cg blue:&cb alpha:&ca] && [color getWhite:&cr alpha:&ca]) cg = cb = cr;
    NSString *key = [NSString stringWithFormat:@"%.1f %.3f %.3f %.3f %.3f %d", r, cr, cg, cb, ca, sheen];
    UIImage *img = cache[key];
    if (img) return img;
    CGFloat side = r * 2 + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGRect box = CGRectMake(0, 0, side, side);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:r] fill];
    if (sheen) {
        CBSheen(box, r, 0.26, 0.02, 0);
        CBTopHighlight(box, r, [UIColor colorWithWhite:1 alpha:0.42]);
    }
    img = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(r, r, r, r)];
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

@end

#pragma mark -

@implementation CBGlassView {
    UIImageView *_bg;
    CGFloat _usedR;
    CBGlassStyle _usedStyle;
}

- (instancetype)initWithFrame:(CGRect)frame radius:(CGFloat)radius style:(CBGlassStyle)style {
    if ((self = [super initWithFrame:frame])) {
        _radius = radius;
        _style = style;
        _usedR = -1;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;
        _bg = [[UIImageView alloc] init];
        _bg.userInteractionEnabled = NO;
        [self addSubview:_bg];
        [self setNeedsLayout];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame radius:-1 style:CBGlassBar];
}

- (void)setRadius:(CGFloat)radius {
    _radius = radius;
    [self setNeedsLayout];
}

- (void)setStyle:(CBGlassStyle)style {
    _style = style;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat r = _radius < 0 ? self.bounds.size.height / 2 : _radius;
    r = MIN(r, MIN(self.bounds.size.width, self.bounds.size.height) / 2);
    if (r != _usedR || _style != _usedStyle) {
        _usedR = r;
        _usedStyle = _style;
        _bg.image = [CBGlass image:r style:_style];
    }
    CGFloat m = [CBGlass margin];
    _bg.frame = CGRectInset(self.bounds, -m, -m);
    if (self.subviews.firstObject != _bg) [self sendSubviewToBack:_bg];
}

@end

#pragma mark -

@implementation CBPillButton {
    UIImageView *_glass;      // kiểu kính: ảnh nền tràn ra ngoài khung (bóng đổ)
    CGFloat _usedR;
    CBPillStyle _usedStyle;
    NSString *_icon;
    CGFloat _iconSize;
}

+ (instancetype)pill:(NSString *)title style:(CBPillStyle)style {
    CBPillButton *b = [self buttonWithType:UIButtonTypeCustom];
    b->_radius = -1;
    b->_usedR = -1;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 16, 8, 16);
    b.adjustsImageWhenHighlighted = NO;
    b.adjustsImageWhenDisabled = NO;
    b.style = style;
    return b;
}

+ (instancetype)circle:(NSString *)icon diameter:(CGFloat)d {
    CBPillButton *b = [self pill:nil style:CBPillGlass];
    b.frame = CGRectMake(0, 0, d, d);
    b.contentEdgeInsets = UIEdgeInsetsZero;
    [b setIcon:icon size:round(d * 0.45)];
    return b;
}

- (UIColor *)textColor {
    switch (_style) {
        case CBPillProminent: return [CBTheme onBrand];
        case CBPillDanger: return [UIColor whiteColor];
        case CBPillSelected: return [CBTheme bg];
        default: return [CBTheme text];
    }
}

- (void)setStyle:(CBPillStyle)style {
    _style = style;
    BOOL strong = style == CBPillProminent || style == CBPillDanger || style == CBPillSelected;
    self.titleLabel.font = strong ? [CBTheme bold:15] : [CBTheme medium:15];
    [self setTitleColor:[self textColor] forState:UIControlStateNormal];
    [self setTitleColor:[[self textColor] colorWithAlphaComponent:0.45] forState:UIControlStateDisabled];
    if (_icon) [self setIcon:_icon size:_iconSize];
    _usedR = -1;
    [self setNeedsLayout];
}

- (void)setRadius:(CGFloat)radius {
    _radius = radius;
    _usedR = -1;
    [self setNeedsLayout];
}

- (void)setIcon:(NSString *)icon size:(CGFloat)size {
    _icon = icon;
    _iconSize = size;
    CGFloat s = size > 0 ? size : MAX(14, round(MAX(self.bounds.size.height, 30) * 0.45));
    UIImage *img = icon ? [CBIcon named:icon size:s color:[self textColor]] : nil;
    [self setImage:img forState:UIControlStateNormal];
    UIImage *off = icon ? [CBIcon named:icon size:s color:[[self textColor] colorWithAlphaComponent:0.45]] : nil;
    [self setImage:off forState:UIControlStateDisabled];
    BOOL both = img && [self titleForState:UIControlStateNormal].length;
    self.imageEdgeInsets = both ? UIEdgeInsetsMake(0, -3, 0, 3) : UIEdgeInsetsZero;
    self.titleEdgeInsets = both ? UIEdgeInsetsMake(0, 3, 0, -3) : UIEdgeInsetsZero;
}

- (void)applyBackground:(CGFloat)r {
    if (_style == CBPillGlass) {
        [self setBackgroundImage:nil forState:UIControlStateNormal];
        [self setBackgroundImage:nil forState:UIControlStateHighlighted];
        if (!_glass) {
            _glass = [[UIImageView alloc] init];
            _glass.userInteractionEnabled = NO;
            [self insertSubview:_glass atIndex:0];
        }
        _glass.hidden = NO;
        _glass.image = [CBGlass image:r style:self.highlighted ? CBGlassPressed : CBGlassBar];
        return;
    }
    _glass.hidden = YES;
    UIColor *normal, *down;
    BOOL sheen = NO;
    switch (_style) {
        case CBPillProminent: normal = [CBTheme brand]; down = CBRGB(0x23946F); sheen = YES; break;
        case CBPillDanger: normal = [CBTheme danger]; down = CBRGB(0xA92E23); sheen = YES; break;
        case CBPillSelected: normal = [CBTheme text]; down = CBRGB(0xC9CED6); break;
        default: normal = [UIColor colorWithWhite:1 alpha:0.09]; down = [UIColor colorWithWhite:1 alpha:0.18]; break;
    }
    [self setBackgroundImage:[CBGlass pill:r color:normal sheen:sheen] forState:UIControlStateNormal];
    [self setBackgroundImage:[CBGlass pill:r color:down sheen:sheen] forState:UIControlStateHighlighted];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    CGFloat r = _radius < 0 ? s.height / 2 : _radius;
    r = MIN(r, MIN(s.width, s.height) / 2);
    if (r > 0 && (r != _usedR || _style != _usedStyle)) {
        _usedR = r;
        _usedStyle = _style;
        [self applyBackground:r];
    }
    if (_glass && !_glass.hidden) {
        CGFloat m = [CBGlass margin];
        _glass.frame = CGRectInset(self.bounds, -m, -m);
        [self sendSubviewToBack:_glass];
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    BOOL was = self.highlighted;
    [super setHighlighted:highlighted];
    if (was != highlighted && _style == CBPillGlass && _glass && _usedR > 0) {
        _glass.image = [CBGlass image:_usedR style:highlighted ? CBGlassPressed : CBGlassBar];
    }
}

@end

#pragma mark -

static const CGFloat kSwW = 54, kSwH = 32, kKnobW = 32, kKnobH = 26;

/// Núm công tắc: viên thuốc trắng có bóng mờ (vẽ sẵn, lề 3 điểm cho bóng)
static UIImage *CBKnobImage(void) {
    static UIImage *img;
    if (img) return img;
    CGFloat m = 3;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kKnobW + m * 2, kKnobH + m * 2), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1.5), 3, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(m, m, kKnobW, kKnobH) cornerRadius:kKnobH / 2] fill];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation CBSwitch {
    UIImageView *_track, *_knob;
    CGPoint _touchStart;
    BOOL _moved;
    CGFloat _knobStartX;
}

- (instancetype)initWithFrame:(CGRect)frame {
    frame.size = CGSizeMake(kSwW, kSwH);
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _track = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kSwW, kSwH)];
        _track.userInteractionEnabled = NO;
        [self addSubview:_track];
        _knob = [[UIImageView alloc] initWithImage:CBKnobImage()];
        _knob.userInteractionEnabled = NO;
        [self addSubview:_knob];
        [self update:NO];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:CGRectZero];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(kSwW, kSwH);
}

- (CGFloat)knobXFor:(BOOL)on {
    return (on ? kSwW - kKnobW - 3 : 3) - 3;   // -3: lề bóng của ảnh núm
}

- (void)update:(BOOL)animated {
    UIImage *track = [CBGlass pill:kSwH / 2 color:_on ? [CBTheme brand] : [UIColor colorWithRed:0.47 green:0.49 blue:0.53 alpha:0.38] sheen:NO];
    void (^apply)(void) = ^{
        self->_knob.frame = CGRectMake([self knobXFor:self->_on], (kSwH - kKnobH) / 2 - 3, kKnobW + 6, kKnobH + 6);
    };
    _track.image = track;
    if (animated) [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:apply completion:nil];
    else apply();
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    [self update:animated];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.45;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _touchStart = [touch locationInView:self];
    _moved = NO;
    _knobStartX = _knob.frame.origin.x;
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat dx = [touch locationInView:self].x - _touchStart.x;
    if (fabs(dx) > 4) _moved = YES;
    if (_moved) {
        CGRect f = _knob.frame;
        f.origin.x = MIN(MAX(_knobStartX + dx, [self knobXFor:NO]), [self knobXFor:YES]);
        _knob.frame = f;
    }
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL on = _on;
    if (_moved) on = CGRectGetMidX(_knob.frame) > kSwW / 2;
    else if (CGRectContainsPoint(CGRectInset(self.bounds, -20, -20), [touch locationInView:self])) on = !_on;
    BOOL changed = on != _on;
    [self setOn:on animated:YES];
    if (changed) [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self update:YES];
}

@end
