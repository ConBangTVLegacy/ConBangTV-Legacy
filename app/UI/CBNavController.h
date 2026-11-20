#import <UIKit/UIKit.h>

/// Thanh điều hướng của app: iPhone đứng dọc (trình phát tự xoay ngang), iPad xoay mọi chiều.
/// Kiểu iOS 26: thanh liền màu nền (không viền, không bóng), nút là viên / vòng kính (CBPillButton) — nút chữ / ảnh của màn
/// (UIBarButtonItem thường) tự đổi sang kính lúc màn hiện; màn đẩy vào có nút quay lại tròn «‹».
/// tabRoot = thanh của một tab (CBRootViewController): màn gốc ẩn thanh (màn tự vẽ tiêu đề lớn — CBTabHeader).
@interface CBNavController : UINavigationController <UINavigationControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic) BOOL tabRoot;
/// Đổi các nút của màn sang kính (gọi lại khi màn đặt nút mới sau lúc hiện)
+ (void)glassify:(UIViewController *)vc inNav:(UINavigationController *)nav;
@end
