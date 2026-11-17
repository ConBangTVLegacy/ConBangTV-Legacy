#import <UIKit/UIKit.h>
#import "CBWatchLimit.h"

/// Hộp thoại UIAlertView dùng khối (iOS 6 chưa có UIAlertController)
@interface CBAlert : UIAlertView <UIAlertViewDelegate>
+ (CBAlert *)title:(NSString *)title message:(NSString *)message cancel:(NSString *)cancel others:(NSArray *)others
              done:(void (^)(CBAlert *alert, NSInteger index))done;
/// Nút `index` là nút thứ mấy trong `others` (0, 1…); -1 = nút huỷ. Đừng dùng firstOtherButtonIndex: nút «others» thêm bằng
/// addButtonWithTitle nên UIAlertView của iOS 5 / 6 để nó là -1 (lệch hai nút)
- (NSInteger)otherIndex:(NSInteger)index;
/// Hộp nhập mã PIN 4 số (ẩn chữ, bàn phím số); pin = nil khi bấm Huỷ
+ (void)askPin:(NSString *)title message:(NSString *)message done:(void (^)(NSString *pin))done;
@end

/// Mã PIN phụ huynh + hết giờ xem (như CheckParent / LimitReached của bản Windows)
@interface CBParental : NSObject
/// Cần mã PIN phụ huynh: chưa có thì đặt mới (nhập 2 lần); có rồi thì hỏi. ok = đúng mã / vừa đặt xong
+ (void)checkParent:(NSString *)why done:(void (^)(BOOL ok))done;
/// Đặt / đổi mã PIN phụ huynh (nhập 2 lần)
+ (void)askNewParentPin:(void (^)(BOOL ok))done;
/// Hết giờ xem: người lớn nhập mã phụ huynh để cho xem thêm, rồi mở lại đúng tập (xem tiếp) từ host
+ (void)limitReached:(CBLimitBlock)block film:(NSString *)film episode:(NSString *)ep host:(UIViewController *)host;
@end
