#import <Foundation/Foundation.h>

/// «Báo khi xem được»: tập chưa có server nào phát được trên iOS 6 (vd tập mới ra chỉ có trình phát có khoá streamfree / NguonC —
/// app không vượt lớp khoá) thì người xem bấm nút ở trình phát để app nhớ tập đó. Mở app / quay lại app / 30 phút một lần khi
/// đang mở (không lúc đang xem phim), app hỏi lại lõi như trình phát hỏi (kk.source → site.videoOf từng server — thường bản KKPhim
/// dự phòng có sau vài giờ); có server phát thẳng được thì hiện hộp «Đã xem được — Xem ngay». Phim không chia mùa thì xét cả
/// cùng tập ở bản khác (Vietsub / Thuyết Minh). Lưu riêng từng người xem (khoá `wait_playable`), tối đa 20 tập, bỏ sau 14 ngày.
@interface CBWaitPlayable : NSObject
/// Gọi một lần lúc mở app
+ (void)start;
+ (BOOL)has:(NSString *)epUrl;
/// detail: FilmDetail của lõi; group: nhóm (bản / mùa) chứa tập
+ (void)add:(NSDictionary *)detail episode:(NSDictionary *)ep group:(NSDictionary *)group;
+ (void)remove:(NSString *)epUrl;
+ (NSArray *)list;
/// Kiểm ngay mọi tập (bỏ qua giới hạn 30 phút) — gỡ lỗi / thử
+ (void)checkNow;
/// Trình phát vừa đóng: hiện các hộp «Đã xem được» đang chờ (có kết quả lúc đang xem phim)
+ (void)playerClosed;
@end
