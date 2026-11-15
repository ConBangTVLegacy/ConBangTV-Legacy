#import <UIKit/UIKit.h>

/// Tải ảnh bìa: NSURLConnection tin thêm gốc Mozilla đóng kèm (cacert.pem — iOS 6 không có gốc Let's Encrypt), lưu đĩa
/// (Library/Caches/img), giải mã thu nhỏ đúng cỡ ô (ImageIO) để đỡ RAM, bộ nhớ đệm NSCache, tối đa 4 ảnh tải cùng lúc.
@interface CBImages : NSObject
/// Đặt ảnh url vào iv (cỡ điểm size); ô tái sử dụng đổi url thì kết quả cũ bị bỏ.
+ (void)load:(NSString *)url size:(CGSize)size into:(UIImageView *)iv;
+ (void)cancel:(UIImageView *)iv;
/// Mỏ neo tin cậy (SecCertificateRef) từ cacert.pem — dùng chung cho mọi kết nối NSURLConnection của app
+ (NSArray *)anchors;
/// Xử lý thử thách TLS bằng gốc của máy + gốc Mozilla đóng kèm
+ (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge;
+ (void)clearMemory;
/// Số ảnh đang tải / chờ / xong / hỏng (gỡ lỗi)
+ (NSString *)debugStatus;
/// Dung lượng ảnh bìa lưu trên máy (byte) / xoá hết (cả bộ đệm trong RAM)
+ (unsigned long long)diskBytes;
+ (void)clearDisk;
@end
