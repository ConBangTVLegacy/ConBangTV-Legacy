#import <UIKit/UIKit.h>

/// Màn chính: «Xem tiếp», «Có tập mới» + trang chủ tổng hợp của lõi (home.makePlan / home.cached / home.load / home.late)
/// hoặc trang chủ của trang đang dùng (site.homeOf), cuối cùng là danh mục.
@interface CBHomeViewController : UITableViewController
- (void)reload;
/// Các hàng đang hiện: @[@{id, title, items: @[@{url, title, …}]}] (lệnh gỡ lỗi)
- (NSArray *)rows;
/// Mở phim thứ i của hàng r như khi chạm (lệnh gỡ lỗi)
- (void)openRow:(NSInteger)r item:(NSInteger)i;
/// Mở nút thứ i của dải danh mục đầu trang
- (void)openCategoryAt:(NSInteger)i;
@end
