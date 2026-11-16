#import <UIKit/UIKit.h>

/// Lịch phát sóng của một kênh (từ EPG / XMLTV của danh sách): Hôm qua / Hôm nay / Ngày mai, chương trình đang phát nổi lên,
/// «Nhắc tôi» đặt thông báo của iOS (UILocalNotification) 5 phút trước giờ phát — báo cả khi app đang đóng; chạm thông báo mở
/// kênh đó (CBAppDelegate).
@interface CBTVGuideViewController : UITableViewController
- (instancetype)initWithChannel:(NSDictionary *)channel;
/// Mở từ trình phát (đè lên): «Xem trực tiếp» / «Đóng» chỉ đóng màn này
@property (nonatomic) BOOL fromPlayer;
@end
