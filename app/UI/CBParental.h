#import <UIKit/UIKit.h>
#import "CBWatchLimit.h"

#import "CBAlert.h"

/// Mã PIN phụ huynh + hết giờ xem (như CheckParent / LimitReached của bản Windows)
@interface CBParental : NSObject
/// Cần mã PIN phụ huynh: chưa có thì đặt mới (nhập 2 lần); có rồi thì hỏi. ok = đúng mã / vừa đặt xong
+ (void)checkParent:(NSString *)why done:(void (^)(BOOL ok))done;
/// Đặt / đổi mã PIN phụ huynh (nhập 2 lần)
+ (void)askNewParentPin:(void (^)(BOOL ok))done;
/// Hết giờ xem: người lớn nhập mã phụ huynh để cho xem thêm, rồi mở lại đúng tập (xem tiếp) từ host
+ (void)limitReached:(CBLimitBlock)block film:(NSString *)film episode:(NSString *)ep host:(UIViewController *)host;
@end
