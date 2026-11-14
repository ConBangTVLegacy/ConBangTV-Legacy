#import <UIKit/UIKit.h>

/// Màn chính: «Xem tiếp», «Có tập mới» + trang chủ tổng hợp của lõi (home.makePlan / home.cached / home.load / home.late)
/// hoặc trang chủ của trang đang dùng (site.homeOf), cuối cùng là danh mục.
@interface CBHomeViewController : UITableViewController
- (void)reload;
@end
