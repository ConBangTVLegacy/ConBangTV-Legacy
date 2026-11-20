#import "CBGroupedTableViewController.h"
#import "CBCompat.h"
#import "CBIcon.h"
#import "CBTheme.h"
#import <objc/runtime.h>

static const NSInteger kChevronTag = 0x6B7;

/// iOS 7+: bảng nhóm tràn hết bề ngang — ô vuông góc (bo góc ở mép màn hình trông lạ)
static BOOL CBFlatGroups(void) {
    return [[UIDevice currentDevice].systemVersion floatValue] >= 7;
}

@implementation CBGroupedTableViewController

+ (void)initialize {
    if (self != [CBGroupedTableViewController class] || !CBOldIOS()) return;
    // iOS 5: gắn hàm vẽ nhãn trước khi có bảng nào (UITableView ghi nhớ hàm uỷ quyền lúc đặt delegate)
    SEL pairs[][2] = {
        {@selector(tableView:viewForHeaderInSection:), @selector(cb5_tableView:viewForHeaderInSection:)},
        {@selector(tableView:viewForFooterInSection:), @selector(cb5_tableView:viewForFooterInSection:)},
        {@selector(tableView:heightForHeaderInSection:), @selector(cb5_tableView:heightForHeaderInSection:)},
        {@selector(tableView:heightForFooterInSection:), @selector(cb5_tableView:heightForFooterInSection:)},
    };
    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        Method m = class_getInstanceMethod(self, pairs[i][1]);
        class_addMethod(self, pairs[i][0], method_getImplementation(m), method_getTypeEncoding(m));
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [CBTheme bg];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;   // đường kẻ nằm trong ảnh nền ô
    if (!CBFlatGroups()) self.tableView.rowHeight = 46;
}

#pragma mark - Ô

/// Ảnh nền ô theo vị trí trong nhóm: 0 một mình, 1 đầu, 2 giữa, 3 cuối. Ô đầu / giữa có đường kẻ mảnh ở mép dưới (từ x = 16)
+ (UIImage *)cellImage:(NSInteger)pos selected:(BOOL)selected {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%ld %d", (long)pos, selected];
    UIImage *img = cache[key];
    if (img) return img;
    BOOL flat = CBFlatGroups();
    CGFloat r = flat ? 0 : 18, cap = MAX(r, 17), w = cap * 2 + 1, h = MAX(r * 2 + 1, 3);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), NO, 0);
    UIRectCorner corners = pos == 0 ? UIRectCornerAllCorners : pos == 1 ? (UIRectCornerTopLeft | UIRectCornerTopRight)
                         : pos == 3 ? (UIRectCornerBottomLeft | UIRectCornerBottomRight) : 0;
    UIBezierPath *p = r > 0 && corners ? [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h) byRoundingCorners:corners
                                                                     cornerRadii:CGSizeMake(r, r)]
                                       : [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, w, h)];
    [(selected ? CBRGB(0x262A33) : [CBTheme surface]) setFill];
    [p fill];
    if (pos == 1 || pos == 2) {
        CGFloat px = 1 / [UIScreen mainScreen].scale;
        [[UIColor colorWithWhite:1 alpha:0.07] setFill];
        UIRectFillUsingBlendMode(CGRectMake(16, h - px, w - 16, px), kCGBlendModeNormal);
    }
    UIEdgeInsets caps = flat ? UIEdgeInsetsMake(1, cap, 1, cap) : UIEdgeInsetsMake(r, cap, r, cap);
    img = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:caps];
    UIGraphicsEndImageContext();
    cache[key] = img;
    return img;
}

