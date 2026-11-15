#import "CBTheme.h"
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
    [b setBackgroundImage:[self imageWithColor:bg] forState:UIControlStateNormal];
    [b setBackgroundImage:[self imageWithColor:down] forState:UIControlStateHighlighted];
    [b setTitleColor:primary ? [self onBrand] : [self text] forState:UIControlStateNormal];
    [b setTitleColor:[self dim] forState:UIControlStateDisabled];
    b.layer.cornerRadius = 8;
    b.clipsToBounds = YES;
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    return b;
}

+ (UIView *)avatarFor:(NSDictionary *)profile size:(CGFloat)size {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    l.backgroundColor = [self profileColor:(NSInteger)CBNum(profile, @"color", 0)];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [self bold:size * 0.45];
    l.text = [CBPrefs initialOf:profile];
    l.layer.cornerRadius = size / 2;
    l.clipsToBounds = YES;
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
    CGSize s = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    return ceil(s.height);
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
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94];
    l.textColor = [UIColor whiteColor];
    l.font = [self font:15];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = text;
    l.layer.cornerRadius = 10;
    l.clipsToBounds = YES;
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
