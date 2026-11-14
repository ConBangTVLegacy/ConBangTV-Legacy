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
@end
