#import <UIKit/UIKit.h>

/// Bảng chọn kiểu iOS 26 (menu kính) — cùng API UIActionSheet (initWithTitle:delegate:…, addButtonWithTitle:,
/// cancelButtonIndex, destructiveButtonIndex, showInView:, showFromRect:inView:animated:) nên chỗ gọi chỉ đổi tên lớp; đại biểu
/// (actionSheet:clickedButtonAtIndex: / willDismiss / didDismiss) gọi như UIActionSheet.
///  • iPhone: thẻ kính ở đáy màn hình + nút Huỷ riêng bên dưới; chạm ra ngoài = Huỷ.
///  • iPad: thẻ kính cạnh ô / nút gọi ra (showFromRect:), không có nút Huỷ (chạm ra ngoài = Huỷ, như popover).
/// Chữ nút bắt đầu bằng «✓ » = mục đang chọn: bỏ dấu, vẽ dấu kiểm bên phải.
@interface CBSheet : UIActionSheet
/// Bảng đang hiện trên cùng (lệnh gỡ lỗi «sheet»)
+ (CBSheet *)visibleSheet;
/// Bấm nút như người dùng chạm (gọi đại biểu rồi đóng)
- (void)tapIndex:(NSInteger)index;
@end
