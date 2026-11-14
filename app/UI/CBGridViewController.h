#import <UIKit/UIKit.h>

/// Lưới phim: danh sách của trang (site.list, tự tải trang sau), tìm kiếm trên mọi trang (site.searchAll) hoặc danh sách có sẵn.
@interface CBGridViewController : UIViewController
- (instancetype)initWithListUrl:(NSString *)url title:(NSString *)title;
- (instancetype)initSearch;
- (instancetype)initWithItems:(NSArray *)items title:(NSString *)title;
/// Phim theo dõi (mở là kiểm tập mới; nhấn giữ: bỏ theo dõi) — như FollowsPage của bản Windows
- (instancetype)initFollows;
/// Xem tiếp / lịch sử (bấm: xem tiếp ngay; nhấn giữ: xoá khỏi lịch sử) — như HistoryPage của bản Windows
- (instancetype)initHistory;
/// Tìm ngay (lệnh gỡ lỗi / mở từ chỗ khác)
- (void)search:(NSString *)query;
@end
