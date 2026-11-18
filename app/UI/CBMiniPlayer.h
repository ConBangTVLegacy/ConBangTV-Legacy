#import <UIKit/UIKit.h>

/// Trình phát nhận thu nhỏ (CBPlayerViewController — phim, CBLivePlayerViewController — kênh truyền hình)
@protocol CBMiniPlayable <NSObject>
/// View hình (lớp AVPlayerLayer) — chuyển sang khung nhỏ, lúc mở lại thì trả về (miniRestoreVideo:)
- (UIView *)miniVideoView;
- (void)miniRestoreVideo:(UIView *)video;
- (BOOL)miniPlaying;
- (void)miniTogglePlay;
/// Đóng hẳn (lưu chỗ xem, dừng phát)
- (void)close;
@optional
/// Thanh thu nhỏ của iPhone: dòng trên (tên phim / kênh), dòng dưới (tập / chương trình)
- (NSString *)miniTitle;
- (NSString *)miniSubtitle;
/// Phần đã xem 0…1 — vạch tiến độ trên thanh thu nhỏ; âm = không vẽ (kênh trực tiếp)
- (double)miniProgress;
@end

/// Trình phát thu nhỏ trong app («hình trong hình» kiểu YouTube): hình phim / kênh vẫn phát trong lúc lướt app.
///  • iPad: khung nhỏ nổi ở góc màn hình — chạm = mở lại, ✕ = đóng hẳn, nút phát / tạm dừng, kéo để dời sang góc khác.
///  • iPhone (màn nhỏ, app đứng dọc): thanh ở đáy màn hình (hình 16:9 bên trái, tên + tập, phát / tạm dừng, ✕), cả app co lên trên
///    thanh nên không che nội dung (CBRootViewController) — chạm = mở lại, vuốt xuống / ✕ = đóng hẳn. Kéo hình lên = tách thành
///    khung nổi 192×108 (bám góc gần chỗ thả, né bàn phím); kéo khung xuống quá mép dưới = về thanh. Nhớ kiểu lần trước.
/// Mở lại là đúng trình phát đó (tập, phụ đề, chỗ xem). Chỉ trong app — iOS 5–8 không có hình trong hình của hệ thống
/// (AVPictureInPictureController từ iOS 9, chỉ iPad A7+). Bật trên máy RAM ≥ 400 MB; tắt trên máy 256 MB (iPad 1, iPhone 3GS,
/// iPod touch 4 — vừa phát vừa lướt dễ bị iOS tắt app).
@interface CBMiniPlayer : NSObject
/// Máy này có thu nhỏ được không (RAM ≥ 400 MB)
+ (BOOL)available;
/// Đang có trình phát thu nhỏ (đang xem — đừng hỏi cập nhật / báo xem được…)
+ (BOOL)active;
/// Biểu tượng nút trên thanh trình phát của iPhone (chỗ hẹp, thay chữ): @"mini" (thu nhỏ), @"float" (hình nổi)
+ (UIImage *)barIcon:(NSString *)kind;
/// Thu nhỏ trình phát đang mở toàn màn hình
+ (void)minimize:(UIViewController<CBMiniPlayable> *)player;
+ (BOOL)isMini:(UIViewController *)player;
/// Mở lại toàn màn hình trình phát đang thu nhỏ
+ (void)expand;
/// Đóng hẳn trình phát đang thu nhỏ (nút ✕)
+ (void)closeCurrent;
/// Trình phát `player` vừa mở: đóng trình phát khác đang thu nhỏ (mỗi lúc chỉ phát một)
+ (void)closeOthers:(UIViewController *)player;
/// Trình phát tự đóng (hết giờ xem, …) lúc đang thu nhỏ: bỏ khung
+ (void)playerClosed:(UIViewController *)player;
/// Màn dùng để trình bày tiếp (hộp hết giờ xem, mở lại trình phát): presentingViewController, hoặc màn trên cùng khi đang thu nhỏ
+ (UIViewController *)hostFor:(UIViewController *)player;
@end
