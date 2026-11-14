#import <UIKit/UIKit.h>

/// Trang phim: ảnh, tên, thông tin, nút Xem / Xem tiếp + Theo dõi, chọn bản (Vietsub / Thuyết Minh…), lưới tập, mô tả.
/// item: {url, title, poster} (từ hàng / lưới phim).
@interface CBDetailViewController : UIViewController
- (instancetype)initWithItem:(NSDictionary *)item;
@end
