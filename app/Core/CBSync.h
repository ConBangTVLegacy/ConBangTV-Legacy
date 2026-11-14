#import <Foundation/Foundation.h>

/// Dữ liệu vừa gộp từ máy khác (lịch sử, theo dõi, người xem, trang phim) — màn đang mở tự vẽ lại
extern NSString *const CBSyncDataChanged;
/// Trạng thái đồng bộ đổi (đang đồng bộ, máy vừa ghép, mã ghép, máy tìm thấy) — màn Đồng bộ vẽ lại
extern NSString *const CBSyncStateChanged;

/// Đồng bộ trong nhà với tivi / iPad / Windows / Mac (lõi Rust: sync_service.rs — cùng giao thức, cùng khoá dữ liệu, ghép bằng
/// mã 4 số, cổng 8791). App lo phần nhịp: lúc mở / quay lại app, thoát phim, đổi dữ liệu, 3 phút một lần khi không xem phim.
@interface CBSync : NSObject
/// Gọi một lần sau khi lõi mở: nối sự kiện của lõi, đồng bộ nếu đã ghép
+ (void)start;
/// Hẹn đồng bộ sau s giây (gọi liền nhiều lần chỉ chạy lần cuối; chưa ghép / tắt tự đồng bộ thì bỏ qua)
+ (void)soon:(double)seconds;
/// Đang xem phim (không tự đồng bộ theo nhịp 3 phút)
+ (void)setPlaying:(BOOL)playing;
@end
