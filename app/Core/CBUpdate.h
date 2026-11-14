#import <Foundation/Foundation.h>

/// Cập nhật OTA từ GitHub Releases (ConBangTVLegacy/ConBangTV-Legacy, bản mới nhất có tệp .deb iphoneos-arm): kiểm lúc mở app
/// và khi quay lại app (tối đa 6 giờ một lần), hỏi trước khi cập nhật; tải .deb qua lõi (rustls — iOS 6 không tự vào được
/// GitHub), kiểm SHA-256 GitHub ghi sẵn, rồi gọi /usr/libexec/conbangtv/cbupdate (root, setuid) để dpkg -i và mở lại app.
@interface CBUpdate : NSObject
/// Gọi một lần lúc mở app
+ (void)start;
/// Cài đặt → Phiên bản: kiểm ngay, báo cả khi đang dùng bản mới nhất
+ (void)checkManual;
@end
