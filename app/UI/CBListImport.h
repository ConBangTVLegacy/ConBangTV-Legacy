#import <Foundation/Foundation.h>

/// Thêm danh sách kênh (Truyền hình): theo địa chỉ, **gửi tệp .m3u từ máy tính qua Wi-Fi** (app mở trang nhận tệp
/// http://<địa chỉ Wi-Fi của máy>:8790 tới khi đóng hộp), **tệp .m3u / .m3u8 có trên máy** (chép vào bằng Filza, iFunBox, SSH…),
/// hoặc «Mở bằng Côn Bằng TV» từ Mail / Filza (CBAppDelegate). Danh sách từ tệp chép vào app (CBIPTV addListWithData:…).
@interface CBListImport : NSObject
/// Hộp chọn cách thêm; done(danh sách mới) ngay khi đã thêm (danh sách đọc / tải nền)
+ (void)ask:(void (^)(NSDictionary *list))done;
+ (void)askURL:(void (^)(NSDictionary *list))done;
+ (void)showUpload:(void (^)(NSDictionary *list))done;
+ (void)pickLocal:(void (^)(NSDictionary *list))done;
/// Thêm từ một tệp trên máy (chọn tệp, «Mở bằng»); NO = không đọc được / không phải M3U (đã báo)
+ (BOOL)importFile:(NSString *)path done:(void (^)(NSDictionary *list))done;
/// Tệp .m3u / .m3u8 tìm được trên máy: [{path, name, size, date}], mới nhất trước
+ (NSArray *)localFiles;
/// Trang nhận tệp đang mở (nil = chưa mở) — lệnh gỡ lỗi
+ (NSString *)uploadAddress;
@end
