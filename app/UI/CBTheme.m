#import "CBTheme.h"
#import "CBCompat.h"
#import "CBPrefs.h"
#import "CBJSON.h"

@implementation CBTheme

+ (UIColor *)bg { return CBRGB(0x0E1014); }
+ (UIColor *)surface { return CBRGB(0x171A21); }
+ (UIColor *)surface2 { return CBRGB(0x232833); }
+ (UIColor *)text { return CBRGB(0xF2F4F8); }
+ (UIColor *)dim { return CBRGB(0x9AA3B2); }
+ (UIColor *)brand { return CBRGB(0x2BAF85); }
+ (UIColor *)onBrand { return CBRGB(0x07140F); }
+ (UIColor *)focus { return CBRGB(0xFFB020); }
+ (UIColor *)watched { return CBRGB(0x3A6B5C); }

+ (UIColor *)profileColor:(NSInteger)index {
    // Prefs.ProfileColors của bản Windows / TV
    static const uint32_t colors[] = {0x2BAF85, 0xE5533D, 0x3B82F6, 0xF59E0B, 0x8B5CF6, 0x06B6D4, 0xEC4899, 0x84CC16};
    uint32_t c = colors[((index % 8) + 8) % 8];
    return CBRGB(c);
}

+ (BOOL)isPad {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

+ (UIFont *)font:(CGFloat)size {
    return [UIFont systemFontOfSize:size];
}

+ (UIFont *)bold:(CGFloat)size {
    return [UIFont boldSystemFontOfSize:size];
}

+ (UIImage *)imageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), YES, 1);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static NSString *CBColorKey(UIColor *color) {
    if (!color) return @"-";
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a] && [color getWhite:&r alpha:&a]) g = b = r;
    return [NSString stringWithFormat:@"%.3f %.3f %.3f %.3f", r, g, b, a];
}

+ (UIImage *)imageWithColor:(UIColor *)color radius:(CGFloat)radius {
    return [self imageWithColor:color radius:radius border:nil width:0];
}

+ (UIImage *)imageWithColor:(UIColor *)color radius:(CGFloat)radius border:(UIColor *)border width:(CGFloat)width {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (!border) width = 0;
    NSString *key = [NSString stringWithFormat:@"%@ %.1f | %@ %.1f", CBColorKey(color), radius, CBColorKey(border), width];
    UIImage *img = cache[key];
    if (img) return img;
    CGFloat side = MAX(radius, width) * 2 + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:radius] fill];
    if (width > 0) {
        [border setStroke];
        UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, side, side), width / 2, width / 2)
                                                        cornerRadius:MAX(0, radius - width / 2)];
        edge.lineWidth = width;
        [edge stroke];
    }
    CGFloat cap = MAX(radius, width);
    img = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap)];
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

+ (CBRoundLabel *)roundLabel:(UIColor *)fill radius:(CGFloat)radius {
    CBRoundLabel *l = [[CBRoundLabel alloc] init];
    l.fillColor = fill;
    l.radius = radius;
    return l;
}

+ (void)apply {
    UINavigationBar *bar = [UINavigationBar appearance];
    [bar setBackgroundImage:[self imageWithColor:[self surface]] forBarMetrics:UIBarMetricsDefault];
    [bar setTitleTextAttributes:@{UITextAttributeTextColor: [self text], UITextAttributeTextShadowColor: [UIColor clearColor],
                                  UITextAttributeFont: [self bold:18]}];
    [bar setTintColor:[self surface2]];
    [[UIBarButtonItem appearance] setTintColor:[self surface2]];
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{UITextAttributeTextColor: [self text],
                                                           UITextAttributeTextShadowColor: [UIColor clearColor]}
                                                forState:UIControlStateNormal];
    [[UISearchBar appearance] setTintColor:[self surface2]];
    [[UISwitch appearance] setOnTintColor:[self brand]];
    [[UISegmentedControl appearance] setTintColor:[self surface2]];
    [[UISlider appearance] setMinimumTrackTintColor:[self brand]];
}

+ (UIButton *)button:(NSString *)title primary:(BOOL)primary {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [self bold:15];
    UIColor *bg = primary ? [self brand] : [self surface2];
    UIColor *down = primary ? CBRGB(0x1F8A68) : CBRGB(0x343B48);
    [b setBackgroundImage:[self imageWithColor:bg radius:8] forState:UIControlStateNormal];
    [b setBackgroundImage:[self imageWithColor:down radius:8] forState:UIControlStateHighlighted];
    [b setTitleColor:primary ? [self onBrand] : [self text] forState:UIControlStateNormal];
    [b setTitleColor:[self dim] forState:UIControlStateDisabled];
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    return b;
}

+ (UIView *)avatarFor:(NSDictionary *)profile size:(CGFloat)size {
    UILabel *l = [self roundLabel:[self profileColor:(NSInteger)CBNum(profile, @"color", 0)] radius:size / 2];
    l.frame = CGRectMake(0, 0, size, size);
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [self bold:size * 0.45];
    l.text = [CBPrefs initialOf:profile];
    return l;
}

