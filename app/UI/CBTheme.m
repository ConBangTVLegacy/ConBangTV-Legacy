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

@end
