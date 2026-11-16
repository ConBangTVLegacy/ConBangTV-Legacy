#import "CBGroupedTableViewController.h"

/// Giới hạn giờ xem (đã nhập mã PIN phụ huynh). Không truyền người xem: danh sách người xem + tóm tắt giới hạn, đổi / xoá mã
/// phụ huynh; có người xem: chọn số phút mỗi ngày và giờ đi ngủ của người đó (như LimitsPage của bản Windows).
@interface CBLimitsViewController : CBGroupedTableViewController
- (instancetype)initWithProfile:(NSString *)pid;
@end
