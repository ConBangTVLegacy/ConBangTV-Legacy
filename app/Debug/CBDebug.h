#import <Foundation/Foundation.h>

/// Chỉ bản thử (DEBUG): điều khiển app từ SSH — ghi lệnh vào Documents/ConBangTV-cmd.txt (mỗi dòng một lệnh), app đọc mỗi
/// 0,7 giây rồi xoá tệp, kết quả ghi vào nhật ký. Lệnh:
///   shot <tên>             chụp màn hình → Documents/shots/<tên>.png
///   film <url>             mở trang phim
///   play <url phim> [url tập]  phát (không có tập: tập trong lịch sử / tập đầu)
///   search <chữ>           tìm phim
///   home | back | settings | profiles | reload
///   seek <giây> | fwd <giây> | toggle | next | prev | server <số> | close   (trình phát)
///   status                 ghi trạng thái trình phát / bộ nhớ vào nhật ký
@interface CBDebug : NSObject
+ (void)start;
@end
