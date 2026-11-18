#import <UIKit/UIKit.h>

/// Trình phát trao được cho «Hình nổi» (CBPlayerViewController — phim, CBLivePlayerViewController — kênh)
@protocol CBFloatPlayable <NSObject>
/// Địa chỉ đang phát (cổng phát nội bộ của app — nil nếu chưa phát)
- (NSString *)floatURL;
/// Giây đang xem (phim; kênh trực tiếp thì 0)
- (double)floatTime;
- (NSString *)floatTitle;
- (BOOL)floatLive;
- (BOOL)floatFill;
- (void)floatPause;
/// Khung nổi đóng lúc app còn nằm nền: chỉ ghi chỗ xem — không đụng AVPlayer (tua lúc app nằm nền thì AVPlayer báo lỗi «No
/// response for media file», trình phát thử lại server rồi phát luôn trong nền)
- (void)floatSaveAt:(double)time;
/// Khung nổi trả lại, app đã ra trước: play = phát tiếp từ `time`; NO = anh đã đóng khung (tua tới đó, để tạm dừng)
- (void)floatReturnedAt:(double)time play:(BOOL)play;
@end

/// «Hình nổi» — hình trong hình nổi trên màn hình chính / app khác, nhờ tinh chỉnh CBFloat trong SpringBoard (gói vn.conbangtv.float,
/// iOS 8 đã jailbreak; tweak/CBFloat). App: ghi ConBangTV-float.json (địa chỉ trên cổng phát nội bộ, chỗ đang xem), phát âm thanh câm
/// (trộn được) để iOS không treo app — cổng phát nội bộ (bỏ quảng cáo, đổi định dạng luồng) phải còn chạy, gửi thông báo Darwin
/// vn.conbangtv.float.show rồi tự về màn hình chính. SpringBoard trả lại qua vn.conbangtv.float.back + ConBangTV-float-back.json.
@interface CBFloatBridge : NSObject
/// Đã cài tinh chỉnh (iOS 7+, tệp CBFloat.dylib)
+ (BOOL)available;
/// Trao trình phát cho khung nổi
+ (void)handoff:(UIViewController<CBFloatPlayable> *)player;
+ (BOOL)isFloating:(UIViewController *)player;
@end
