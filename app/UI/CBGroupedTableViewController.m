#import "CBGroupedTableViewController.h"
#import "CBCompat.h"
#import "CBTheme.h"
#import <objc/runtime.h>

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

#pragma mark - iOS 6

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *h = (UITableViewHeaderFooterView *)view;
        h.textLabel.textColor = [CBTheme dim];
        h.textLabel.shadowColor = [UIColor clearColor];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [self tableView:tableView willDisplayHeaderView:view forSection:section];
}

#pragma mark - iOS 5 (gắn ở +initialize)

- (NSString *)cb5_title:(UITableView *)tv section:(NSInteger)s footer:(BOOL)footer {
    SEL sel = footer ? @selector(tableView:titleForFooterInSection:) : @selector(tableView:titleForHeaderInSection:);
    if (![self respondsToSelector:sel]) return nil;
    NSString *t = footer ? [self tableView:tv titleForFooterInSection:s] : [self tableView:tv titleForHeaderInSection:s];
    return t.length ? t : nil;
}

- (UIFont *)cb5_font:(BOOL)footer {
    return footer ? [CBTheme font:15] : [CBTheme bold:17];
}

/// Lề chữ như nhãn mặc định của bảng nhóm (iPad lề rộng hơn)
- (CGFloat)cb5_inset {
    return [CBTheme isPad] ? 55 : 20;
}

- (CGFloat)cb5_height:(NSString *)t footer:(BOOL)footer width:(CGFloat)w {
    CGFloat textH = [CBTheme heightOf:t font:[self cb5_font:footer] width:w - 2 * [self cb5_inset]];
    return ceil(textH) + (footer ? 18 : 16);
}

- (UIView *)cb5_view:(NSString *)t footer:(BOOL)footer width:(CGFloat)w {
    CGFloat h = [self cb5_height:t footer:footer width:w], inset = [self cb5_inset];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    v.backgroundColor = [UIColor clearColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(inset, footer ? 6 : 10, w - 2 * inset, h - 16)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [CBTheme dim];
    l.font = [self cb5_font:footer];
    l.numberOfLines = 0;
    l.textAlignment = footer ? NSTextAlignmentCenter : NSTextAlignmentLeft;
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
