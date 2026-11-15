#import <Foundation/Foundation.h>

/// Lõi Rust chung của Côn Bằng TV (repo chính: linux/core + linux/ffi, dựng cho iOS 6 → libconbang_core.a). Giao tiếp bằng JSON
/// như bản Windows (windows/ConBangTV/Core/Native.cs): tên hàm «nhóm.hàm», tham số là một object.
@interface CBCore : NSObject
/// Mở lõi một lần lúc mở app: thư mục dữ liệu Documents/cbtv-core, chứng chỉ gốc Mozilla đóng kèm (SSL_CERT_FILE → rustls).
+ (BOOL)start;
/// Hàm nhanh, chờ kết quả ngay: trả phần «ok» (null → nil). Lỗi → nil, ghi log, *error = câu báo lỗi.
+ (id)sync:(NSString *)method args:(NSDictionary *)args error:(NSString **)error;
+ (id)sync:(NSString *)method args:(NSDictionary *)args;
/// Hàm chạy nền (mạng): done(ok, err) gọi trên luồng chính. part: kết quả từng phần / tiến độ (có thể nil).
+ (void)call:(NSString *)method args:(NSDictionary *)args part:(void (^)(id part))part done:(void (^)(id ok, NSString *err))done;
+ (void)call:(NSString *)method args:(NSDictionary *)args done:(void (^)(id ok, NSString *err))done;
/// Báo lõi cài đặt mạng vừa đổi (DNS mã hoá, vượt chặn, proxy) — mở cổng nội bộ mới
+ (void)networkSettingsChanged;
/// Quay lại app: iOS thu hồi cổng nghe 127.0.0.1 của app nằm nền lâu (cổng nội bộ — đường ra mạng của lõi — và cổng phát)
/// → mở lại (bản vá patches/0002, hàm net.revive). Gọi mỗi lần app hoạt động lại; cổng còn sống thì không làm gì.
+ (void)reviveLocalPorts;
@end

/// Câu báo lỗi của lõi để hiện cho người xem: bỏ dấu máy «socks|» / «ss|» lõi gắn vào đầu (lỗi qua proxy); nil → @"".
/// CBCore đã làm sạch lỗi trả về cho call / sync — hàm này cho chỗ ghép câu từ lỗi lấy nơi khác.
NSString *CBCleanError(NSString *err);
