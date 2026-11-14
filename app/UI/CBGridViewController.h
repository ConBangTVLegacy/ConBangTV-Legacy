#import <UIKit/UIKit.h>

/// Lưới phim: danh sách của trang (site.list, tự tải trang sau), tìm kiếm trên mọi trang (site.searchAll) hoặc danh sách có sẵn.
@interface CBGridViewController : UIViewController
- (instancetype)initWithListUrl:(NSString *)url title:(NSString *)title;
- (instancetype)initSearch;
- (instancetype)initWithItems:(NSArray *)items title:(NSString *)title;
/// Tìm ngay (lệnh gỡ lỗi / mở từ chỗ khác)
- (void)search:(NSString *)query;
@end
