#import <Foundation/Foundation.h>

/// Truyền hình (IPTV): danh sách kênh M3U / M3U8 người xem tự thêm (app không kèm sẵn kênh), lịch phát sóng XMLTV.
///  • Danh sách: tải qua lõi (`http.get` — TLS / DNS / proxy như phần còn lại của app), đọc #EXTINF (tvg-id, tvg-name, tvg-logo,
///    group-title, tvg-chno), #EXTGRP, #EXTVLCOPT http-referrer / http-user-agent, «url|Referer=…»; kênh trùng tên trong cùng
///    nhóm gộp thành nhiều nguồn. Lưu đệm Library/Caches/iptv/<mã>.json; tải lại khi cũ quá 6 giờ (danh sách có trận: 30 phút;
///    trận sắp / đang đá mà chưa có link thật: 5 phút) — lúc vào màn Truyền hình và tự làm mới khi màn đang mở.
///  • Lịch: địa chỉ EPG ghi trong đầu danh sách (url-tvg / x-tvg-url) hoặc người xem tự đặt; tải bằng lõi (`http.download`), giải
///    nén .gz theo từng khúc ra đĩa, đọc XML dần (NSXMLParser trên luồng — iPad 1 chỉ 256 MB), chỉ giữ chương trình của các
///    kênh trong danh sách, từ 24 giờ trước tới 48 giờ sau. Khớp kênh theo tvg-id, không có thì theo tên.
///  • Lưu ở kho prefs của lõi: iptv_lists, iptv_active, iptv_epg_url (cả nhà); iptv_favs, iptv_recent (từng người xem — khoá
///    «key#pid»); iptv_bad (kênh máy không phát được: H.265, khổ quá lớn…).
/// Kênh: {k (khoá: tên chuẩn hoá), n (tên), g (nhóm), logo, id (tvg-id), num, urls: [địa chỉ], ref (Referer), ua,
///        hdr ({địa chỉ: {ref, ua}} — nguồn gộp vào có tiêu đề khác), kick (giờ bóng lăn), dur (phút), radio (đài phát thanh)}
extern NSString *const CBIPTVChangedNotification;   // danh sách / lịch vừa tải xong

typedef NS_ENUM(NSInteger, CBMatchState) {
    CBMatchNone = 0,   // kênh thường (tên không ghi giờ trận)
    CBMatchLater,      // còn hơn 30 phút mới bóng lăn
    CBMatchSoon,       // trong 30 phút trước giờ bóng lăn (kênh thường đã lên sóng)
    CBMatchLive,       // đang đá
    CBMatchOver,       // đã xong
};
@interface CBIPTV : NSObject

// ---- Danh sách ----
/// [{id, name, url | file + src (thêm từ tệp), count, updated (ms), epg, err}]
+ (NSArray *)lists;
+ (NSDictionary *)activeList;
+ (void)setActive:(NSString *)listId;
/// Thêm danh sách (tên lấy từ địa chỉ) và chọn nó; trả bản ghi mới
+ (NSDictionary *)addList:(NSString *)url name:(NSString *)name;
/// Thêm danh sách từ nội dung tệp M3U (máy tính gửi qua Wi-Fi, tệp trên máy, «Mở bằng»): chép vào Documents/ConBangTV-iptv,
/// bản ghi {id, name, file, src (tên tệp gốc)} — không tải mạng, không tự làm mới. Chọn nó; nil + error nếu không phải M3U
+ (NSDictionary *)addListWithData:(NSData *)data fileName:(NSString *)fileName name:(NSString *)name error:(NSString **)error;
/// Đường dẫn tệp đã chép của danh sách thêm từ tệp (nil = danh sách theo địa chỉ)
+ (NSString *)localFileOf:(NSDictionary *)list;
+ (void)renameList:(NSString *)listId name:(NSString *)name;
+ (void)removeList:(NSString *)listId;
/// Kênh của danh sách đang chọn (đã đọc đệm); nil = chưa tải
+ (NSArray *)channels;
/// Đang tải danh sách / lịch
+ (BOOL)loading;
+ (NSString *)status;
/// Tải danh sách đang chọn (force: bỏ qua đệm còn mới), rồi lịch nếu cũ. done trên luồng chính
+ (void)refresh:(BOOL)force done:(void (^)(NSString *err))done;
+ (void)refreshGuide:(BOOL)force done:(void (^)(NSString *err))done;
/// Màn Truyền hình đang mở (gọi mỗi 30 giây / lúc app trở lại): tải lại danh sách nếu đã quá hạn; vừa tải hỏng thì 3 phút sau
/// mới thử lại
+ (void)autoRefresh;

// ---- Nhóm / lọc ----
/// Các nhóm theo thứ tự xuất hiện: [{name, count}]
+ (NSArray *)groupsOf:(NSArray *)channels;
/// Hồ sơ trẻ em: chỉ giữ kênh nhóm thiếu nhi / hoạt hình
+ (NSArray *)kidsFilter:(NSArray *)channels;