+ (UIImage *)rowIcon:(NSString *)icon color:(UIColor *)color {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString *key = [NSString stringWithFormat:@"%@ %.3f %.3f %.3f", icon, r, g, b];
    UIImage *img = cache[key];
    if (img) return img;
    CGFloat s = 29;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:7.5];
    [color setFill];
    [p fill];
    // Ánh bóng nhẹ phía trên (biểu tượng kiểu kính)
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    [p addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {1, 1, 1, 0.22, 1, 1, 1, 0};
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, s * 0.6), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);
    [[CBIcon named:icon size:18 color:[UIColor whiteColor]] drawInRect:CGRectMake(5.5, 5.5, 18, 18)];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) cache[key] = img;
    return img;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger n = [self tableView:tv numberOfRowsInSection:ip.section];
    NSInteger pos = n <= 1 ? 0 : ip.row == 0 ? 1 : ip.row == n - 1 ? 3 : 2;
    cell.backgroundColor = [UIColor clearColor];
    UIImageView *bg = [cell.backgroundView isKindOfClass:[UIImageView class]] ? (UIImageView *)cell.backgroundView : nil;
    if (!bg) {
        bg = [[UIImageView alloc] init];
        cell.backgroundView = bg;
    }
    bg.image = [CBGroupedTableViewController cellImage:pos selected:NO];
    UIImageView *sel = [cell.selectedBackgroundView isKindOfClass:[UIImageView class]] ? (UIImageView *)cell.selectedBackgroundView : nil;
    if (!sel) {
        sel = [[UIImageView alloc] init];
        cell.selectedBackgroundView = sel;
    }
    sel.image = [CBGroupedTableViewController cellImage:pos selected:YES];
    // Mũi tên «›» mảnh, màu nhạt (thay mũi tên xám của hệ thống)
    if (cell.accessoryType == UITableViewCellAccessoryDisclosureIndicator) {
        if (cell.accessoryView.tag != kChevronTag) {
            UIImageView *chev = [[UIImageView alloc] initWithImage:[CBIcon named:@"forward" size:15 color:CBRGB(0x6E7685)]];
            chev.tag = kChevronTag;
            cell.accessoryView = chev;
        }
    } else if (cell.accessoryType == UITableViewCellAccessoryCheckmark) {
        if (cell.accessoryView.tag != kChevronTag + 1) {
            UIImageView *mark = [[UIImageView alloc] initWithImage:[CBIcon named:@"check" size:18 color:[CBTheme accent]]];
            mark.tag = kChevronTag + 1;
            cell.accessoryView = mark;
        }
    } else if (cell.accessoryView.tag == kChevronTag || cell.accessoryView.tag == kChevronTag + 1) {
        cell.accessoryView = nil;
    }
}

#pragma mark - iOS 6+

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)view;
        h.textLabel.textColor = [CBTheme dim];
        h.textLabel.shadowColor = [UIColor clearColor];
        h.textLabel.font = [CBTheme medium:13];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)view;
        h.textLabel.textColor = [CBTheme dim];
        h.textLabel.shadowColor = [UIColor clearColor];
        h.textLabel.font = [CBTheme font:13];
        h.textLabel.textAlignment = NSTextAlignmentLeft;
    }
}

#pragma mark - iOS 5 (gắn ở +initialize)

- (NSString *)cb5_title:(UITableView *)tv section:(NSInteger)s footer:(BOOL)footer {
    SEL sel = footer ? @selector(tableView:titleForFooterInSection:) : @selector(tableView:titleForHeaderInSection:);
    if (![self respondsToSelector:sel]) return nil;
    NSString *t = footer ? [self tableView:tv titleForFooterInSection:s] : [self tableView:tv titleForHeaderInSection:s];
    return t.length ? t : nil;
}

- (UIFont *)cb5_font:(BOOL)footer {
    return footer ? [CBTheme font:13] : [CBTheme medium:13];
}

/// Lề chữ: thẳng chữ trong ô (ô nhóm iPhone cách mép 10, iPad 45)
- (CGFloat)cb5_inset {
    return [CBTheme isPad] ? 60 : 26;
}

- (CGFloat)cb5_height:(NSString *)t footer:(BOOL)footer width:(CGFloat)w {
    CGFloat textH = [CBTheme heightOf:t font:[self cb5_font:footer] width:w - 2 * [self cb5_inset]];
    return ceil(textH) + (footer ? 16 : 22);
}

- (UIView *)cb5_view:(NSString *)t footer:(BOOL)footer width:(CGFloat)w {
    CGFloat h = [self cb5_height:t footer:footer width:w], inset = [self cb5_inset];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    v.backgroundColor = [UIColor clearColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(inset, footer ? 6 : 14, w - 2 * inset, h - (footer ? 12 : 20))];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [CBTheme dim];
    l.font = [self cb5_font:footer];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentLeft;
    l.text = t;
    [v addSubview:l];
    return v;
}

- (UIView *)cb5_tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    NSString *t = [self cb5_title:tv section:s footer:NO];
    return t ? [self cb5_view:t footer:NO width:tv.bounds.size.width] : nil;
}

- (UIView *)cb5_tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    NSString *t = [self cb5_title:tv section:s footer:YES];
    return t ? [self cb5_view:t footer:YES width:tv.bounds.size.width] : nil;
}

- (CGFloat)cb5_tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s {
    NSString *t = [self cb5_title:tv section:s footer:NO];
    return t ? [self cb5_height:t footer:NO width:tv.bounds.size.width] : UITableViewAutomaticDimension;
}

- (CGFloat)cb5_tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    NSString *t = [self cb5_title:tv section:s footer:YES];
    return t ? [self cb5_height:t footer:YES width:tv.bounds.size.width] : UITableViewAutomaticDimension;
}

@end