+ (UILabel *)messageLabel {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [self dim];
    l.font = [self font:15];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

+ (CGFloat)heightOf:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    if (!text.length) return 0;
    // Nhớ kết quả: đo chữ (CoreText) tốn — iOS 8 iPad mini 1 đo mô tả phim dài mất hàng chục ms, mà bố cục gọi lại nhiều lần
    // (mở trang phim, cuộn ô ảnh bìa). Chỉ dùng trên luồng chính.
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 2000;
    }
    BOOL main = [NSThread isMainThread];
    NSString *key = main ? [NSString stringWithFormat:@"%@ %.1f %.1f\n%@", font.fontName, font.pointSize, width, text] : nil;
    NSNumber *hit = key ? [cache objectForKey:key] : nil;
    if (hit) return hit.doubleValue;
    CGSize s = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat h = ceil(s.height);
    if (key) [cache setObject:@(h) forKey:key];
    return h;
}

+ (NSString *)time:(double)seconds {
    if (!isfinite(seconds) || seconds < 0) return @"--:--";
    long s = (long)seconds;
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%02ld:%02ld", s / 60, s % 60];
}

+ (void)layoutSegments:(UISegmentedControl *)seg inStrip:(UIScrollView *)strip frame:(CGRect)frame {
    strip.frame = frame;
    strip.showsHorizontalScrollIndicator = NO;
    strip.scrollsToTop = NO;
    UIFont *font = [UIFont boldSystemFontOfSize:13];  // chữ của UISegmentedControlStyleBar
    NSMutableArray *widths = [NSMutableArray array];
    CGFloat total = 0;
    for (NSUInteger i = 0; i < seg.numberOfSegments; i++) {
        CGFloat tw = ceil([[seg titleForSegmentAtIndex:i] ?: @"" sizeWithFont:font].width) + 28;
        [widths addObject:@(tw)];
        total += tw;
    }
    BOOL fits = total <= frame.size.width;
    for (NSUInteger i = 0; i < seg.numberOfSegments; i++) [seg setWidth:fits ? 0 : [widths[i] floatValue] forSegmentAtIndex:i];
    seg.frame = CGRectMake(0, 0, fits ? frame.size.width : total, frame.size.height);
    strip.contentSize = seg.frame.size;
}

static UILabel *gToast;

/// Chỗ gắn thông báo: màn trên cùng của cửa sổ chính. Trên iOS 6 cửa sổ không xoay theo máy (chỉ màn của nó xoay) — gắn vào
/// cửa sổ thì nằm ngang chữ ở iPad ngang / trình phát iPhone; và không lấy keyWindow (lúc bấm nút hộp thoại, keyWindow là cửa
/// sổ riêng của hộp thoại — thông báo biến mất theo hộp thoại).
+ (UIView *)toastHost {
    id<UIApplicationDelegate> d = [UIApplication sharedApplication].delegate;
    UIWindow *w = [d respondsToSelector:@selector(window)] ? d.window : [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc.isViewLoaded ? vc.view : w;
}

+ (void)toast:(NSString *)text {
    UIView *w = [self toastHost];
    if (!w || !text.length) return;
    [gToast removeFromSuperview];
    UILabel *l = [self roundLabel:[UIColor colorWithWhite:0.12 alpha:0.94] radius:10];
    l.textColor = [UIColor whiteColor];
    l.font = [self font:15];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = text;
    CGFloat maxW = MIN(w.bounds.size.width - 40, 420);
    CGFloat h = [self heightOf:text font:l.font width:maxW - 24] + 20;
    CGSize one = [text sizeWithFont:l.font];
    CGFloat lw = MIN(maxW, one.width + 32);
    l.frame = CGRectMake((w.bounds.size.width - lw) / 2, w.bounds.size.height - h - 100, lw, h);
    l.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    l.alpha = 0;
    [w addSubview:l];
    gToast = l;
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; }];
    double secs = MIN(6, 2.5 + text.length / 30.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secs * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ l.alpha = 0; } completion:^(BOOL done) {
            [l removeFromSuperview];
            if (gToast == l) gToast = nil;
        }];
    });
}

@end

NSString *CBPlayIcon(void) {
    return CBOldIOS() ? @"►" : @"▶︎";
}

@implementation CBRoundLabel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [super setBackgroundColor:[UIColor clearColor]];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;  // đổi khổ thì vẽ lại nền
    }
    return self;
}

// Nền thật của nhãn luôn trong suốt — màu nền bo góc là fillColor. Tinh chỉnh chế độ tối (vd Eclipse trên iOS 8) gán lại
// backgroundColor của mọi nhãn: nếu lấy màu từ đó thì mất nền bo góc (iPad mini 1, 18/11/2026), hoặc hiện nền vuông
- (void)setBackgroundColor:(UIColor *)color {
    [super setBackgroundColor:[UIColor clearColor]];
}

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay];
}

- (void)setRadius:(CGFloat)radius {
    _radius = radius;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (_fillColor && CGColorGetAlpha(_fillColor.CGColor) > 0) {
        [_fillColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:MIN(_radius, MIN(self.bounds.size.width, self.bounds.size.height) / 2)] fill];
    }
    [super drawRect:rect];
}

@end
