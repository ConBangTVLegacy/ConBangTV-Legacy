#import <UIKit/UIKit.h>

/// Bảng nhóm nền tối (Cài đặt, Đồng bộ, Proxy, Giới hạn giờ xem): chữ đầu / cuối mục (titleForHeader / titleForFooter) màu nhạt,
/// không bóng. iOS 6: đổi màu nhãn có sẵn (willDisplayHeaderView). iOS 5 chưa có hàm đó → tự vẽ nhãn (viewForHeaderInSection —
/// chỉ gắn lúc chạy trên iOS 5, iOS 6 giữ nguyên nhãn của hệ thống).
@interface CBGroupedTableViewController : UITableViewController
@end
