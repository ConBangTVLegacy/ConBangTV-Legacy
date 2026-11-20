#import <UIKit/UIKit.h>

/// Đầu màn gốc của tab (thanh điều hướng ẩn): iPhone — tiêu đề lớn canh trái + nút kính bên phải; iPad — hàng nút ngang hàng thanh
/// tab nổi ở giữa mép trên (không chữ tiêu đề: tab đang chọn đã ghi). Đặt làm tableHeaderView / view trên cùng của màn; cuộn đi
/// cùng nội dung. Đã chừa chỗ thanh trạng thái (iOS 7+).
@interface CBTabHeader : UIView
- (instancetype)initWithTitle:(NSString *)title;
@property (nonatomic, copy) NSString *title;
/// Nút kính bên trái (iPad) / cạnh trái nhóm nút bên phải (iPhone)
@property (nonatomic, copy) NSArray *leftItems;
@property (nonatomic, copy) NSArray *rightItems;
/// Chiều cao phần đầu (hàng tiêu đề + chỗ thanh trạng thái)
+ (CGFloat)height;
/// Nhóm nút biểu tượng chung một viên kính (vd «+» và «⚙︎» của Truyền hình); selectors là chuỗi tên hàm
+ (UIView *)groupWithIcons:(NSArray *)icons target:(id)target actions:(NSArray *)selectors labels:(NSArray *)labels;
/// Nút tròn kính có ảnh đại diện người xem ở giữa
+ (UIButton *)avatarButton:(NSDictionary *)profile target:(id)target action:(SEL)action;
@end
