#import <UIKit/UIKit.h>

/// «Ai đang xem?» — chọn người xem (mã PIN nếu có khoá). Hiện lúc mở app khi có nhiều người xem, hoặc bấm ảnh người xem.
@interface CBProfilesViewController : UIViewController
@property (nonatomic, copy) void (^onDone)(void);
/// Có nút «✕ Đóng» (mở từ trang chủ / Cài đặt); lúc mở app thì không — phải chọn người xem
@property (nonatomic) BOOL closable;
@end
