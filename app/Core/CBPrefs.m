#import "CBPrefs.h"
#import "CBCore.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBSync.h"
#import "CBWatchLimit.h"
#import <CommonCrypto/CommonDigest.h>

// Trang mẫu (như Prefs.PresetSites của bản Windows)
static NSString *const kDefaultBase = @"https://yanhh3d.ee";
static NSString *const kKkSite = @"https://www.kkphim.com";
static NSString *const kFirstProfileName = @"Cả nhà";
static const NSInteger kMaxHistory = 60;
static const NSInteger kMaxPositions = 400;

static NSArray *PresetSites(void) {
    return @[kDefaultBase, @"https://hoathinh3d.pw", @"https://hoathinh3d.ee", @"https://hhkungfu.ee", @"https://phimmois.fun",
             @"https://mephim.ddns.net", kKkSite, @"https://phim.nguonc.com", @"https://vsmov.com", @"https://sc.k-20.xyz"];
}

/// Khoá riêng từng người xem (còn lại dùng chung) — giống ProfileKeys của bản Windows
static NSSet *ProfileKeys(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[@"history", @"positions_v2", @"follows", @"last_follow_check", @"private_mode", @"hist_del",
                                  @"follow_del", @"base_url", @"seek_step", @"auto_next", @"video_fill", @"limit_min", @"bedtime",
                                  @"watch_day", @"watch_sec", @"watch_extra", @"unblock_until", @"home_mix", @"home_topics",
                                  @"seen_eps", @"kids", @"watch_langs", @"home_rows", @"home_custom", @"home_src_off"]];
    });
    return s;
}
static NSArray *ProfilePrefixes(void) { return @[@"server_type@", @"server_label@"]; }
/// Người thêm sau bắt đầu với các cài đặt này của người đang dùng
static NSSet *CopiedKeys(void) { return [NSSet setWithArray:@[@"base_url", @"seek_step", @"auto_next", @"video_fill", @"home_mix"]]; }

static NSString *gPidCache;
static NSMutableArray *gHistoryCache;
static NSMutableArray *gPositionsCache;

static NSString *Sha256Hex(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *out = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", h[i]];
    return out;
}

@implementation CBPrefs

#pragma mark - Đọc / ghi khoá

+ (id)get:(NSString *)key {
    return [CBCore sync:@"prefs.get" args:@{@"key": key}];
}

+ (void)set:(NSString *)key value:(id)value {
    [CBCore sync:@"prefs.set" args:@{@"key": key, @"value": value ?: [NSNull null]}];
}

+ (BOOL)has:(NSString *)key {
    return [[CBCore sync:@"prefs.has" args:@{@"key": key}] boolValue];
}

+ (void)remove:(NSString *)key {
    [self set:key value:nil];
}

