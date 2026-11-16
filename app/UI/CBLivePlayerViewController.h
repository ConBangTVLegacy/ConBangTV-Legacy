#import <UIKit/UIKit.h>

/// Trình phát truyền hình trực tiếp (IPTV): kênh qua cổng phát nội bộ của lõi (`media.open` — HLS trực tiếp tải lại danh sách
/// phát mỗi lần AVPlayer hỏi; HTTPS / DNS / proxy như phim), «Kênh trước / Kênh sau», bảng «☰ Kênh» bên phải, «Nguồn i/n»
/// (kênh có nhiều địa chỉ; nguồn lỗi tự sang nguồn sau), tạm dừng → «Về trực tiếp», chương trình đang phát / kế tiếp từ lịch
/// phát sóng, giới hạn giờ xem như phim. Trước khi phát đọc danh sách chính: bản nào máy cũng không giải mã được (H.265, khổ quá
/// lớn) thì ghi kênh đó «không phát được» và báo ngay.
@interface CBLivePlayerViewController : UIViewController
- (instancetype)initWithChannels:(NSArray *)channels index:(NSInteger)index;
- (void)nextChannel;
- (void)previousChannel;
- (void)playChannelAt:(NSInteger)index;
- (void)togglePlay;
- (void)goLive;
- (void)toggleChannels;
- (void)nextSource;
- (void)close;
/// Trạng thái để ghi log (lệnh gỡ lỗi «tvstatus»)
- (NSString *)statusLine;
@end
