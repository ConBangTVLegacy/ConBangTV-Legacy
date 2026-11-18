#import <UIKit/UIKit.h>

/// Màn gốc của cửa sổ trên iPhone: chứa thanh điều hướng của app (content) và chỗ cho một thanh ở đáy màn hình — thanh thu nhỏ
/// của CBMiniPlayer. Có thanh thì cả app co lên trên thanh (không che nội dung, không phải chỉnh contentInset từng màn); bàn phím
/// hiện thì thanh nổi lên trên bàn phím. Màn được trình bày đè (trình phát, Cài đặt…) phủ cả thanh như phủ cả app.
/// iPad không dùng (khung thu nhỏ nổi ở góc, nằm trên màn gốc là thanh điều hướng như cũ).
@interface CBRootViewController : UIViewController
- (instancetype)initWithContent:(UIViewController *)content;
@property (nonatomic, readonly) UIViewController *content;
@property (nonatomic, readonly) UIView *bottomBar;
/// Gắn / bỏ thanh ở đáy (nil = bỏ). Thanh tự đặt khung, nằm trên nội dung.
- (void)setBottomBar:(UIView *)bar height:(CGFloat)height;
/// Đỉnh bàn phím trong toạ độ view (0 = không có bàn phím)
@property (nonatomic, readonly) CGFloat keyboardTop;
/// Bàn phím hiện / ẩn (khung nổi của CBMiniPlayer dời lên trên bàn phím)
@property (nonatomic, copy) void (^keyboardChanged)(NSTimeInterval duration);
/// Màn gốc của cửa sổ chính nếu là CBRootViewController (iPhone), không thì nil
+ (CBRootViewController *)current;
@end
