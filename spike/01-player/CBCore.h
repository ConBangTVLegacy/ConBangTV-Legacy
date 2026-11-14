#import <Foundation/Foundation.h>

/// Lõi Rust chung của bản Windows / Linux (ChimToTV linux/core + linux/ffi, dựng cho iOS 6 → libconbang_core.a).
/// Giao tiếp bằng JSON như bản Windows (windows/ConBangTV/Core/Native.cs).
@interface CBCore : NSObject
/// Mở lõi một lần: thư mục dữ liệu Documents/cbtv-core, chứng chỉ gốc Mozilla đóng kèm (SSL_CERT_FILE → rustls-native-certs).
+ (BOOL)start;
/// Hàm nhanh, chờ kết quả: trả {"ok": …} hoặc {"err": "…"}
+ (NSDictionary *)callSync:(NSString *)method args:(NSDictionary *)args;
/// Hàm chạy nền: done(ok, err) gọi trên luồng chính; part(…) cho kết quả từng phần / tiến độ (có thể nil)
+ (void)call:(NSString *)method args:(NSDictionary *)args part:(void (^)(id part))part done:(void (^)(id ok, NSString *err))done;
@end
