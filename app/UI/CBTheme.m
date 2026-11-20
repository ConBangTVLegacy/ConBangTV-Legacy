#import "CBIcon.h"
#import "CBTheme.h"
#import "CBCompat.h"
#import "CBGlass.h"
#import "CBRootViewController.h"
#import "CBPrefs.h"
#import "CBJSON.h"

@implementation CBTheme

// Bảng màu kiểu iOS 26 (bản mẫu duyệt 20/11/2026): nền gần đen, mặt nhóm / thẻ sáng hơn một bậc
+ (UIColor *)bg { return CBRGB(0x0A0B0E); }
+ (UIColor *)surface { return CBRGB(0x16191F); }
+ (UIColor *)surface2 { return CBRGB(0x22262E); }
+ (UIColor *)text { return CBRGB(0xF2F4F8); }
+ (UIColor *)dim { return CBRGB(0x9AA3B2); }
+ (UIColor *)brand { return CBRGB(0x2BAF85); }
+ (UIColor *)onBrand { return CBRGB(0x07140F); }
+ (UIColor *)focus { return CBRGB(0xFFB020); }
+ (UIColor *)watched { return CBRGB(0x3A6B5C); }
+ (UIColor *)accent { return CBRGB(0x41C99B); }
+ (UIColor *)danger { return CBRGB(0xC9372A); }
+ (UIColor *)dangerText { return CBRGB(0xFF7A6B); }
+ (UIColor *)fill { return [UIColor colorWithWhite:1 alpha:0.09]; }
+ (UIColor *)separator { return [UIColor colorWithWhite:1 alpha:0.08]; }

+ (BOOL)lite {
    static int lite = -1;
    if (lite < 0) lite = [NSProcessInfo processInfo].physicalMemory < 400ull * 1024 * 1024;
    return lite == 1;
}

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

