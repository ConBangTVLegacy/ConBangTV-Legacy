#import <UIKit/UIKit.h>

/// Biểu tượng vẽ bằng mã (iOS 5 / 6 không có SF Symbols; ký tự ☰ ► ⌄ thiếu / khác nhau giữa các bản iOS). Mỗi biểu tượng là
/// đường vẽ SVG khung 24 × 24 (giống bản mẫu iOS 26 — design canvas), vẽ ra ảnh theo cỡ + màu, nhớ đệm.
///
/// Tên: home tv bookmark gear search back forward down up more play pause close list float back10 fwd10 swap star plus
/// sliders lock clock grid smile gauge next prev people trash info captions moon reload skip expand check radio globe
/// shield sync eyeoff refresh speaker
@interface CBIcon : NSObject
/// Ảnh biểu tượng `name` cỡ `size` điểm (vuông), màu `color`. filled = tô kín (biểu tượng tab đang chọn)
+ (UIImage *)named:(NSString *)name size:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)named:(NSString *)name size:(CGFloat)size color:(UIColor *)color filled:(BOOL)filled;
/// Đường vẽ SVG (lệnh M L H V C S Q T A Z, hoa / thường) → CGPath (khung gốc)
+ (CGPathRef)newPathFromSVG:(NSString *)d CF_RETURNS_RETAINED;
@end
