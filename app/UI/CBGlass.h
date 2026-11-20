#import <UIKit/UIKit.h>

/// Chất liệu «kính» kiểu iOS 26 (Liquid Glass) cho lớp nổi trên nội dung: thanh tab, nút tròn trên đầu màn, thanh thu nhỏ,
/// menu, hộp thoại, nút của trình phát. iOS 5 / 6 không làm mờ được thứ nằm dưới → «kính giả»: ảnh kéo giãn vẽ sẵn (nền tối gần
/// đặc + ánh bóng chéo + viền sáng mảnh + vệt sáng mép trên + bóng đổ), nhớ đệm theo bán kính — GPU chỉ dán ảnh, không có lớp
/// bo góc / bóng đổ tính lại mỗi khung (xem CBTheme imageWithColor:radius:). Máy yếu (CBTheme lite — iPad 1) không có bóng đổ.
typedef NS_ENUM(NSInteger, CBGlassStyle) {
    CBGlassBar = 0,     // thanh, nút nổi
    CBGlassHeavy,       // menu, hộp thoại (đặc hơn, bóng đậm hơn)
    CBGlassPressed,     // nút kính đang bị chạm
};

/// Kiểu nút viên thuốc (bo tròn hai đầu theo chiều cao)
typedef NS_ENUM(NSInteger, CBPillStyle) {
    CBPillSubtle = 0,   // nền trắng mờ 9 % — nút trong nội dung (chip, «Từ tập đầu»)
    CBPillProminent,    // xanh của app, chữ tối — nút chính («Xem tiếp»)
    CBPillGlass,        // kính — nút nổi trên nội dung / video
    CBPillDanger,       // đỏ — «Xoá»
    CBPillSelected,     // chip đang chọn: nền sáng, chữ tối
};

@interface CBGlass : NSObject
/// Ảnh kính kéo giãn, bán kính `radius` (khung ảnh rộng hơn khung thật `margin` mỗi phía để chứa bóng đổ)
+ (UIImage *)image:(CGFloat)radius style:(CBGlassStyle)style;
/// Lề bóng đổ quanh ảnh kính (0 trên máy yếu)
+ (CGFloat)margin;
/// Ảnh viên thuốc / khối bo góc phẳng có ánh bóng (nút chính, nút đỏ) — không bóng đổ
+ (UIImage *)pill:(CGFloat)radius color:(UIColor *)color sheen:(BOOL)sheen;
@end

/// Mảng kính: UIView có nền là ảnh kính (tràn ra ngoài khung để vẽ bóng đổ — clipsToBounds = NO). Con đặt như view thường.
@interface CBGlassView : UIView
- (instancetype)initWithFrame:(CGRect)frame radius:(CGFloat)radius style:(CBGlassStyle)style;
@property (nonatomic) CGFloat radius;      // < 0 = viên thuốc (bán kính = nửa chiều cao, tự theo khung)
@property (nonatomic) CBGlassStyle style;
@end

/// Nút viên thuốc: ảnh nền tự vẽ lại theo chiều cao (bo tròn hai đầu), sáng hơn khi chạm. Có biểu tượng (CBIcon) và / hoặc chữ.
@interface CBPillButton : UIButton
+ (instancetype)pill:(NSString *)title style:(CBPillStyle)style;
/// Nút tròn kính chỉ có biểu tượng (cỡ biểu tượng ~ 45 % đường kính)
+ (instancetype)circle:(NSString *)icon diameter:(CGFloat)d;
@property (nonatomic) CBPillStyle style;
/// Bán kính cố định (mặc định < 0 = nửa chiều cao)
@property (nonatomic) CGFloat radius;
/// Đặt biểu tượng (tên CBIcon) theo màu chữ hiện tại; size 0 = tự chọn theo chiều cao
- (void)setIcon:(NSString *)icon size:(CGFloat)size;
@end

/// Công tắc kiểu iOS 26 (rãnh viên thuốc 54 × 32, núm dẹt trắng) — thay UISwitch (iOS 5 / 6 vẽ công tắc bóng «I / O»).
/// Cùng các thuộc tính chỗ gọi dùng: on / isOn, setOn:animated:, enabled, gửi UIControlEventValueChanged khi người dùng đổi.
@interface CBSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end