+ (UIFont *)medium:(CGFloat)size {
    return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size] ?: [UIFont boldSystemFontOfSize:size];
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
    // Kiểu iOS 26: thanh liền màu nền (không viền dưới, không bóng) — nút trên thanh là kính (CBNavController)
    UINavigationBar *bar = [UINavigationBar appearance];
    [bar setBackgroundImage:[self imageWithColor:[self bg]] forBarMetrics:UIBarMetricsDefault];
    if ([bar respondsToSelector:@selector(setShadowImage:)]) [bar setShadowImage:[[UIImage alloc] init]];
    if ([bar respondsToSelector:@selector(setBarTintColor:)]) [bar setBarTintColor:[self bg]];
    [bar setTitleTextAttributes:@{UITextAttributeTextColor: [self text], UITextAttributeTextShadowColor: [UIColor clearColor],
                                  UITextAttributeFont: [self bold:17]}];
    [bar setTintColor:[self surface2]];
    [[UIBarButtonItem appearance] setTintColor:[self surface2]];
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{UITextAttributeTextColor: [self text],
                                                           UITextAttributeTextShadowColor: [UIColor clearColor]}
                                                forState:UIControlStateNormal];
    // Ô tìm: viên thuốc trắng mờ trên nền trong suốt (kiểu iOS 26), chữ trắng, kính lúp vẽ bằng CBIcon
    UISearchBar *sb = [UISearchBar appearance];
    [sb setTintColor:[self surface2]];
    [sb setBackgroundImage:[[UIImage alloc] init]];
    [sb setSearchFieldBackgroundImage:[CBGlass pill:18 color:[UIColor colorWithWhite:1 alpha:0.11] sheen:NO] forState:UIControlStateNormal];
    [sb setImage:[CBIcon named:@"search" size:15 color:[self dim]] forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    [[UITextField appearanceWhenContainedIn:[UISearchBar class], nil] setTextColor:[self text]];
    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setBackgroundImage:[CBGlass pill:15 color:[UIColor colorWithWhite:1 alpha:0.12] sheen:NO]
                                                                                    forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [[UISwitch appearance] setOnTintColor:[self brand]];
    // Thanh chọn (Vietsub / Thuyết minh, nhóm kênh…): rãnh viên thuốc trắng mờ, mục đang chọn sáng hơn, không vạch chia
    UISegmentedControl *seg = [UISegmentedControl appearance];
    [seg setTintColor:[self surface2]];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    UIImage *clear = UIGraphicsGetImageFromCurrentImageContext();   // vạch chia trong suốt 1 điểm
    UIGraphicsEndImageContext();
    UIImage *track = [CBGlass pill:16 color:[UIColor colorWithWhite:1 alpha:0.08] sheen:NO];
    UIImage *on = [CBGlass pill:16 color:[UIColor colorWithWhite:1 alpha:0.2] sheen:NO];
    UIImage *down = [CBGlass pill:16 color:[UIColor colorWithWhite:1 alpha:0.14] sheen:NO];
    [seg setBackgroundImage:track forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [seg setBackgroundImage:on forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    [seg setBackgroundImage:down forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    UIControlState states[] = {UIControlStateNormal, UIControlStateSelected, UIControlStateHighlighted};
    for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) {
        [seg setDividerImage:clear forLeftSegmentState:states[i] rightSegmentState:states[j] barMetrics:UIBarMetricsDefault];
    }
    [seg setTitleTextAttributes:@{UITextAttributeFont: [self medium:13], UITextAttributeTextColor: CBRGB(0xB8BFCA),
                                  UITextAttributeTextShadowColor: [UIColor clearColor]} forState:UIControlStateNormal];
    [seg setTitleTextAttributes:@{UITextAttributeFont: [self bold:13], UITextAttributeTextColor: [UIColor whiteColor],
                                  UITextAttributeTextShadowColor: [UIColor clearColor]} forState:UIControlStateSelected];
    // Thanh tua: rãnh mảnh 4 điểm bo tròn, núm tròn trắng có bóng
    UISlider *sl = [UISlider appearance];
    [sl setMinimumTrackImage:[[CBGlass pill:2 color:[self accent] sheen:NO] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 2, 0, 2)]
                    forState:UIControlStateNormal];
    [sl setMaximumTrackImage:[[CBGlass pill:2 color:[UIColor colorWithWhite:1 alpha:0.25] sheen:NO]
                                 resizableImageWithCapInsets:UIEdgeInsetsMake(0, 2, 0, 2)] forState:UIControlStateNormal];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26, 26), NO, 0);
    CGContextSetShadowWithColor(UIGraphicsGetCurrentContext(), CGSizeMake(0, 1.5), 3, [UIColor colorWithWhite:0 alpha:0.4].CGColor);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 3, 18, 18)] fill];
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [sl setThumbImage:thumb forState:UIControlStateNormal];
    [sl setThumbImage:thumb forState:UIControlStateHighlighted];
}

+ (void)darkKeyboard:(UISearchBar *)bar {
    if ([bar respondsToSelector:@selector(setKeyboardAppearance:)]) {
        [(id)bar setKeyboardAppearance:UIKeyboardAppearanceAlert];
        return;
    }
    NSMutableArray *stack = [NSMutableArray arrayWithObject:bar];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[UITextField class]]) {
            [(UITextField *)v setKeyboardAppearance:UIKeyboardAppearanceAlert];
            return;
        }
        [stack addObjectsFromArray:v.subviews];
    }
}

+ (UIButton *)button:(NSString *)title primary:(BOOL)primary {
    return [CBPillButton pill:title style:primary ? CBPillProminent : CBPillSubtle];
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
    UILabel *l = [self roundLabel:[UIColor colorWithRed:33 / 255.0 green:37 / 255.0 blue:45 / 255.0 alpha:0.96] radius:22];
    l.textColor = [UIColor whiteColor];
    l.font = [self font:15];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = text;
    CGFloat maxW = MIN(w.bounds.size.width - 40, 420);
    CGFloat h = MAX(44, [self heightOf:text font:l.font width:maxW - 36] + 22);
    CGSize one = [text sizeWithFont:l.font];
    CGFloat lw = MIN(maxW, one.width + 40);
    // Trên thanh tab nổi (+ thanh thu nhỏ) của màn gốc
    CBRootViewController *root = [CBRootViewController current];
    CGFloat gap = root && w == root.view ? MAX(100, root.overlayBottom + 16) : 100;
    l.frame = CGRectMake((w.bounds.size.width - lw) / 2, w.bounds.size.height - h - gap, lw, h);
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