+ (BOOL)boolKey:(NSString *)key def:(BOOL)def {
    id v = [self get:key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}

+ (NSDictionary *)stamps:(NSString *)key {
    id v = [self get:key];
    return CBIsDict(v) ? v : @{};
}

+ (void)setStamps:(NSString *)key map:(NSDictionary *)map {
    [CBCore sync:@"prefs.setStamps" args:@{@"key": key, @"map": map}];
}

#pragma mark - Người xem

+ (NSString *)pk:(NSString *)pid key:(NSString *)key {
    return pid.length == 0 ? key : [NSString stringWithFormat:@"%@#%@", key, pid];
}

+ (NSString *)k:(NSString *)key {
    return [self pk:[self profileId] key:key];
}

+ (NSArray *)profiles {
    NSMutableArray *list = [NSMutableArray array];
    for (id p in CBArr(@{@"x": [self get:@"profiles"] ?: [NSNull null]}, @"x")) {
        if (CBIsDict(p)) [list addObject:p];
    }
    if (!list.count) [list addObject:@{@"id": @"", @"name": kFirstProfileName, @"color": @0}];
    return list;
}

+ (NSString *)profileId {
    if (gPidCache) return gPidCache;
    id saved = [self get:@"profile"];
    NSArray *list = [self profiles];
    NSString *pid = CBStr(list[0], @"id") ?: @"";
    for (NSDictionary *p in list) {
        if (CBIsStr(saved) && [(CBStr(p, @"id") ?: @"") isEqualToString:saved]) pid = saved;
    }
    gPidCache = pid;
    return pid;
}

+ (NSDictionary *)currentProfile {
    NSString *pid = [self profileId];
    NSArray *list = [self profiles];
    for (NSDictionary *p in list) {
        if ([(CBStr(p, @"id") ?: @"") isEqualToString:pid]) return p;
    }
    return list[0];
}

+ (void)invalidateCaches {
    gPidCache = nil;
    gHistoryCache = nil;
    gPositionsCache = nil;
}

+ (void)switchProfile:(NSString *)pid {
    BOOL found = NO;
    for (NSDictionary *p in [self profiles]) found |= [(CBStr(p, @"id") ?: @"") isEqualToString:pid];
    if (!found) return;
    [CBWatchLimit flush];  // giờ đã xem tính cho người cũ
    [CBWatchLimit reset];
    gPidCache = pid;
    gHistoryCache = nil;
    gPositionsCache = nil;
    [self set:@"profile" value:pid];
}

+ (BOOL)isProfileKey:(NSString *)base {
    if ([ProfileKeys() containsObject:base]) return YES;
    for (NSString *p in ProfilePrefixes()) {
        if ([base hasPrefix:p]) return YES;
    }
    return NO;
}

/// Các khoá riêng đang có của một người xem: @[@[khoá thật, khoá gốc]]
+ (NSArray *)ownKeys:(NSString *)pid {
    NSMutableArray *out = [NSMutableArray array];
    id keys = [CBCore sync:@"prefs.keys" args:nil];
    for (id key in CBIsArr(keys) ? keys : @[]) {
        if (!CBIsStr(key)) continue;
        NSString *base = nil;
        if (pid.length == 0) {
            if ([key rangeOfString:@"#"].location == NSNotFound) base = key;
        } else {
            NSString *suffix = [@"#" stringByAppendingString:pid];
            if ([key hasSuffix:suffix]) base = [key substringToIndex:[key length] - suffix.length];
        }
        if (base && [self isProfileKey:base]) [out addObject:@[key, base]];
    }
    return out;
}

+ (void)saveProfiles:(NSArray *)list {
    [self set:@"profiles" value:list];
}

+ (NSDictionary *)addProfile:(NSString *)name {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSMutableArray *list = [[self profiles] mutableCopy];
    NSInteger n = 1;
    NSMutableSet *ids = [NSMutableSet set];
    NSMutableSet *colors = [NSMutableSet set];
    for (NSDictionary *p in list) {
        [ids addObject:CBStr(p, @"id") ?: @""];
        [colors addObject:@((NSInteger)CBNum(p, @"color", 0))];
    }
    while ([ids containsObject:[NSString stringWithFormat:@"p%ld", (long)n]]) n++;
    NSString *pid = [NSString stringWithFormat:@"p%ld", (long)n];
    NSInteger color = list.count % 8;
    for (NSInteger i = 0; i < 8; i++) {
        if (![colors containsObject:@(i)]) {
            color = i;
            break;
        }
    }
    for (NSArray *kb in [self ownKeys:[self profileId]]) {
        NSString *base = kb[1];
        BOOL prefixed = NO;
        for (NSString *p in ProfilePrefixes()) prefixed |= [base hasPrefix:p];
        if (![CopiedKeys() containsObject:base] && !prefixed) continue;
        id v = [self get:kb[0]];
        if (v) [self set:[NSString stringWithFormat:@"%@#%@", base, pid] value:v];
    }
    [self set:[NSString stringWithFormat:@"base_url#%@", pid] value:[self baseUrl]];
    NSString *clean = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *p = @{@"id": pid, @"name": clean.length ? clean : @"Người xem", @"color": @(color)};
    [list addObject:p];
    [self saveProfiles:list];
    return p;
}

+ (void)updateProfile:(NSString *)pid change:(void (^)(NSMutableDictionary *p))change {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *p in [self profiles]) {
        NSMutableDictionary *m = [p mutableCopy];
        if ([(CBStr(p, @"id") ?: @"") isEqualToString:pid]) change(m);
        [list addObject:m];
    }
    [self saveProfiles:list];
}

+ (void)renameProfile:(NSString *)pid name:(NSString *)name {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSString *clean = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!clean.length) return;
    [self updateProfile:pid change:^(NSMutableDictionary *p) { p[@"name"] = clean; }];
}

