#import <UIKit/UIKit.h>

/// Trình phát: lõi tìm server (kk.source) → link (site.videoOf) → cổng phát nội bộ (media.open: bỏ quảng cáo…) → AVPlayer.
/// Server chỉ có trình phát nhúng (iOS 6 không chạy được) thì tự thử server sau. Nhớ chỗ đang xem, tự chuyển tập.
/// detail nil: tự tải trang phim. resume: mở từ «Xem tiếp» — tập đã xem hết thì sang tập sau.
@interface CBPlayerViewController : UIViewController
- (instancetype)initWithFilm:(NSString *)filmUrl detail:(NSDictionary *)detail episode:(NSString *)epUrl resume:(BOOL)resume;
// Điều khiển (nút, màn hình khoá, lệnh gỡ lỗi)
- (void)togglePlay;
- (void)seekBy:(double)delta;
- (void)seekTo:(double)seconds;
- (void)nextEpisode;
- (void)previousEpisode;
- (void)selectServer:(NSInteger)index;
- (void)close;
/// Trạng thái để ghi log / gỡ lỗi
- (NSString *)statusLine;
/// Bảng chọn tập (gỡ lỗi: lệnh «eps» / «ep <số>»)
- (void)toggleEpisodes;
- (void)selectEpisode:(NSInteger)i;
/// Phụ đề rời WebVTT / SRT từ địa chỉ http (gỡ lỗi: lệnh «sub <url>»)
- (void)loadSubtitles:(NSString *)url;
/// Gỡ lỗi: giả server đang phát bị rớt (lệnh «fail») / giả hết tập (lệnh «end»)
- (void)debugStreamFailed;
/// Menu «⋯»: tốc độ, đoạn mở đầu, hẹn giờ tắt, tải lại, mở trang tập (gỡ lỗi: lệnh «menu» / «speed» / «sleep»)
- (void)showMenu;
/// Gỡ lỗi (lệnh «sheet <số>»): bấm mục của bảng chọn đang hiện (số âm = Huỷ); NO nếu không có bảng
- (BOOL)pressMenuItem:(NSInteger)index;
- (void)setSpeed:(float)speed;
- (void)setSleepAfter:(NSTimeInterval)seconds endOfEpisode:(BOOL)endOfEpisode;
- (void)debugPlayedToEnd;
@end

/// Danh sách phát chính (HLS) không có bản nào máy này giải mã được → mô tả bản lớn nhất («2542×1080, H.264 mức 5.0»); nil
/// nếu có bản phát được / không ghi khổ (danh sách con)
NSString *CBPlaylistUndecodable(NSString *m3u8);