// ---- Yêu thích / vừa xem / kênh lỗi (khoá kênh = k) ----
+ (BOOL)isFavorite:(NSDictionary *)channel;
+ (void)setFavorite:(NSDictionary *)channel on:(BOOL)on;
+ (NSArray *)favoriteKeys;
/// Kênh vừa xem (mới nhất trước, tối đa 12): bản tóm tắt {k, n, logo, g} — kênh thật lấy bằng channelForKey:
+ (NSArray *)recent;
+ (void)addRecent:(NSDictionary *)channel;
+ (NSDictionary *)channelForKey:(NSString *)key;
/// Lý do máy không phát được nguồn này (nil = chưa thấy lỗi)
+ (NSString *)badReason:(NSString *)url;
+ (void)markBad:(NSString *)url reason:(NSString *)reason;
+ (void)clearBad;
/// Bỏ dấu «không phát được» của mọi nguồn của kênh (người xem bấm «Thử lại kênh này»)
+ (void)clearBadFor:(NSDictionary *)channel;
/// Mọi nguồn của kênh đều đã ghi là không phát được → lý do của nguồn đầu
+ (NSString *)channelBadReason:(NSDictionary *)channel;

// ---- Cài đặt ----
+ (BOOL)hideBad;
+ (void)setHideBad:(BOOL)on;
+ (BOOL)autoSource;
+ (void)setAutoSource:(BOOL)on;
/// Địa chỉ EPG người xem tự đặt (nil = lấy từ danh sách)
+ (NSString *)epgOverride;
+ (void)setEpgOverride:(NSString *)url;
/// Địa chỉ EPG sẽ dùng cho danh sách đang chọn
+ (NSString *)epgUrl;
/// Lần tải lịch gần nhất (ms; 0 = chưa) và số kênh có lịch
+ (long long)guideUpdated;
+ (NSUInteger)guideChannelCount;

// ---- Lịch phát sóng ----
/// Chương trình của kênh, theo giờ bắt đầu: [{s, e (giây từ 1970), t}]
+ (NSArray *)programmesFor:(NSDictionary *)channel;
/// Chương trình đang phát / kế tiếp lúc now (giây)
+ (NSDictionary *)nowFor:(NSDictionary *)channel at:(NSTimeInterval)now;
+ (NSDictionary *)nextFor:(NSDictionary *)channel at:(NSTimeInterval)now;

// ---- Phát ----
/// Danh sách chính không có bản nào máy giải mã được: H.265 (HEVC) / AV1 / khổ quá lớn → lý do; nil = thử phát
+ (NSString *)undecodableReason:(NSString *)m3u8;
/// Tên chuẩn hoá để so (bỏ dấu, chữ thường, bỏ «HD», «FHD»…)
+ (NSString *)norm:(NSString *)name;
/// «19:00»
+ (NSString *)clock:(NSTimeInterval)t;
/// Referer / User-Agent gửi lên máy chủ cho nguồn `url` của kênh: {referer, ua} (tham số media.open)
+ (NSDictionary *)headersFor:(NSDictionary *)channel url:(NSString *)url;
/// Đài radio (danh sách ghi radio="true", nhóm «Radio» / «Phát thanh», link .mp3 / .aac / .pls)
+ (BOOL)isRadio:(NSDictionary *)channel;
/// Link giả «không có tín hiệu» mà danh sách thể thao để cho trận chưa có link thật (…/no-signal/…)
+ (BOOL)isPlaceholderURL:(NSString *)url;
/// Danh sách phát là đoạn phim ngắn có hồi kết (hình chờ «không có tín hiệu» thay cho luồng trực tiếp)
+ (BOOL)isPlaceholderPlaylist:(NSString *)m3u8;
/// Tải lại danh sách đang chọn nếu cũ hơn `seconds` (đang tải thì chờ xong); done trên luồng chính
+ (void)refreshIfOlderThan:(double)seconds done:(void (^)(NSString *err))done;

// ---- Trận đấu (danh sách thể thao ghi giờ trận trong tên: «20:00 16/11 ⚽ A vs B (BLV …)») ----
/// Kênh trận có kick (giờ bóng lăn, giây từ 1970) và dur (phút)
+ (CBMatchState)matchState:(NSDictionary *)channel at:(NSTimeInterval)now;
/// «Sắp đá 20:00 · còn 25 phút», «● Đang đá · bóng lăn 20:00», «Đã xong · đá lúc 20:00»; nil = kênh thường
+ (NSString *)matchLine:(NSDictionary *)channel at:(NSTimeInterval)now;
/// «20:00», «02:45 mai», «20:00 18/11»
+ (NSString *)kickText:(NSTimeInterval)kick now:(NSTimeInterval)now;
/// Đang đá trước, rồi sắp đá (sớm trước), kênh thường, đã xong (mới xong trước); ngang nhau giữ thứ tự gốc
+ (NSArray *)sortByMatch:(NSArray *)channels at:(NSTimeInterval)now;
/// «Nhắc lúc bóng lăn» (thông báo của máy đúng giờ trận)
+ (BOOL)hasKickReminder:(NSDictionary *)channel;
/// YES = vừa đặt nhắc, NO = vừa bỏ (hoặc trận đã bắt đầu)
+ (BOOL)toggleKickReminder:(NSDictionary *)channel;
@end