/// Không lưu mã PIN thật, chỉ lưu mã băm — cùng cách băm bản TV / iPad / Windows
+ (NSString *)pinHash:(NSString *)pid pin:(NSString *)pin {
    return Sha256Hex([NSString stringWithFormat:@"chimto-pin:%@:%@", pid, pin]);
}

+ (void)setProfilePin:(NSString *)pid pin:(NSString *)pin {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    [self updateProfile:pid change:^(NSMutableDictionary *p) {
        if (pin) p[@"pin"] = [self pinHash:pid pin:pin];
        else [p removeObjectForKey:@"pin"];
    }];
}

+ (BOOL)checkPin:(NSString *)pin profile:(NSDictionary *)profile {
    NSString *hash = CBStr(profile, @"pin");
    return !hash || [hash isEqualToString:[self pinHash:CBStr(profile, @"id") ?: @"" pin:pin]];
}

#pragma mark - Mã PIN phụ huynh (cả nhà) — khoá parent_pin như bản Windows / TV / iPad

+ (BOOL)hasParentPin {
    return CBIsStr([self get:@"parent_pin"]);
}

+ (void)setParentPin:(NSString *)pin {
    if (pin.length) [self set:@"parent_pin" value:[self pinHash:@"parent" pin:pin]];
    else [self remove:@"parent_pin"];
}

+ (BOOL)checkParentPin:(NSString *)pin {
    id h = [self get:@"parent_pin"];
    return CBIsStr(h) && [h isEqualToString:[self pinHash:@"parent" pin:pin ?: @""]];
}

+ (BOOL)deleteProfile:(NSString *)pid {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSArray *list = [self profiles];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSDictionary *p in list) {
        if (![(CBStr(p, @"id") ?: @"") isEqualToString:pid]) [rest addObject:p];
    }
    if (list.count <= 1 || rest.count == list.count) return NO;
    for (NSArray *kb in [self ownKeys:pid]) [self remove:kb[0]];
    [self saveProfiles:rest];
    if ([[self profileId] isEqualToString:pid]) [self switchProfile:CBStr(rest[0], @"id") ?: @""];
    return YES;
}

+ (BOOL)askProfile {
    return [self boolKey:@"ask_profile" def:YES];
}

+ (void)setAskProfile:(BOOL)on {
    [self set:@"ask_profile" value:@(on)];
}

+ (NSString *)initialOf:(NSDictionary *)profile {
    NSString *n = [CBStr(profile, @"name") ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!n.length) return @"?";
    NSRange r = [n rangeOfComposedCharacterSequenceAtIndex:0];
    return [[n substringWithRange:r] uppercaseString];
}

#pragma mark - Lịch sử

+ (NSMutableArray *)historyList {
    if (!gHistoryCache) {
        gHistoryCache = [NSMutableArray array];
        id v = [self get:[self k:@"history"]];
        for (id h in CBIsArr(v) ? v : @[]) {
            if (CBIsDict(h)) [gHistoryCache addObject:h];
        }
    }
    return gHistoryCache;
}

+ (NSArray *)history {
    return [[self historyList] copy];
}

+ (void)saveHistory:(NSArray *)list {
    gHistoryCache = [list mutableCopy];
    [self set:[self k:@"history"] value:list];
}

+ (NSDictionary *)historyFor:(NSString *)filmUrl {
    for (NSDictionary *h in [self historyList]) {
        if ([CBStr(h, @"filmUrl") isEqualToString:filmUrl]) return h;
    }
    return nil;
}

+ (void)addHistory:(NSDictionary *)detail episode:(NSDictionary *)ep {
    NSString *filmUrl = CBStr(detail, @"url");
    if (!filmUrl) return;
    NSMutableDictionary *item = [@{@"filmUrl": filmUrl, @"title": CBStr(detail, @"title") ?: @"",
                                   @"epTitle": CBStr(ep, @"title") ?: @"", @"epUrl": CBStr(ep, @"url") ?: @"",
                                   @"time": @(CBNowMs())} mutableCopy];
    if (CBStr(detail, @"poster")) item[@"poster"] = CBStr(detail, @"poster");
    NSMutableArray *list = [NSMutableArray arrayWithObject:item];
    for (NSDictionary *h in [self historyList]) {
        if (![CBStr(h, @"filmUrl") isEqualToString:filmUrl] && list.count < kMaxHistory) [list addObject:h];
    }
    [self saveHistory:list];
}

