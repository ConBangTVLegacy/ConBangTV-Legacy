#import <UIKit/UIKit.h>

@class CBNavController;

@interface CBAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
/// Thanh điều hướng của tab đang chọn (CBRootViewController) — chỗ đẩy / trình bày màn mới
@property (nonatomic, readonly) CBNavController *nav;
@end
