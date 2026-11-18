#import <UIKit/UIKit.h>

/// Hộp thoại dùng khối, cùng API UIAlertView (title, message, alertViewStyle, textFieldAtIndex:, cancelButtonIndex,
/// buttonTitleAtIndex:, show, dismissWithClickedButtonIndex:animated:) nên chỗ gọi không phải đổi.
///  • iOS 5 / 6: UIAlertView của hệ thống (nhanh).
///  • iOS 7+: hộp tự vẽ trong cửa sổ riêng — không nền làm mờ, không autolayout. UIAlertView của iOS 8 (dựng trên
///    UIAlertController) hiện mất 0,4–1,3 s trên iPad mini 1 (A5), luồng chính khựng tới 0,9 s (đo 18/11/2026).
@interface CBAlert : UIAlertView <UIAlertViewDelegate, UITextFieldDelegate>
+ (CBAlert *)title:(NSString *)title message:(NSString *)message cancel:(NSString *)cancel others:(NSArray *)others
              done:(void (^)(CBAlert *alert, NSInteger index))done;
/// Nút `index` là nút thứ mấy trong `others` (0, 1…); -1 = nút huỷ. Đừng dùng firstOtherButtonIndex: nút «others» thêm bằng
/// addButtonWithTitle nên UIAlertView của iOS 5 / 6 để nó là -1 (lệch hai nút)
- (NSInteger)otherIndex:(NSInteger)index;
/// Chạy `block` khi hộp đã đóng hẳn (hết hiệu ứng) — để mở hộp / màn khác ngay sau hộp này, thay cho chờ cứng một khoảng.
/// Hộp đã đóng rồi thì chạy ở lượt sau của vòng chạy.
- (void)afterDismiss:(dispatch_block_t)block;
/// Hộp tự vẽ đang hiện trên cùng (iOS 7+; iOS 5 / 6 luôn nil) — cho lệnh gỡ lỗi «alert»
+ (CBAlert *)visibleOwnAlert;
/// Hộp nhập mã PIN 4 số (ẩn chữ, bàn phím số); pin = nil khi bấm Huỷ
+ (void)askPin:(NSString *)title message:(NSString *)message done:(void (^)(NSString *pin))done;
@end
