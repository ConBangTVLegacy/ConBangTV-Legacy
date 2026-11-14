#import <UIKit/UIKit.h>

/// «Ai đang xem?» — chọn người xem (mã PIN nếu có khoá). Hiện lúc mở app khi có nhiều người xem, hoặc bấm ảnh người xem.
@interface CBProfilesViewController : UIViewController
@property (nonatomic, copy) void (^onDone)(void);
@end
