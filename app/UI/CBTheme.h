#import <UIKit/UIKit.h>

#define CBRGB(h) [UIColor colorWithRed:(((h) >> 16) & 0xFF) / 255.0 green:(((h) >> 8) & 0xFF) / 255.0 blue:((h) & 0xFF) / 255.0 alpha:1]

@class CBRoundLabel;

/// Màu / chữ / nút chung — cùng bảng màu bản iPad (ios/ConBangTV/Sources/UI/Theme.swift)
@interface CBTheme : NSObject
+ (UIColor *)bg;
+ (UIColor *)surface;
+ (UIColor *)surface2;
+ (UIColor *)text;
+ (UIColor *)dim;
+ (UIColor *)brand;
+ (UIColor *)onBrand;
+ (UIColor *)focus;
+ (UIColor *)watched;
/// Chữ màu nhấn trên nền tối (xanh sáng hơn brand — đủ tương phản cho chữ nhỏ)
+ (UIColor *)accent;
/// Đỏ của nút xoá / chữ cảnh báo
+ (UIColor *)danger;
+ (UIColor *)dangerText;
/// Nền mờ của nút / chip trong nội dung (trắng 9 %)
+ (UIColor *)fill;
/// Đường kẻ mảnh giữa các dòng
+ (UIColor *)separator;
/// Máy yếu (RAM < 400 MB — iPad 1): bỏ bóng đổ của kính, bỏ nền ảnh bìa làm mờ ở trang phim
+ (BOOL)lite;
+ (UIColor *)profileColor:(NSInteger)index;
+ (BOOL)isPad;
+ (UIFont *)font:(CGFloat)size;
+ (UIFont *)bold:(CGFloat)size;
/// Chữ đậm vừa (Helvetica Neue Medium — có từ iOS 5)
+ (UIFont *)medium:(CGFloat)size;
/// Bàn phím tối cho ô tìm (UISearchBar của iOS 5 / 6 chưa có keyboardAppearance — đặt cho ô chữ bên trong)
+ (void)darkKeyboard:(UISearchBar *)bar;
/// Giao diện iOS 6 theo màu tối của app (thanh điều hướng, nút, bảng)
+ (void)apply;
+ (UIImage *)imageWithColor:(UIColor *)color;
/// Bo góc KHÔNG dùng layer.cornerRadius. cornerRadius + clipsToBounds bắt GPU vẽ lớp ngoài màn hình ở mọi khung hình (iPad mini 1
/// iOS 8: trang chủ 14 khung/s); iOS 5 tốn cả khi chỉ bo nền không cắt (iPad 1: lưới kênh 11 → 30 khung/s khi bỏ bo góc). Dùng thay:
///  • nút / khung / thẻ: ảnh bo góc kéo giãn được (setBackgroundImage, hoặc UIImageView làm nền) — ảnh dùng chung, nhớ đệm theo
///    màu + bán kính (+ viền)
+ (UIImage *)imageWithColor:(UIColor *)color radius:(CGFloat)radius;
+ (UIImage *)imageWithColor:(UIColor *)color radius:(CGFloat)radius border:(UIColor *)border width:(CGFloat)width;
///  • nhãn có màu nền: CBRoundLabel (dưới)
+ (CBRoundLabel *)roundLabel:(UIColor *)fill radius:(CGFloat)radius;
/// Nút viên thuốc (CBPillButton): primary = nền xanh của app (chữ tối), còn lại nền trắng mờ
+ (UIButton *)button:(NSString *)title primary:(BOOL)primary;
/// Vòng tròn màu có chữ cái đầu tên người xem
+ (UIView *)avatarFor:(NSDictionary *)profile size:(CGFloat)size;
/// Nhãn nhiều dòng màu mờ (báo lỗi / trống)
+ (UILabel *)messageLabel;
/// Chiều cao chữ nhiều dòng (sizeWithFont — iOS 6 chưa có boundingRectWithSize)
+ (CGFloat)heightOf:(NSString *)text font:(UIFont *)font width:(CGFloat)width;
/// «01:23:45» / «23:45»
+ (NSString *)time:(double)seconds;
/// Lời báo ngắn ở cuối màn hình (tự ẩn sau vài giây; lời mới thay lời cũ)
+ (void)toast:(NSString *)text;
/// Đặt UISegmentedControl (nằm trong strip) vừa khung: đủ chỗ thì chia đều; nhiều bản không đủ chỗ (chữ bị cắt «Thuyết…»)
/// thì mỗi nút rộng theo chữ, strip cuộn ngang
+ (void)layoutSegments:(UISegmentedControl *)seg inStrip:(UIScrollView *)strip frame:(CGRect)frame;
@end

/// Dấu «phát» đặt trước chữ nút: iOS 6 «▶︎» (kèm ký tự chọn kiểu chữ U+FE0E); iOS 5 không hiểu U+FE0E (hiện ô vuông) và vẽ ▶
/// thành emoji xanh → «►»
NSString *CBPlayIcon(void);

/// Nhãn có nền bo góc vẽ thẳng vào nội dung của nhãn (drawRect) — GPU chỉ dán một ảnh, không lớp bo góc nào (xem
/// imageWithColor:radius:). Màu nền bo góc là fillColor; backgroundColor luôn trong suốt (gán gì cũng bỏ qua).
@interface CBRoundLabel : UILabel
@property (nonatomic) CGFloat radius;
@property (nonatomic, strong) UIColor *fillColor;
@end
