#import <Foundation/Foundation.h>

/// Cài đặt và dữ liệu người xem — kho prefs.json của lõi (prefs.get / prefs.set), cùng khoá và cách tính với bản Windows
/// (windows/ConBangTV/Core/Prefs.cs) / TV / iPad để đồng bộ trong nhà dùng chung được. Dữ liệu là NSDictionary JSON camelCase:
///   người xem {id, name, color, pin}; lịch sử {filmUrl, title, poster, epTitle, epUrl, time};
///   vị trí {ep, sec, film, t}; theo dõi {filmUrl, title, poster, count, latest, seen, t}.
@interface CBPrefs : NSObject

+ (id)get:(NSString *)key;
+ (void)set:(NSString *)key value:(id)value;
+ (BOOL)has:(NSString *)key;
+ (void)remove:(NSString *)key;

// ---- Người xem ----
+ (NSArray *)profiles;
+ (NSString *)profileId;
+ (NSDictionary *)currentProfile;
+ (void)switchProfile:(NSString *)pid;
/// Bỏ bộ đệm (đồng bộ vừa gộp dữ liệu của máy khác vào lõi)
+ (void)invalidateCaches;
+ (NSDictionary *)addProfile:(NSString *)name;
+ (void)renameProfile:(NSString *)pid name:(NSString *)name;
/// pin nil = bỏ khoá
+ (void)setProfilePin:(NSString *)pid pin:(NSString *)pin;
+ (BOOL)checkPin:(NSString *)pin profile:(NSDictionary *)profile;
/// Mã PIN phụ huynh (cả nhà): đặt / đổi giới hạn giờ xem, cho xem thêm khi hết giờ
+ (BOOL)hasParentPin;
+ (void)setParentPin:(NSString *)pin;  // nil = xoá
+ (BOOL)checkParentPin:(NSString *)pin;
/// Khoá riêng của người xem pid («key#pid»; người đầu tiên pid "" = «key») / của người đang xem
+ (NSString *)pk:(NSString *)pid key:(NSString *)key;
+ (NSString *)k:(NSString *)key;
/// Xoá người xem cùng dữ liệu riêng (còn một người thì không xoá)
+ (BOOL)deleteProfile:(NSString *)pid;
+ (BOOL)askProfile;
+ (void)setAskProfile:(BOOL)on;
+ (NSString *)initialOf:(NSDictionary *)profile;

// ---- Lịch sử / chỗ đang xem / theo dõi ----
+ (NSArray *)history;
+ (NSDictionary *)historyFor:(NSString *)filmUrl;
+ (void)addHistory:(NSDictionary *)detail episode:(NSDictionary *)ep;
+ (void)removeHistory:(NSString *)filmUrl;
+ (void)clearHistory;
+ (int)positionOf:(NSString *)epUrl;
/// Tập đã xem hết (lưu vị trí 0 khi xem tới ~90 giây cuối)
+ (BOOL)finished:(NSString *)epUrl;
+ (NSSet *)watchedEpisodes;
+ (void)savePosition:(NSString *)epUrl seconds:(int)sec film:(NSString *)filmUrl;
+ (NSArray *)follows;
+ (NSDictionary *)followOf:(NSString *)filmUrl;
+ (void)follow:(NSDictionary *)detail;
+ (void)unfollow:(NSString *)filmUrl;
+ (void)updateFollow:(NSString *)filmUrl count:(NSInteger)count latest:(NSString *)latest seen:(BOOL)seen;

// ---- Cài đặt ----
+ (NSString *)baseUrl;
+ (void)setBaseUrl:(NSString *)url;
+ (NSArray *)sites;
+ (void)setSites:(NSArray *)sites;
/// Vượt chặn nhà mạng: 0 tắt, 1 mức 1 (chia nhỏ gói bắt tay), 2 mức 2 — khoá unblock + unblock_level như lõi / bản Windows
+ (NSInteger)unblockLevel;
+ (void)setUnblockLevel:(NSInteger)level;
/// Server dự phòng KKPhim cho các trang tự có trình phát (khoá kk_backup, chưa có = bật)
+ (BOOL)kkBackup;
+ (void)setKkBackup:(BOOL)on;
/// Tự kiểm tra bản mới khi mở app (khoá auto_update, chưa có = bật)
+ (BOOL)autoUpdate;
+ (void)setAutoUpdate:(BOOL)on;
/// Xem riêng (từng người xem, khoá private_mode): không ghi lịch sử / «đã thấy tập»; chỗ đang xem chỉ giữ trong lần mở app này
+ (BOOL)privateMode;
+ (void)setPrivateMode:(BOOL)on;
/// Server đã chọn / đã phát được theo từng trang (server_type@ / legacy_server@): số trang đang nhớ, và xoá hết
+ (NSUInteger)chosenServerCount;
+ (void)resetChosenServers;
+ (BOOL)homeMix;
/// Hồ sơ trẻ em (khoá kids — đặt từ bản Windows / Android, đồng bộ hồ sơ)
+ (BOOL)kids;
+ (void)setKids:(BOOL)on;
+ (void)setHomeMix:(BOOL)on;
+ (BOOL)autoNext;
+ (void)setAutoNext:(BOOL)on;
+ (NSInteger)seekStep;
+ (void)setSeekStep:(NSInteger)sec;
+ (BOOL)videoFill;
+ (void)setVideoFill:(BOOL)on;
+ (BOOL)secureDns;
+ (void)setSecureDns:(BOOL)on;
+ (BOOL)unblock;
+ (void)setUnblock:(BOOL)on;
+ (NSString *)serverTypeForHost:(NSString *)host;
+ (void)setServerForHost:(NSString *)host type:(NSString *)type label:(NSString *)label;
+ (NSInteger)disclaimerVersion;
+ (void)setDisclaimerVersion:(NSInteger)v;
@end

// ---- Phim (FilmDetail của lõi: {url, title, otherTitle, poster, description, info, groups: [{name, episodes: [{title, url}]}]}) ----
NSInteger CBDetailEpisodeCount(NSDictionary *detail);
/// Tập mới nhất của bản nhiều tập nhất
NSDictionary *CBDetailLatestEpisode(NSDictionary *detail);
/// Chỉ số bản (nhóm tập) chứa tập epUrl; -1 = không có
NSInteger CBDetailGroupIndexOf(NSDictionary *detail, NSString *epUrl);
/// Tên miền (bỏ «www.»)
NSString *CBHostOf(NSString *url);
