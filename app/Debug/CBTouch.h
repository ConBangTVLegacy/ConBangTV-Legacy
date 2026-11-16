#import <UIKit/UIKit.h>

/// Chỉ có trong bản thử: giả lập chạm đi qua đường xử lý chạm thật của UIKit (xem CBTouch.m). Toạ độ: điểm trong cửa sổ.
@interface CBTouch : NSObject
+ (void)tapAt:(CGPoint)p;
+ (void)holdAt:(CGPoint)p seconds:(double)s;
+ (void)dragFrom:(CGPoint)a to:(CGPoint)b seconds:(double)s;
@end
