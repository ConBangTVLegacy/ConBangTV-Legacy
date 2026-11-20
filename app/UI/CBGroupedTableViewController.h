#import <UIKit/UIKit.h>

/// Bảng nhóm nền tối kiểu iOS 26 (Cài đặt, Đồng bộ, Proxy, Giới hạn giờ xem, Cài đặt truyền hình):
///  • ô của nhóm là ảnh bo góc theo vị trí (đầu / giữa / cuối / một mình, bán kính 18) + đường kẻ mảnh giữa các ô — iOS 7+ (bảng
///    nhóm tràn mép) thì ô vuông góc; mũi tên «›» vẽ bằng CBIcon.
///  • chữ đầu / cuối mục (titleForHeader / titleForFooter) nhỏ, màu nhạt, canh trái. iOS 6: sửa nhãn có sẵn (willDisplayHeaderView).
///    iOS 5 chưa có hàm đó → tự vẽ nhãn (viewForHeaderInSection — chỉ gắn lúc chạy trên iOS 5, iOS 6 giữ nhãn của hệ thống).
/// Lớp con có tableView:willDisplayCell:forRowAtIndexPath: thì gọi super.
@interface CBGroupedTableViewController : UITableViewController
/// Ô vuông màu có biểu tượng trắng (đầu dòng kiểu Cài đặt của iOS) — 29 × 29
+ (UIImage *)rowIcon:(NSString *)icon color:(UIColor *)color;
@end
