#import <UIKit/UIKit.h>

#define CBRGB(h) [UIColor colorWithRed:(((h) >> 16) & 0xFF) / 255.0 green:(((h) >> 8) & 0xFF) / 255.0 blue:((h) & 0xFF) / 255.0 alpha:1]

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
+ (UIColor *)profileColor:(NSInteger)index;
+ (BOOL)isPad;
+ (UIFont *)font:(CGFloat)size;
+ (UIFont *)bold:(CGFloat)size;
/// Giao diện iOS 6 theo màu tối của app (thanh điều hướng, nút, bảng)
+ (void)apply;
+ (UIImage *)imageWithColor:(UIColor *)color;
/// Nút bo góc: primary = nền xanh của app, còn lại nền xám
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
