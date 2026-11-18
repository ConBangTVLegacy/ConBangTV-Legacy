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
@end

/// Trình phát thu nhỏ trong app («hình trong hình» kiểu YouTube): hình phim / kênh thu vào khung nhỏ ở góc màn hình, vẫn phát trong
/// lúc lướt app. Chạm khung = mở lại toàn màn hình (đúng trình phát đó: tập, phụ đề, chỗ xem), ✕ = đóng hẳn, nút phát / tạm dừng;
/// kéo để dời sang góc khác. Chỉ trong app — iOS 5–8 không có hình trong hình của hệ thống (AVPictureInPictureController từ iOS 9,
/// chỉ iPad A7+). Bật trên iPad RAM ≥ 400 MB; tắt trên iPad 1 (256 MB — vừa phát vừa lướt dễ bị iOS tắt app) và iPhone (chưa thử).
@interface CBMiniPlayer : NSObject
/// Máy này có thu nhỏ được không (RAM ≥ 400 MB)
+ (BOOL)available;
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
