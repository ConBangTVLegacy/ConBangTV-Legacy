#import <UIKit/UIKit.h>

/// Thể loại / Quốc gia của trang đang chọn (trang API kiểu KKPhim: api.filters; trang «next»: next.filters): lưới nút, chọn một
/// mục thì mở lưới phim của mục đó. Giống FilterPage của bản Windows.
@interface CBFilterViewController : UIViewController
- (instancetype)initGenres:(BOOL)genres;
/// Trang đang chọn có bộ lọc không (để hiện nút «Thể loại» / «Quốc gia»)
+ (BOOL)available;
/// Mở mục thứ i (gỡ lỗi: lệnh «pick <số>»)
- (void)openAt:(NSInteger)i;
@end
