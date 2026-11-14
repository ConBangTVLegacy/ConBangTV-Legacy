#import <UIKit/UIKit.h>

/// Proxy (Cài đặt → Proxy): SOCKS5 hoặc Shadowsocks — bật / tắt, máy chủ, cổng, tài khoản / khoá, dán link ss://, DNS qua
/// proxy, chỉ trang phim, thử kết nối. Lõi đọc cùng khoá với bản Windows / TV / iPad (proxy_*, ss_*; mật khẩu / khoá trong
/// secret.json của lõi). Proxy lỗi thì báo lỗi chứ không lặng lẽ đi thẳng. Đổi xong có hiệu lực ngay (cả trình phát, ảnh).
@interface CBProxyViewController : UITableViewController
/// Tóm tắt cho dòng ở Cài đặt: «Tắt», «SOCKS5 1.2.3.4:1080», «Shadowsocks host:port»
+ (NSString *)summary;
@end