+ (void)removeHistory:(NSString *)filmUrl {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSDictionary *item = [self historyFor:filmUrl];
    NSMutableDictionary *del = [[self stamps:[self k:@"hist_del"]] mutableCopy];
    del[filmUrl] = @(CBNowMs());
    [self setStamps:[self k:@"hist_del"] map:del];
    NSMutableSet *eps = [NSMutableSet set];
    for (NSDictionary *p in [self positionsList]) {
        if ([CBStr(p, @"film") isEqualToString:filmUrl]) [eps addObject:CBStr(p, @"ep") ?: @""];
    }
    if (CBStr(item, @"epUrl")) [eps addObject:CBStr(item, @"epUrl")];
    NSMutableArray *pos = [NSMutableArray array];
    for (NSDictionary *p in [self positionsList]) {
        if (![eps containsObject:CBStr(p, @"ep") ?: @""]) [pos addObject:p];
    }
    [self savePositions:pos];
    NSMutableArray *hist = [NSMutableArray array];
    for (NSDictionary *h in [self historyList]) {
        if (![CBStr(h, @"filmUrl") isEqualToString:filmUrl]) [hist addObject:h];
    }
    [self saveHistory:hist];
}

+ (void)clearHistory {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSMutableDictionary *del = [[self stamps:[self k:@"hist_del"]] mutableCopy];
    NSNumber *now = @(CBNowMs());
    for (NSDictionary *h in [self historyList]) {
        if (CBStr(h, @"filmUrl")) del[CBStr(h, @"filmUrl")] = now;
    }
    for (NSDictionary *p in [self positionsList]) {
        if (CBStr(p, @"film")) del[CBStr(p, @"film")] = now;
    }
    [self setStamps:[self k:@"hist_del"] map:del];
    [self saveHistory:@[]];
    [self savePositions:@[]];
}

#pragma mark - Chỗ đang xem từng tập (giây)

+ (NSMutableArray *)positionsList {
    if (!gPositionsCache) {
        gPositionsCache = [NSMutableArray array];
        id v = [self get:[self k:@"positions_v2"]];
        for (id p in CBIsArr(v) ? v : @[]) {
            if (CBIsDict(p)) [gPositionsCache addObject:p];
        }
    }
    return gPositionsCache;
}

+ (void)savePositions:(NSArray *)list {
    gPositionsCache = [list mutableCopy];
    [self set:[self k:@"positions_v2"] value:list];
}

+ (NSDictionary *)lastPosition:(NSString *)epUrl {
    for (NSDictionary *p in [[self positionsList] reverseObjectEnumerator]) {
        if ([CBStr(p, @"ep") isEqualToString:epUrl]) return p;
    }
    return nil;
}

+ (int)positionOf:(NSString *)epUrl {
    return (int)CBNum([self lastPosition:epUrl], @"sec", 0);
}

+ (BOOL)finished:(NSString *)epUrl {
    NSDictionary *p = [self lastPosition:epUrl];
    return p && CBNum(p, @"sec", -1) == 0;
}

+ (NSSet *)watchedEpisodes {
    NSMutableSet *s = [NSMutableSet set];
    for (NSDictionary *p in [self positionsList]) {
        if (CBStr(p, @"ep")) [s addObject:CBStr(p, @"ep")];
    }
    return s;
}

+ (void)savePosition:(NSString *)epUrl seconds:(int)sec film:(NSString *)filmUrl {
    if (!epUrl.length) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *p in [self positionsList]) {
        if (![CBStr(p, @"ep") isEqualToString:epUrl]) [list addObject:p];
    }
    [list addObject:@{@"ep": epUrl, @"sec": @(MAX(sec, 0)), @"film": filmUrl ?: @"", @"t": @(CBNowMs())}];
    if (list.count > kMaxPositions) [list removeObjectsInRange:NSMakeRange(0, list.count - kMaxPositions)];
    [self savePositions:list];
}

#pragma mark - Phim theo dõi

