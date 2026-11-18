#import <UIKit/UIKit.h>

/// Gửi khi purgeOffscreen: ô ảnh bìa đang khuất bỏ ảnh (CBPosterCell)
extern NSString *const CBImagesPurgeNotification;

/// Khung ảnh có nhãn chờ nằm dưới (tên phim / chữ viết tắt tên kênh): có ảnh thì ẩn nhãn — khỏi vẽ chữ thừa mỗi lần ô hiện lên
/// khi cuộn, và chữ không lòi ra sau phần trong suốt của logo
@interface CBCoverView : UIImageView
@property (nonatomic, weak) UIView *placeholder;
@end

/// Tải ảnh bìa: NSURLConnection tin thêm gốc Mozilla đóng kèm (cacert.pem — iOS 6 không có gốc Let's Encrypt), lưu đĩa
/// (Library/Caches/img), giải mã thu nhỏ đúng cỡ ô (ImageIO) để đỡ RAM, bộ nhớ đệm NSCache, tối đa 4 ảnh tải cùng lúc.
@interface CBImages : NSObject
/// Đặt ảnh url vào iv (cỡ điểm size); ô tái sử dụng đổi url thì kết quả cũ bị bỏ.
+ (void)load:(NSString *)url size:(CGSize)size into:(UIImageView *)iv;
/// Như trên, nhưng ảnh giải mã sẵn đúng khổ `size` (cắt kiểu Aspect Fill) và bo góc `radius` điểm ngay trong ảnh (góc trong suốt):
/// khung ảnh khỏi cần cornerRadius + clipsToBounds — thứ bắt GPU vẽ ngoài màn hình ở mọi khung hình, ô danh sách cuộn giật
+ (void)load:(NSString *)url size:(CGSize)size radius:(CGFloat)radius into:(UIImageView *)iv;
+ (void)cancel:(UIImageView *)iv;
/// Mỏ neo tin cậy (SecCertificateRef) từ cacert.pem — dùng chung cho mọi kết nối NSURLConnection của app
+ (NSArray *)anchors;
/// Xử lý thử thách TLS bằng gốc của máy + gốc Mozilla đóng kèm
+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge;
+ (void)clearMemory;
/// Máy RAM thấp (≤ 256 MB: iPad 1, iPhone 3GS / 4) — phát video ở đó chiếm ~65 MB bộ nhớ hệ thống, app phải nhường
+ (BOOL)lowRam;
/// Bỏ ảnh bìa đã giải mã ở các màn đang khuất (ô không nằm trong cửa sổ — vd dưới trình phát) và bộ đệm RAM; ô hiện lại thì
/// tự nạp lại từ đĩa. Gọi khi mở trình phát trên máy RAM thấp và khi có cảnh báo thiếu bộ nhớ.
+ (void)purgeOffscreen;
/// Số ảnh đang tải / chờ / xong / hỏng (gỡ lỗi)
+ (NSString *)debugStatus;
/// Dung lượng ảnh bìa lưu trên máy (byte) / xoá hết (cả bộ đệm trong RAM)
+ (unsigned long long)diskBytes;
+ (void)clearDisk;
@end
