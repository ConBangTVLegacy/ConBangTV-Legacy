#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CBLimitBlock) { CBLimitNone = 0, CBLimitDaily, CBLimitBedtime };

/// Giới hạn giờ xem theo người xem (Cài đặt → Giới hạn giờ xem): số phút xem mỗi ngày và giờ đi ngủ (từ giờ đó tới 6 giờ sáng
/// không xem được). Đếm thời gian phim thật sự chạy của người đang xem; hết giờ thì trình phát dừng phim, xem thêm phải có mã
/// PIN phụ huynh. Cùng cách tính, cùng tên khoá với WatchLimit của bản Windows / TV / iPad (limit_min, bedtime, watch_day,
/// watch_sec, watch_extra, unblock_until — riêng từng người xem).
@interface CBWatchLimit : NSObject
/// Lựa chọn số phút mỗi ngày (0 = không giới hạn), giờ đi ngủ (phút trong ngày, -1 = không), cho xem thêm (phút)
+ (NSArray *)dailyChoices;
+ (NSArray *)bedtimeChoices;
+ (NSArray *)grantChoices;

+ (NSInteger)dailyLimitFor:(NSString *)pid;
+ (void)setDailyLimit:(NSInteger)minutes for:(NSString *)pid;
+ (NSInteger)bedtimeFor:(NSString *)pid;
+ (void)setBedtime:(NSInteger)minute for:(NSString *)pid;
/// Có người xem nào đang bị giới hạn (khi đó thêm / xoá người xem cũng cần mã PIN phụ huynh)
+ (BOOL)anyLimits;

/// Giây còn được xem hôm nay của người đang xem; NSNotFound = không giới hạn theo ngày
+ (NSInteger)remaining;
/// Người đang xem có bị chặn không (giờ đi ngủ trước, rồi hết phút trong ngày)
+ (CBLimitBlock)blocked;
/// Gọi đều khi đọc trạng thái trình phát: phim đang chạy thì cộng thời gian từ lần trước (bỏ khoảng hở > 3 giây)
+ (void)tick:(BOOL)playing;
/// Ghi phần đã đếm (rời trình phát, đổi người xem)
+ (void)flush;
/// Bỏ phần đếm chưa ghi (đổi người xem — đã flush trước)
+ (void)reset;
/// Cho xem thêm (đã nhập mã phụ huynh): giờ đi ngủ → mở khoá thêm từng ấy phút; hết phút trong ngày → cộng thêm
+ (void)grant:(NSInteger)minutes;
/// Không giới hạn tới 6 giờ sáng
+ (void)grantUntilMorning;

/// «30 phút», «1 giờ», «1 giờ 30 phút», «Không giới hạn»
+ (NSString *)dailyLabel:(NSInteger)minutes;
/// «21:00» hoặc «Không»
+ (NSString *)bedtimeLabel:(NSInteger)minute;
/// Giây còn lại → «25 phút» (làm tròn lên, tối thiểu 1 phút)
+ (NSString *)minutesText:(NSInteger)seconds;
/// «1 giờ/ngày, ngủ lúc 21:00» / «không giới hạn»
+ (NSString *)summaryFor:(NSString *)pid;
/// Câu báo khi bị chặn, vd «Bé đã xem hết 1 giờ của hôm nay.»
+ (NSString *)reason:(CBLimitBlock)block;
@end