+ (NSArray *)follows {
    NSMutableArray *list = [NSMutableArray array];
    id v = [self get:[self k:@"follows"]];
    for (id f in CBIsArr(v) ? v : @[]) {
        if (CBIsDict(f)) [list addObject:f];
    }
    return list;
}

+ (NSDictionary *)followOf:(NSString *)filmUrl {
    for (NSDictionary *f in [self follows]) {
        if ([CBStr(f, @"filmUrl") isEqualToString:filmUrl]) return f;
    }
    return nil;
}

+ (void)follow:(NSDictionary *)detail {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSString *url = CBStr(detail, @"url");
    if (!url) return;
    NSInteger n = CBDetailEpisodeCount(detail);
    NSMutableDictionary *f = [@{@"filmUrl": url, @"title": CBStr(detail, @"title") ?: @"", @"count": @(n),
                                @"latest": CBStr(CBDetailLatestEpisode(detail), @"title") ?: @"", @"seen": @(n),
                                @"t": @(CBNowMs())} mutableCopy];
    if (CBStr(detail, @"poster")) f[@"poster"] = CBStr(detail, @"poster");
    NSMutableArray *list = [NSMutableArray arrayWithObject:f];
    for (NSDictionary *x in [self follows]) {
        if (![CBStr(x, @"filmUrl") isEqualToString:url]) [list addObject:x];
    }
    [self set:[self k:@"follows"] value:list];
}

+ (void)unfollow:(NSString *)filmUrl {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSMutableDictionary *del = [[self stamps:[self k:@"follow_del"]] mutableCopy];
    del[filmUrl] = @(CBNowMs());
    [self setStamps:[self k:@"follow_del"] map:del];
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *x in [self follows]) {
        if (![CBStr(x, @"filmUrl") isEqualToString:filmUrl]) [list addObject:x];
    }
    [self set:[self k:@"follows"] value:list];
}

+ (void)updateFollow:(NSString *)filmUrl count:(NSInteger)count latest:(NSString *)latest seen:(BOOL)seen {
    NSMutableArray *list = [NSMutableArray array];
    BOOL found = NO;
    for (NSDictionary *x in [self follows]) {
        if ([CBStr(x, @"filmUrl") isEqualToString:filmUrl]) {
            found = YES;
            NSMutableDictionary *f = [x mutableCopy];
            NSInteger wasSeen = (NSInteger)CBNum(x, @"seen", 0);
            f[@"count"] = @(count);
            f[@"latest"] = latest ?: @"";
            f[@"seen"] = @(seen || count < wasSeen ? count : wasSeen);
            [list addObject:f];
        } else {
            [list addObject:x];
        }
    }
    if (found) [self set:[self k:@"follows"] value:list];
}

#pragma mark - Cài đặt

+ (NSString *)baseUrl {
    id v = [self get:[self k:@"base_url"]] ?: [self get:@"base_url"];
    if (CBIsStr(v) && [v length]) return v;
    // Bản iOS 6: lần đầu dùng KKPhim — phát thẳng được hết (trang mặc định của TV chỉ có trình phát nhúng). Ghi luôn vào cài đặt
    // để lõi (trang chủ, danh mục, bộ lọc) cũng dùng KKPhim — lõi mặc định trang đầu danh sách (yanhh3d)
    [self set:[self k:@"base_url"] value:kKkSite];
    return kKkSite;
}

+ (NSArray *)sites {
    id v = [self get:@"sites"];
    NSMutableArray *list = [NSMutableArray array];
    for (id s in CBIsArr(v) ? v : PresetSites()) {
        if (CBIsStr(s)) [list addObject:s];
    }
    return list;
}

+ (void)setSites:(NSArray *)sites {
    [CBSync soon:3];  // dữ liệu dùng chung với máy đã ghép
    NSSet *old = [NSSet setWithArray:[self sites]];
    NSMutableDictionary *add = [[self stamps:@"sites_add"] mutableCopy];
    NSMutableDictionary *del = [[self stamps:@"sites_del"] mutableCopy];
    NSNumber *now = @(CBNowMs());
    for (NSString *s in sites) {
        if (![old containsObject:s]) add[s] = now;
    }
    for (NSString *s in old) {
        if (![sites containsObject:s]) del[s] = now;
    }
    [self setStamps:@"sites_add" map:add];
    [self setStamps:@"sites_del" map:del];
    [self set:@"sites" value:sites];
}

+ (void)setBaseUrl:(NSString *)url {
    [self set:[self k:@"base_url"] value:url];
    NSArray *sites = [self sites];
    if (![sites containsObject:url]) [self setSites:[sites arrayByAddingObject:url]];
}

+ (BOOL)kids {
    return [self boolKey:[self k:@"kids"] def:NO];
}

+ (void)setKids:(BOOL)on {
    [self set:[self k:@"kids"] value:@(on)];
    [CBSync soon:3];
}

+ (BOOL)homeMix {
    return [self boolKey:[self k:@"home_mix"] def:YES] || [self boolKey:[self k:@"kids"] def:NO];
}

+ (void)setHomeMix:(BOOL)on {
    [self set:[self k:@"home_mix"] value:@(on)];
}

+ (BOOL)autoNext {
    return [self boolKey:[self k:@"auto_next"] def:YES];
}

+ (void)setAutoNext:(BOOL)on {
    [self set:[self k:@"auto_next"] value:@(on)];
}

+ (NSInteger)seekStep {
    id v = [self get:[self k:@"seek_step"]];
    return [v isKindOfClass:[NSNumber class]] && [v integerValue] > 0 ? [v integerValue] : 10;
}

+ (void)setSeekStep:(NSInteger)sec {
    [self set:[self k:@"seek_step"] value:@(sec)];
}

+ (BOOL)videoFill {
    return [self boolKey:[self k:@"video_fill"] def:NO];
}

+ (void)setVideoFill:(BOOL)on {
    [self set:[self k:@"video_fill"] value:@(on)];
}

+ (BOOL)secureDns {
    id v = [self get:@"doh"];
    return !(CBIsStr(v) && [v isEqualToString:@"OFF"]);
}

+ (void)setSecureDns:(BOOL)on {
    [self set:@"doh" value:on ? @"AUTO" : @"OFF"];
    [CBCore networkSettingsChanged];
}

+ (BOOL)unblock {
    return [self boolKey:@"unblock" def:NO];
}

+ (void)setUnblock:(BOOL)on {
    [self set:@"unblock" value:@(on)];
    [CBCore networkSettingsChanged];
}

+ (NSString *)serverTypeForHost:(NSString *)host {
    id v = [self get:[self k:[@"server_type@" stringByAppendingString:host ?: @""]]];
    return CBIsStr(v) ? v : nil;
}

+ (void)setServerForHost:(NSString *)host type:(NSString *)type label:(NSString *)label {
    [self set:[self k:[@"server_type@" stringByAppendingString:host ?: @""]] value:type];
    [self set:[self k:[@"server_label@" stringByAppendingString:host ?: @""]] value:label];
}

+ (NSInteger)disclaimerVersion {
    id v = [self get:@"disclaimer_v"];
    return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : 0;
}

+ (void)setDisclaimerVersion:(NSInteger)v {
    [self set:@"disclaimer_v" value:@(v)];
}

@end

#pragma mark - Phim

NSInteger CBDetailEpisodeCount(NSDictionary *detail) {
    NSInteger n = 0;
    for (id g in CBArr(detail, @"groups") ?: @[]) n = MAX(n, (NSInteger)CBArr(g, @"episodes").count);
    return n;
}

NSDictionary *CBDetailLatestEpisode(NSDictionary *detail) {
    NSArray *best = nil;
    for (id g in CBArr(detail, @"groups") ?: @[]) {
        NSArray *eps = CBArr(g, @"episodes");
        if (eps.count > best.count) best = eps;
    }
    id last = best.lastObject;
    return CBIsDict(last) ? last : nil;
}

NSInteger CBDetailGroupIndexOf(NSDictionary *detail, NSString *epUrl) {
    NSArray *groups = CBArr(detail, @"groups");
    for (NSUInteger i = 0; i < groups.count; i++) {
        for (id e in CBArr(groups[i], @"episodes") ?: @[]) {
            if ([CBStr(e, @"url") isEqualToString:epUrl]) return (NSInteger)i;
        }
    }
    return -1;
}

NSString *CBHostOf(NSString *url) {
    NSString *h = [[NSURL URLWithString:url].host lowercaseString];
    if ([h hasPrefix:@"www."]) h = [h substringFromIndex:4];
    return h;
}
