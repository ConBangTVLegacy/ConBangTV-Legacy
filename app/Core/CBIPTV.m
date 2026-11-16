#import "CBIPTV.h"
#import "CBCore.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#include <zlib.h>

NSString *const CBIPTVChangedNotification = @"CBIPTVChanged";

static NSArray *gChannels;          // kênh của danh sách gChannelsList
static NSString *gChannelsList;
static NSDictionary *gGuide;        // {prog: {khoá: [[s, e, t]…]}, fetched, list}
static NSString *gGuideList;
static BOOL gLoading, gGuideLoading;
static NSString *gStatus;
static NSMutableArray *gWaiters;    // khối done chờ lần tải đang chạy

static long long gLastTry;          // lần gần nhất bắt đầu tải danh sách (ms) — tự làm mới không thử lại dồn dập khi mạng hỏng

static const long long kListMaxAge = 6LL * 3600 * 1000;
/// Danh sách thể thao (có giờ trận): trận mới / link mới thêm liên tục — tải lại sau 30 phút
static const long long kMatchListMaxAge = 30LL * 60 * 1000;
/// Có trận sắp / đang đá mà danh sách chưa có link thật (link giả «no-signal»): link thật thường thêm sát giờ — 5 phút
static const long long kWaitingListMaxAge = 5LL * 60 * 1000;
/// Tự làm mới: vừa thử tải (hỏng) thì chờ chừng này mới thử lại
static const long long kAutoRetryGap = 3LL * 60 * 1000;
/// Đổi cách đọc M3U (2: giờ trận, giữ BLV; 3: link giả «no-signal»; 4: kênh radio; 5: bỏ mã nước «|UK| » đầu tên) — đệm cũ đọc lại
static const NSInteger kParseVersion = 5;
/// Kênh trận đấu thường lên sóng trước giờ bóng lăn chừng này (giây)
static const double kMatchEarly = 30 * 60;
static const long long kGuideMaxAge = 6LL * 3600 * 1000;

#pragma mark - Tệp

static NSString *CBIPTVDir(void) {
    static NSString *dir;
    if (!dir) {
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        dir = [caches stringByAppendingPathComponent:@"iptv"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return dir;
}

static NSString *CBListFile(NSString *listId) {
    return [CBIPTVDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", listId]];
}

static NSString *CBGuideFile(NSString *listId) {
    return [CBIPTVDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"epg-%@.json", listId]];
}

static id CBReadJSON(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
}

static void CBWriteJSON(NSString *path, id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    [d writeToFile:path atomically:YES];
}

/// Văn bản của tệp tải về: UTF-8, không được thì Latin-1 (vài danh sách cũ)
/// Tệp danh sách người xem thêm từ tệp (máy tính gửi qua Wi-Fi, tệp trên máy, «Mở bằng»): giữ ở Documents/ConBangTV-iptv — không
/// phải bộ nhớ đệm (iOS dọn Caches khi máy đầy, mà danh sách này không tải lại được)
static NSString *CBLocalListDir(void) {
    static NSString *dir;
    if (!dir) {
        dir = [CBDocumentsDir() stringByAppendingPathComponent:@"ConBangTV-iptv"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return dir;
}

static NSString *CBReadText(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return nil;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return s ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
}

#pragma mark - Đọc M3U

static NSDictionary *CBAttrs(NSString *s) {
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"([A-Za-z0-9_-]+)=\"([^\"]*)\"" options:0 error:NULL];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        out[[[s substringWithRange:[m rangeAtIndex:1]] lowercaseString]] = [s substringWithRange:[m rangeAtIndex:2]];
    }
    return out;
}

/// Tên kênh sau dấu phẩy đầu tiên nằm ngoài ngoặc kép của dòng #EXTINF
static NSString *CBExtinfName(NSString *line) {
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '"') quoted = !quoted;
        else if (c == ',' && !quoted) {
            return [[line substringFromIndex:i + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return nil;
}

static NSString *CBFirstUrl(NSString *s) {
    for (NSString *p in [s componentsSeparatedByString:@","]) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t hasPrefix:@"http://"] || [t hasPrefix:@"https://"]) return t;
    }
    return nil;
}

static long long CBDaysFromCivil(long y, unsigned m, unsigned d);

/// Giờ trận ghi trong tên kênh thể thao («20:00 16/11 ⚽ A vs B (BLV …)», «16/11 20:00 …», «20h00 16/11») → giây từ 1970.
/// Giờ Việt Nam (UTC+7) — danh sách thể thao là của trang Việt; không ghi năm thì lấy năm gần bây giờ nhất (qua giao thừa).
/// *range = chỗ ghi giờ trong tên (bỏ khỏi tên hiển thị). NAN = tên không ghi giờ trận.
static double CBKickoff(NSString *name, long nowYear, NSRange *range) {
    static NSRegularExpression *timeFirst, *dateFirst;
    if (!timeFirst) {
        timeFirst = [NSRegularExpression regularExpressionWithPattern:
            @"(?<![\\d:/])(\\d{1,2})[:hH](\\d{2})\\s*[-,|·]?\\s*(?:ngày\\s*)?(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?(?![\\d:/])" options:0 error:NULL];
        dateFirst = [NSRegularExpression regularExpressionWithPattern:
            @"(?<![\\d:/])(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\s*[-,|·]?\\s*(\\d{1,2})[:hH](\\d{2})(?![\\d:/])" options:0 error:NULL];
    }
    NSRange all = NSMakeRange(0, name.length);
    NSTextCheckingResult *m = [timeFirst firstMatchInString:name options:0 range:all];
    BOOL tf = m != nil;
    if (!m) m = [dateFirst firstMatchInString:name options:0 range:all];
    if (!m) return NAN;
    NSInteger (^g)(NSUInteger) = ^NSInteger(NSUInteger i) {
        NSRange r = [m rangeAtIndex:i];
        return r.location == NSNotFound ? 0 : [[name substringWithRange:r] integerValue];
    };
    NSInteger h = tf ? g(1) : g(4), mi = tf ? g(2) : g(5), d = tf ? g(3) : g(1), mo = tf ? g(4) : g(2), y = tf ? g(5) : g(3);
    if (h > 23 || mi > 59 || d < 1 || d > 31 || mo < 1 || mo > 12) return NAN;
    if (y && y < 100) y += 2000;
    double now = [[NSDate date] timeIntervalSince1970], best = NAN;
    for (long yy = y ? y : nowYear - 1; yy <= (y ? y : nowYear + 1); yy++) {
        double t = (double)CBDaysFromCivil(yy, (unsigned)mo, (unsigned)d) * 86400 + h * 3600 + mi * 60 - 7 * 3600;
        if (isnan(best) || fabs(t - now) < fabs(best - now)) best = t;
    }
    if (range) *range = m.range;
    return best;
}

/// Emoji mới hơn Unicode 6 (🟢 🥎 🏐 🥅…): iOS 5 / 6 vẽ thành ô vuông — bỏ (🥎 bóng mềm → 🎾 cho các trận quần vợt)
static NSString *CBOldEmoji(NSString *s) {
    if (![s canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        s = [s stringByReplacingOccurrencesOfString:@"🥎" withString:@"🎾"];
        NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
        NSUInteger i = 0, n = s.length;
        while (i < n) {
            unichar c = [s characterAtIndex:i];
            if (CFStringIsSurrogateHighCharacter(c) && i + 1 < n) {
                UTF32Char cp = CFStringGetLongCharacterForSurrogatePair(c, [s characterAtIndex:i + 1]);
                BOOL newer = cp >= 0x1F900 || (cp >= 0x1F7E0 && cp <= 0x1F7FF) || (cp >= 0x1F3CF && cp <= 0x1F3D3) ||
                             (cp >= 0x1F3F8 && cp <= 0x1F3FF) || (cp >= 0x1F6D0 && cp <= 0x1F6FF);
                if (!newer) [out appendString:[s substringWithRange:NSMakeRange(i, 2)]];
                i += 2;
            } else {
                [out appendFormat:@"%C", c];
                i++;
            }
        }
        s = out;
    }
    static NSRegularExpression *spaces;
    if (!spaces) spaces = [NSRegularExpression regularExpressionWithPattern:@"\\s{2,}" options:0 error:NULL];
    s = [spaces stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/// Thời lượng trận (phút) theo môn ghi trong tên — để biết lúc nào «Đã xong»
static NSInteger CBMatchMinutes(NSString *name) {
    if ([name rangeOfString:@"⚽"].location != NSNotFound) return 130;   // 90' + nghỉ giữa hiệp + bù giờ
    if ([name rangeOfString:@"🎾"].location != NSNotFound || [name rangeOfString:@"🥎"].location != NSNotFound) return 200;
    return 150;
}

/// Luồng HTTP-FLV (lõi đổi sang HLS — nặng hơn HLS gốc một chút): xếp sau
static BOOL CBIsFlv(NSString *url) {
    return [[[[NSURL URLWithString:url] path] lowercaseString] hasSuffix:@".flv"];
}

/// Link giả «không có tín hiệu» (danh sách thể thao để sẵn cho trận chưa có link thật — vd …/no-signal/low.m3u8: một ảnh 10 s)
static BOOL CBIsPlaceholder(NSString *url) {
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"(?i)no[-_]?signal" options:0 error:NULL];
    NSString *path = [[NSURL URLWithString:url] path] ?: url;
    return [re firstMatchInString:path options:0 range:NSMakeRange(0, path.length)] != nil;
}

/// Thứ tự nguồn: HLS → FLV → link giả
static NSInteger CBSourceRank(NSString *url) {
    return CBIsPlaceholder(url) ? 2 : (CBIsFlv(url) ? 1 : 0);
}

/// Đài radio: danh sách ghi `radio="true"` (kiểu Kodi / iptv-org), nhóm tên «Radio» / «Phát thanh» / «Truyền thanh», hoặc link
/// tệp tiếng / danh sách của đài (.mp3, .aac, .pls). Đài không đánh dấu (link không đuôi) trình phát vẫn nhận ra lúc mở.
static BOOL CBIsRadio(NSDictionary *attrs, NSString *group, NSString *url) {
    NSString *r = [attrs[@"radio"] lowercaseString];
    if ([r isEqualToString:@"true"] || [r isEqualToString:@"1"]) return YES;
    NSString *g = [CBIPTV norm:group ?: @""];
    if ([g rangeOfString:@"radio"].location != NSNotFound || [g rangeOfString:@"phat thanh"].location != NSNotFound ||
        [g rangeOfString:@"truyen thanh"].location != NSNotFound) return YES;
    NSString *ext = [[[[NSURL URLWithString:url] path] pathExtension] lowercaseString];
    return [@[@"mp3", @"aac", @"pls"] containsObject:ext ?: @""];
}

/// {epg, channels}
static NSDictionary *CBParseM3U(NSString *text) {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:7 * 3600];
    long nowYear = (long)[cal components:NSYearCalendarUnit fromDate:[NSDate date]].year;
    NSString *epg = nil;
    NSMutableArray *order = [NSMutableArray array];          // khoá gộp theo thứ tự
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    NSDictionary *attrs = nil;
    NSString *name = nil, *group = nil, *ref = nil, *ua = nil;
    NSInteger index = 0;
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!l.length) continue;
        if ([l hasPrefix:@"﻿"]) l = [l substringFromIndex:1];
        if ([l hasPrefix:@"#EXTM3U"]) {
            NSDictionary *h = CBAttrs(l);
            epg = CBFirstUrl(h[@"url-tvg"] ?: h[@"x-tvg-url"] ?: h[@"tvg-url"] ?: @"") ?: epg;
        } else if ([l hasPrefix:@"#EXTINF"]) {
            NSString *n = CBExtinfName(l);
            NSString *head = n ? [l substringToIndex:l.length - n.length] : l;
            attrs = CBAttrs(head);
            name = n.length ? n : attrs[@"tvg-name"];
            group = attrs[@"group-title"];
            ref = nil;
            ua = nil;
        } else if ([l hasPrefix:@"#EXTGRP:"]) {
            group = [[l substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        } else if ([l hasPrefix:@"#EXTVLCOPT:"]) {
            NSString *o = [l substringFromIndex:11];
            NSRange eq = [o rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *k = [[o substringToIndex:eq.location] lowercaseString], *v = [o substringFromIndex:eq.location + 1];
            if ([k isEqualToString:@"http-referrer"] || [k isEqualToString:@"http-referer"]) ref = v;
            if ([k isEqualToString:@"http-user-agent"]) ua = v;
        } else if (![l hasPrefix:@"#"]) {
            NSString *url = l;
            NSRange bar = [url rangeOfString:@"|"];
            if (bar.location != NSNotFound) {  // «url|Referer=…&User-Agent=…» (kiểu Kodi)
                for (NSString *kv in [[url substringFromIndex:bar.location + 1] componentsSeparatedByString:@"&"]) {
                    NSRange e = [kv rangeOfString:@"="];
                    if (e.location == NSNotFound) continue;
                    NSString *k = [[kv substringToIndex:e.location] lowercaseString];
                    NSString *v = [[kv substringFromIndex:e.location + 1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                    if ([k isEqualToString:@"referer"] || [k isEqualToString:@"referrer"]) ref = v;
                    if ([k isEqualToString:@"user-agent"]) ua = v;
                }
                url = [url substringToIndex:bar.location];
            }
            if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
                index++;
                NSString *n = name.length ? name : ([[NSURL URLWithString:url] lastPathComponent] ?: url);
                // Kênh thể thao ghi giờ trận trong tên: giờ tách riêng (dòng trạng thái «Sắp đá 20:00»), giữ «(BLV …)» — mỗi bình luận
                // viên là một kênh — chỉ bỏ thẻ «[hls]», «[flv]», «[FHD]»; bản HLS / FLV của cùng BLV gộp thành nhiều nguồn
                NSRange kr;
                double kick = CBKickoff(n, nowYear, &kr);
                // Chỉ tên kiểu trận đấu («A vs B», có BLV / biểu tượng môn) — «Updated 16/11 15:36» không phải trận
                static NSRegularExpression *matchy;
                if (!matchy) matchy = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\bvs?\\.?\\s|\\s[-–]\\s|BLV|⚽|🏀|🎾|🥎|🏐|🏸|🏒|🥊|🏈|⚾"
                                                                                options:0 error:NULL];
                if (!isnan(kick) && ![matchy firstMatchInString:n options:0 range:NSMakeRange(0, n.length)]) kick = NAN;
                NSString *k;
                NSInteger minutes = 0;
                if (!isnan(kick)) {
                    minutes = CBMatchMinutes(n);
                    n = [n stringByReplacingCharactersInRange:kr withString:@" "];
                    static NSRegularExpression *tags;
                    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"\\[[^\\]]*\\]" options:0 error:NULL];
                    NSString *bare = CBOldEmoji([tags stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""]);
                    if (bare.length) n = bare;
                    NSString *flat = [[n stringByReplacingOccurrencesOfString:@"(" withString:@" "] stringByReplacingOccurrencesOfString:@")" withString:@" "];
                    k = [NSString stringWithFormat:@"%@@%lld", [CBIPTV norm:flat], (long long)(kick / 60)];
                } else {
                    // Tên hiển thị bỏ phần trong ngoặc («Can Tho TV 2 (1080p) [Geo-blocked]» → «Can Tho TV 2»)
                    static NSRegularExpression *br;
                    if (!br) br = [NSRegularExpression regularExpressionWithPattern:@"\\s*(\\([^)]*\\)|\\[[^\\]]*\\])" options:0 error:NULL];
                    // Danh sách kiểu Xtream ghi mã nước đầu tên: «|UK| SPORT 1 HD», «DE| ZDF» → bỏ (tên ô kênh khỏi cụt)
                    static NSRegularExpression *tag;
                    if (!tag) tag = [NSRegularExpression regularExpressionWithPattern:@"^\\|?[A-Z0-9]{2,5}\\|\\s*" options:0 error:NULL];
                    NSString *untagged = [tag stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""];
                    if (untagged.length) n = untagged;
                    NSString *bare = [[br stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (bare.length) n = bare;
                    k = [CBIPTV norm:n];
                    if (!k.length) k = [n lowercaseString];
                }
                NSString *g = group.length ? group : @"Khác";
                NSString *mk = [NSString stringWithFormat:@"%@|%@", k, g];
                NSMutableDictionary *c = byKey[mk];
                if (c) {
                    NSMutableArray *urls = c[@"urls"];
                    if (![urls containsObject:url]) {
                        // HLS trước FLV, link giả cuối cùng
                        NSUInteger at = urls.count;
                        NSInteger rank = CBSourceRank(url);
                        for (NSUInteger i = 0; i < urls.count; i++) if (CBSourceRank(urls[i]) > rank) { at = i; break; }
                        [urls insertObject:url atIndex:at];
                        // Nguồn gộp vào có Referer / User-Agent khác kênh: ghi riêng cho nguồn
                        BOOL sameRef = (!ref.length && !CBStr(c, @"ref")) || [ref isEqualToString:CBStr(c, @"ref")];
                        BOOL sameUa = (!ua.length && !CBStr(c, @"ua")) || [ua isEqualToString:CBStr(c, @"ua")];
                        if (!sameRef || !sameUa) {
                            if (!c[@"hdr"]) c[@"hdr"] = [NSMutableDictionary dictionary];
                            c[@"hdr"][url] = @{@"ref": ref ?: @"", @"ua": ua ?: @""};
                        }
                    }
                } else {
                    c = [NSMutableDictionary dictionary];
                    c[@"k"] = k;
                    c[@"n"] = n;
                    c[@"g"] = g;
                    c[@"urls"] = [NSMutableArray arrayWithObject:url];
                    NSString *chno = attrs[@"tvg-chno"];
                    c[@"num"] = chno.length ? chno : [NSString stringWithFormat:@"%ld", (long)index];
                    if ([attrs[@"tvg-logo"] hasPrefix:@"http"]) c[@"logo"] = attrs[@"tvg-logo"];
                    if ([attrs[@"tvg-id"] length]) c[@"id"] = attrs[@"tvg-id"];
                    if (!isnan(kick)) {
                        c[@"kick"] = @(kick);
                        c[@"dur"] = @(minutes);
                    }
                    if (ref.length) c[@"ref"] = ref;
                    if (ua.length) c[@"ua"] = ua;
                    if (CBIsRadio(attrs, g, url)) c[@"radio"] = @YES;
                    byKey[mk] = c;
                    [order addObject:mk];
                }
            }
            attrs = nil;
            name = nil;
            group = nil;
            ref = nil;
            ua = nil;
        }
    }
    NSMutableArray *channels = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *mk in order) {
        NSMutableDictionary *c = byKey[mk];
        // Mọi nguồn đều là link giả: danh sách chưa có link phát
        BOOL nolink = YES;
        for (NSString *u in c[@"urls"]) if (!CBIsPlaceholder(u)) { nolink = NO; break; }
        if (nolink) c[@"nolink"] = @YES;
        [channels addObject:c];
    }
    NSMutableDictionary *out = [@{@"channels": channels, @"v": @(kParseVersion)} mutableCopy];
    if (epg) out[@"epg"] = epg;
    return out;
}

#pragma mark - Đọc XMLTV

static long long CBDaysFromCivil(long y, unsigned m, unsigned d) {
    y -= m <= 2;
    long era = (y >= 0 ? y : y - 399) / 400;
    unsigned yoe = (unsigned)(y - era * 400);
    unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return (long long)era * 146097 + (long long)doe - 719468;
}

/// «20261116190000 +0700» → giây từ 1970 (UTC); NAN nếu sai dạng
static double CBXmltvTime(NSString *s) {
    const char *c = s.UTF8String;
    if (!c || strlen(c) < 12) return NAN;
    int v[6] = {0};
    int widths[6] = {4, 2, 2, 2, 2, 2};
    const char *p = c;
    for (int i = 0; i < 6; i++) {
        if (i == 5 && !(p[0] >= '0' && p[0] <= '9')) break;  // không có giây
        for (int k = 0; k < widths[i]; k++, p++) {
            if (*p < '0' || *p > '9') return NAN;
            v[i] = v[i] * 10 + (*p - '0');
        }
    }
    double t = (double)CBDaysFromCivil(v[0], (unsigned)v[1], (unsigned)v[2]) * 86400 + v[3] * 3600 + v[4] * 60 + v[5];
    while (*p == ' ') p++;
    if ((*p == '+' || *p == '-') && strlen(p) >= 5) {
        int hh = (p[1] - '0') * 10 + (p[2] - '0'), mm = (p[3] - '0') * 10 + (p[4] - '0');
        double off = hh * 3600 + mm * 60;
        t -= *p == '+' ? off : -off;
    }
    return t;
}

@interface CBEPGParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSSet *wantedIds;
@property (nonatomic, strong) NSSet *wantedNames;
@property (nonatomic, strong) NSMutableDictionary *prog;   // khoá → [[s, e, t]]
@property (nonatomic) double from, to;
@end

@implementation CBEPGParser {
    NSMutableDictionary *_alias;    // id kênh trong EPG → «n:<tên chuẩn hoá>»
    NSString *_chan, *_progChan;
    double _start, _stop;
    NSMutableString *_text;
    BOOL _inName, _inTitle;
    NSString *_title;
}

- (instancetype)init {
    if ((self = [super init])) {
        _prog = [NSMutableDictionary dictionary];
        _alias = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary *)attr {
    if ([el isEqualToString:@"channel"]) {
        _chan = attr[@"id"];
    } else if ([el isEqualToString:@"display-name"] && _chan) {
        _inName = YES;
        _text = [NSMutableString string];
    } else if ([el isEqualToString:@"programme"]) {
        _progChan = nil;
        _title = nil;
        NSString *cid = attr[@"channel"];
        if (!cid) return;
        NSString *key = [_wantedIds containsObject:cid] ? cid : _alias[cid];
        if (!key) return;
        _start = CBXmltvTime(attr[@"start"] ?: @"");
        _stop = CBXmltvTime(attr[@"stop"] ?: @"");
        if (isnan(_start) || _start > _to || (!isnan(_stop) && _stop < _from) || (isnan(_stop) && _start < _from)) return;
        _progChan = key;
    } else if ([el isEqualToString:@"title"] && _progChan && !_title) {
        _inTitle = YES;
        _text = [NSMutableString string];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)s {
    if (_inName || _inTitle) [_text appendString:s];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([el isEqualToString:@"display-name"] && _inName) {
        _inName = NO;
        NSString *n = [CBIPTV norm:_text];
        if (n.length && [_wantedNames containsObject:n] && ![_wantedIds containsObject:_chan] && !_alias[_chan]) {
            _alias[_chan] = [@"n:" stringByAppendingString:n];
        }
    } else if ([el isEqualToString:@"channel"]) {
        _chan = nil;
    } else if ([el isEqualToString:@"title"] && _inTitle) {
        _inTitle = NO;
        _title = [_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } else if ([el isEqualToString:@"programme"] && _progChan) {
        NSMutableArray *list = _prog[_progChan];
        if (!list) _prog[_progChan] = list = [NSMutableArray array];
        double e = isnan(_stop) ? _start + 1800 : _stop;
        [list addObject:@[@(_start), @(e), _title.length ? _title : @"(không tên)"]];
        _progChan = nil;
    }
}

@end

/// Tải tệp bằng mạng của iOS (NSURLConnection — DNS của máy, tự theo chuyển hướng, tin thêm gốc Mozilla như ảnh bìa): dự
/// phòng khi lõi tải lỗi. iPad 1 (16/11): lõi quá giờ với một link rút gọn, mạng của iOS thì được.
@interface CBIPTVFetch : NSObject <NSURLConnectionDataDelegate>
+ (void)fetch:(NSString *)url to:(NSString *)path done:(void (^)(NSString *err))done;
@end

@implementation CBIPTVFetch {
    NSString *_path;
    NSFileHandle *_out;
    NSInteger _code;
    void (^_done)(NSString *);
    NSURLConnection *_conn;
    CBIPTVFetch *_self;   // giữ mình sống tới khi xong
}

+ (void)fetch:(NSString *)url to:(NSString *)path done:(void (^)(NSString *))done {
    CBIPTVFetch *f = [[CBIPTVFetch alloc] init];
    f->_path = path;
    f->_done = [done copy];
    f->_self = f;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [req setValue:@"Mozilla/5.0 (iPad; CPU OS 6_1 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko)" forHTTPHeaderField:@"User-Agent"];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    f->_out = [NSFileHandle fileHandleForWritingAtPath:path];
    f->_conn = [[NSURLConnection alloc] initWithRequest:req delegate:f startImmediately:NO];
    [f->_conn scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [f->_conn start];
}

- (void)finish:(NSString *)err {
    [_out closeFile];
    _out = nil;
    void (^done)(NSString *) = _done;
    _done = nil;
    _self = nil;
    if (done) done(err);
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)c {
    [CBImages handleChallenge:c];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    [_out truncateFileAtOffset:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_out writeData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self finish:_code >= 400 ? [NSString stringWithFormat:@"HTTP %ld", (long)_code] : nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self finish:error.localizedDescription ?: @"lỗi mạng"];
}

@end

/// Tải qua lõi; lõi lỗi thì thử lại bằng mạng của iOS. done trên luồng chính, err = lỗi của lõi nếu cả hai cùng lỗi
static void CBDownload(NSString *url, NSString *path, void (^done)(NSString *err)) {
    long long t0 = CBNowMs();
    [CBCore call:@"http.download" args:@{@"url": url, @"path": path} done:^(id ok, NSString *err) {
        if (!err) {
            done(nil);
            return;
        }
        CBLog(@"IPTV: lõi tải %@ lỗi (%@, %lld ms) — thử bằng mạng của iOS", url, err, CBNowMs() - t0);
        long long t1 = CBNowMs();
        [CBIPTVFetch fetch:url to:path done:^(NSString *err2) {
            CBLog(@"IPTV: mạng của iOS tải %@: %@ (%lld ms)", url, err2 ?: @"được", CBNowMs() - t1);
            done(err2 ? err : nil);
        }];
    }];
}

/// Giải nén .gz (gzread đọc cả tệp không nén) ra tệp dst theo từng khúc 64 KB
static BOOL CBGunzip(NSString *src, NSString *dst) {
    gzFile in = gzopen(src.fileSystemRepresentation, "rb");
    if (!in) return NO;
    FILE *out = fopen(dst.fileSystemRepresentation, "wb");
    if (!out) {
        gzclose(in);
        return NO;
    }
    char buf[65536];
    int n;
    BOOL ok = YES;
    while ((n = gzread(in, buf, sizeof buf)) > 0) {
        if (fwrite(buf, 1, (size_t)n, out) != (size_t)n) {
            ok = NO;
            break;
        }
    }
    if (n < 0) ok = NO;
    gzclose(in);
    fclose(out);
    return ok;
}

@implementation CBIPTV

#pragma mark - Danh sách

+ (NSArray *)lists {
    id v = [CBPrefs get:@"iptv_lists"];
    return CBIsArr(v) ? v : @[];
}

+ (void)saveLists:(NSArray *)lists {
    [CBPrefs set:@"iptv_lists" value:lists];
}

+ (NSDictionary *)activeList {
    NSArray *lists = [self lists];
    id active = [CBPrefs get:@"iptv_active"];
    for (NSDictionary *l in lists) if ([CBStr(l, @"id") isEqualToString:active]) return l;
    return lists.firstObject;
}

+ (void)setActive:(NSString *)listId {
    [CBPrefs set:@"iptv_active" value:listId ?: @""];
    gChannels = nil;
    gChannelsList = nil;
    gGuide = nil;
    gGuideList = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
}

+ (void)updateList:(NSString *)listId with:(NSDictionary *)changes {
    NSMutableArray *lists = [[self lists] mutableCopy];
    for (NSUInteger i = 0; i < lists.count; i++) {
        if (![CBStr(lists[i], @"id") isEqualToString:listId]) continue;
        NSMutableDictionary *l = [lists[i] mutableCopy];
        [changes enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            if (v == [NSNull null]) [l removeObjectForKey:k];
            else l[k] = v;
        }];
        lists[i] = l;
    }
    [self saveLists:lists];
}

+ (NSDictionary *)addList:(NSString *)url name:(NSString *)name {
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) url = [@"http://" stringByAppendingString:url];
    if (!name.length) {
        NSURL *u = [NSURL URLWithString:url];
        NSString *file = [[u.lastPathComponent stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        name = file.length > 2 && ![file isEqualToString:@"/"] ? file : (u.host ?: @"Danh sách kênh");
    }
    NSDictionary *l = @{@"id": [NSString stringWithFormat:@"l%lld", CBNowMs()], @"name": name, @"url": url};
    [self saveLists:[[self lists] arrayByAddingObject:l]];
    [self setActive:l[@"id"]];
    return l;
}

+ (NSDictionary *)addListWithData:(NSData *)data fileName:(NSString *)fileName name:(NSString *)name error:(NSString **)error {
    NSString *text = data.length ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                    ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding]) : nil;
    if (!text || ([text rangeOfString:@"#EXTINF"].location == NSNotFound && [text rangeOfString:@"http"].location == NSNotFound)) {
        if (error) *error = data.length ? @"Tệp không phải danh sách M3U (không có dòng #EXTINF / địa chỉ kênh nào)." : @"Tệp trống.";
        return nil;
    }
    if (!name.length) {
        // «iptv-playlist---2026-11-11T131814-437.m3u» → «iptv-playlist»
        NSString *n = [[fileName lastPathComponent] stringByDeletingPathExtension] ?: @"";
        static NSRegularExpression *stamp;
        if (!stamp) stamp = [NSRegularExpression regularExpressionWithPattern:@"[-_ ]*\\d{4}-\\d{2}-\\d{2}([T_ ]?[\\d.:-]*)?$" options:0 error:NULL];
        n = [stamp stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""];
        n = [[n stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByTrimmingCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@" -."]];
        name = n.length ? (n.length > 40 ? [n substringToIndex:40] : n) : @"Danh sách từ tệp";
    }
    NSString *lid = [NSString stringWithFormat:@"l%lld", CBNowMs()];
    NSString *file = [lid stringByAppendingPathExtension:@"m3u"];
    if (![data writeToFile:[CBLocalListDir() stringByAppendingPathComponent:file] atomically:YES]) {
        if (error) *error = @"Không ghi được tệp vào máy (bộ nhớ đầy?).";
        return nil;
    }
    NSDictionary *l = @{@"id": lid, @"name": name, @"file": file, @"src": [fileName lastPathComponent] ?: file};
    [self saveLists:[[self lists] arrayByAddingObject:l]];
    [self setActive:lid];
    CBLog(@"IPTV: thêm danh sách từ tệp «%@» (%lu byte) → %@", fileName, (unsigned long)data.length, lid);
    return l;
}

+ (NSString *)localFileOf:(NSDictionary *)list {
    NSString *f = CBStr(list, @"file");
    return f ? [CBLocalListDir() stringByAppendingPathComponent:f] : nil;
}

+ (void)renameList:(NSString *)listId name:(NSString *)name {
    if (name.length) [self updateList:listId with:@{@"name": name}];
}

+ (void)removeList:(NSString *)listId {
    NSMutableArray *lists = [NSMutableArray array];
    for (NSDictionary *l in [self lists]) {
        if (![CBStr(l, @"id") isEqualToString:listId]) [lists addObject:l];
        else if ([self localFileOf:l]) [[NSFileManager defaultManager] removeItemAtPath:[self localFileOf:l] error:NULL];
    }
    [self saveLists:lists];
    [[NSFileManager defaultManager] removeItemAtPath:CBListFile(listId) error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:CBGuideFile(listId) error:NULL];
    if ([gChannelsList isEqualToString:listId] || ![[self activeList][@"id"] isEqualToString:gChannelsList]) {
        [self setActive:CBStr(lists.firstObject, @"id")];
    }
}

+ (NSArray *)channels {
    NSDictionary *l = [self activeList];
    NSString *lid = CBStr(l, @"id");
    if (!lid) return nil;
    if (gChannels && [gChannelsList isEqualToString:lid]) return gChannels;
    id cached = CBReadJSON(CBListFile(lid));
    if (CBIsArr(CBArr(cached, @"channels")) && CBNum(cached, @"v", 1) >= kParseVersion) {
        gChannels = CBArr(cached, @"channels");
        gChannelsList = lid;
        return gChannels;
    }
    return nil;
}

+ (BOOL)loading {
    return gLoading || gGuideLoading;
}

+ (NSString *)status {
    return gStatus;
}

+ (void)finishWaiters:(NSString *)err {
    NSArray *w = gWaiters;
    gWaiters = nil;
    for (void (^b)(NSString *) in w) b(err);
}

/// Danh sách cũ quá bao lâu thì tải lại (ms): có trận sắp / đang đá mà chưa có link thật → 5 phút; có trận → 30 phút; còn lại 6 giờ
static long long CBListMaxAge(NSArray *channels) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL matches = NO;
    for (NSDictionary *c in channels) {
        double kick = CBNum(c, @"kick", 0);
        if (kick <= 0) continue;
        matches = YES;
        if (CBNum(c, @"nolink", 0) && now >= kick - kMatchEarly && now < kick + CBNum(c, @"dur", 150) * 60) return kWaitingListMaxAge;
    }
    return matches ? kMatchListMaxAge : kListMaxAge;
}

+ (void)autoRefresh {
    NSDictionary *l = [self activeList];
    if (!l || CBStr(l, @"file") || gLoading || gGuideLoading || CBNowMs() - gLastTry < kAutoRetryGap) return;
    NSArray *have = [self channels];
    if (have && CBNowMs() - (long long)CBNum(l, @"updated", 0) < CBListMaxAge(have)) return;
    CBLog(@"IPTV: tự làm mới danh sách «%@» (cập nhật lần trước %@)", CBStr(l, @"name"),
          CBNum(l, @"updated", 0) > 0 ? [self clock:CBNum(l, @"updated", 0) / 1000] : @"chưa");
    [self refresh:NO done:nil];
}

+ (void)refresh:(BOOL)force done:(void (^)(NSString *))done {
    NSDictionary *l = [self activeList];
    NSString *lid = CBStr(l, @"id"), *url = CBStr(l, @"url");
    // Danh sách thêm từ tệp: đọc lại bản đã chép vào app (không tải mạng, không tự làm mới — tệp mới thì người xem thêm lại)
    NSString *local = [self localFileOf:l];
    if (!lid || (!url && !local)) {
        if (done) done(@"Chưa có danh sách kênh");
        return;
    }
    if (!url) url = [@"tệp " stringByAppendingString:CBStr(l, @"src") ?: CBStr(l, @"file")];
    if (!gWaiters) gWaiters = [NSMutableArray array];
    if (done) [gWaiters addObject:[done copy]];
    if (gLoading) return;
    NSArray *have = [self channels];
    BOOL fresh = local || CBNowMs() - (long long)CBNum(l, @"updated", 0) < CBListMaxAge(have);
    if (!force && fresh && have) {
        [self finishWaiters:nil];
        [self refreshGuide:NO done:nil];
        return;
    }
    gLoading = YES;
    gLastTry = CBNowMs();
    gStatus = local ? @"Đang đọc danh sách kênh…" : @"Đang tải danh sách kênh…";
    [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
    NSString *tmp = [CBIPTVDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m3u", lid]];
    long long t0 = CBNowMs();
    void (^got)(NSString *) = ^(NSString *err) {
        if (err) {
            CBLog(@"IPTV: tải danh sách %@ lỗi: %@", url, err);
            gLoading = NO;
            gStatus = nil;
            [self updateList:lid with:@{@"err": err}];
            [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
            [self finishWaiters:[NSString stringWithFormat:@"Không tải được danh sách kênh: %@", err]];
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *text = CBReadText(tmp);
            [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
            NSDictionary *parsed = text ? CBParseM3U(text) : nil;
            NSArray *channels = CBArr(parsed, @"channels");
            if (channels.count) CBWriteJSON(CBListFile(lid), parsed);
            dispatch_async(dispatch_get_main_queue(), ^{
                gLoading = NO;
                gStatus = nil;
                if (!channels.count) {
                    NSString *why = [text rangeOfString:@"#EXTINF"].location == NSNotFound
                        ? @"Tệp tải về không phải danh sách M3U." : @"Danh sách không có kênh nào.";
                    [self updateList:lid with:@{@"err": why}];
                    [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
                    [self finishWaiters:why];
                    return;
                }
                CBLog(@"IPTV: danh sách %@ — %lu kênh, lịch %@ (%lld ms)", url, (unsigned long)channels.count,
                      CBStr(parsed, @"epg") ?: @"không có", CBNowMs() - t0);
                gChannels = channels;
                gChannelsList = lid;
                [self updateList:lid with:@{@"count": @(channels.count), @"updated": @(CBNowMs()), @"err": [NSNull null],
                                            @"epg": CBStr(parsed, @"epg") ?: [NSNull null]}];
                [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
                [self finishWaiters:nil];
                [self refreshGuide:NO done:nil];
            });
        });
    };
    if (local) {
        // Chép ra tệp tạm như bản tải về (khối đọc xoá tệp tạm sau khi đọc)
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
        BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:local toPath:tmp error:NULL];
        got(ok ? nil : @"không đọc được tệp danh sách đã lưu");
    } else {
        CBDownload(url, tmp, got);
    }
}

#pragma mark - Lịch

+ (NSDictionary *)guide {
    NSString *lid = CBStr([self activeList], @"id");
    if (!lid) return nil;
    if (gGuide && [gGuideList isEqualToString:lid]) return gGuide;
    id cached = CBReadJSON(CBGuideFile(lid));
    if (CBIsDict(cached)) {
        gGuide = cached;
        gGuideList = lid;
    }
    return gGuide;
}

+ (long long)guideUpdated {
    return (long long)CBNum([self guide], @"fetched", 0);
}

+ (NSUInteger)guideChannelCount {
    return CBDict([self guide], @"prog").count;
}

+ (NSString *)epgOverride {
    id v = [CBPrefs get:@"iptv_epg_url"];
    return CBIsStr(v) && [v length] ? v : nil;
}

+ (void)setEpgOverride:(NSString *)url {
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (url.length) [CBPrefs set:@"iptv_epg_url" value:url];
    else [CBPrefs remove:@"iptv_epg_url"];
}

+ (NSString *)epgUrl {
    return [self epgOverride] ?: CBStr([self activeList], @"epg");
}

+ (void)refreshGuide:(BOOL)force done:(void (^)(NSString *))done {
    NSString *lid = CBStr([self activeList], @"id"), *url = [self epgUrl];
    NSArray *channels = [self channels];
    if (!lid || !url.length || !channels.count) {
        if (done) done(url.length ? @"Chưa tải danh sách kênh" : @"Danh sách không ghi địa chỉ lịch phát sóng (EPG)");
        return;
    }
    NSDictionary *g = [self guide];
    if (gGuideLoading || (!force && g && [CBStr(g, @"src") isEqualToString:url] &&
                          CBNowMs() - (long long)CBNum(g, @"fetched", 0) < kGuideMaxAge)) {
        if (done) done(nil);
        return;
    }
    gGuideLoading = YES;
    gStatus = @"Đang tải lịch phát sóng…";
    [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
    NSString *raw = [CBIPTVDir() stringByAppendingPathComponent:@"epg.download"];
    NSString *xml = [CBIPTVDir() stringByAppendingPathComponent:@"epg.xml"];
    NSMutableSet *ids = [NSMutableSet set], *names = [NSMutableSet set];
    for (NSDictionary *c in channels) {
        if (CBStr(c, @"id")) [ids addObject:CBStr(c, @"id")];
        if (CBStr(c, @"k")) [names addObject:CBStr(c, @"k")];
    }
    long long t0 = CBNowMs();
    CBDownload(url, raw, ^(NSString *err) {
        if (err) {
            CBLog(@"IPTV: tải lịch %@ lỗi: %@", url, err);
            gGuideLoading = NO;
            gStatus = nil;
            [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
            if (done) done([NSString stringWithFormat:@"Không tải được lịch phát sóng: %@", err]);
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            long long t1 = CBNowMs();
            BOOL unz = CBGunzip(raw, xml);
            [[NSFileManager defaultManager] removeItemAtPath:raw error:NULL];
            NSDictionary *result = nil;
            if (unz) {
                @autoreleasepool {
                    CBEPGParser *p = [[CBEPGParser alloc] init];
                    double now = [[NSDate date] timeIntervalSince1970];
                    p.from = now - 24 * 3600;
                    p.to = now + 48 * 3600;
                    p.wantedIds = ids;
                    p.wantedNames = names;
                    NSXMLParser *xp = [[NSXMLParser alloc] initWithStream:[NSInputStream inputStreamWithFileAtPath:xml]];
                    xp.delegate = p;
                    [xp parse];
                    for (NSMutableArray *list in p.prog.allValues) {
                        [list sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
                    }
                    result = @{@"prog": p.prog, @"fetched": @(CBNowMs()), @"src": url};
                }
            }
            [[NSFileManager defaultManager] removeItemAtPath:xml error:NULL];
            if (result) CBWriteJSON(CBGuideFile(lid), result);
            dispatch_async(dispatch_get_main_queue(), ^{
                gGuideLoading = NO;
                gStatus = nil;
                if (result) {
                    gGuide = result;
                    gGuideList = lid;
                    CBLog(@"IPTV: lịch %@ — %lu kênh có lịch (tải %lld ms, đọc %lld ms, RAM %.0f MB)", url,
                          (unsigned long)CBDict(result, @"prog").count, t1 - t0, CBNowMs() - t1, CBResidentMB());
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:CBIPTVChangedNotification object:nil];
                if (done) done(result ? nil : @"Không đọc được tệp lịch phát sóng");
            });
        });
    });
}

+ (NSArray *)programmesFor:(NSDictionary *)channel {
    NSDictionary *prog = CBDict([self guide], @"prog");
    if (!prog.count) return @[];
    NSArray *raw = CBStr(channel, @"id") ? CBArr(prog, CBStr(channel, @"id")) : nil;
    if (!raw && CBStr(channel, @"k")) raw = CBArr(prog, [@"n:" stringByAppendingString:CBStr(channel, @"k")]);
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id p in raw) {
        if (CBIsArr(p) && [p count] >= 3) [out addObject:@{@"s": p[0], @"e": p[1], @"t": p[2]}];
    }
    return out;
}

+ (NSDictionary *)nowFor:(NSDictionary *)channel at:(NSTimeInterval)now {
    for (NSDictionary *p in [self programmesFor:channel]) {
        if (CBNum(p, @"s", 0) <= now && now < CBNum(p, @"e", 0)) return p;
    }
    return nil;
}

+ (NSDictionary *)nextFor:(NSDictionary *)channel at:(NSTimeInterval)now {
    for (NSDictionary *p in [self programmesFor:channel]) {
        if (CBNum(p, @"s", 0) > now) return p;
    }
    return nil;
}

#pragma mark - Nhóm

+ (NSArray *)groupsOf:(NSArray *)channels {
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *count = [NSMutableDictionary dictionary];
    for (NSDictionary *c in channels) {
        NSString *g = CBStr(c, @"g") ?: @"Khác";
        if (!count[g]) [order addObject:g];
        count[g] = @([count[g] integerValue] + 1);
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *g in order) [out addObject:@{@"name": g, @"count": count[g]}];
    return out;
}

+ (NSArray *)kidsFilter:(NSArray *)channels {
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"thieunhi|kid|child|cartoon|hoathinh|disney|nick|boomerang|baby|junior|anime"
                                                            options:0 error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in channels) {
        NSString *s = [NSString stringWithFormat:@"%@ %@", [self norm:CBStr(c, @"g") ?: @""], CBStr(c, @"k") ?: @""];
        if ([re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) [out addObject:c];
    }
    return out;
}

#pragma mark - Yêu thích / vừa xem / lỗi

+ (NSArray *)favoriteKeys {
    id v = [CBPrefs get:[CBPrefs k:@"iptv_favs"]];
    return CBIsArr(v) ? v : @[];
}

+ (BOOL)isFavorite:(NSDictionary *)channel {
    return CBStr(channel, @"k") && [[self favoriteKeys] containsObject:CBStr(channel, @"k")];
}

+ (void)setFavorite:(NSDictionary *)channel on:(BOOL)on {
    NSString *k = CBStr(channel, @"k");
    if (!k) return;
    NSMutableArray *f = [[self favoriteKeys] mutableCopy];
    [f removeObject:k];
    if (on) [f addObject:k];
    [CBPrefs set:[CBPrefs k:@"iptv_favs"] value:f];
}

+ (NSArray *)recent {
    id v = [CBPrefs get:[CBPrefs k:@"iptv_recent"]];
    return CBIsArr(v) ? v : @[];
}

+ (void)addRecent:(NSDictionary *)channel {
    NSString *k = CBStr(channel, @"k");
    if (!k || [CBPrefs privateMode]) return;
    NSMutableArray *r = [NSMutableArray array];
    NSMutableDictionary *item = [@{@"k": k, @"n": CBStr(channel, @"n") ?: k} mutableCopy];
    if (CBStr(channel, @"logo")) item[@"logo"] = CBStr(channel, @"logo");
    if (CBStr(channel, @"g")) item[@"g"] = CBStr(channel, @"g");
    [r addObject:item];
    for (NSDictionary *x in [self recent]) {
        if (![CBStr(x, @"k") isEqualToString:k] && r.count < 12) [r addObject:x];
    }
    [CBPrefs set:[CBPrefs k:@"iptv_recent"] value:r];
}

+ (NSDictionary *)channelForKey:(NSString *)key {
    for (NSDictionary *c in [self channels]) if ([CBStr(c, @"k") isEqualToString:key]) return c;
    return nil;
}

+ (NSDictionary *)badMap {
    id v = [CBPrefs get:@"iptv_bad"];
    if (!CBIsDict(v)) return @{};
    // Bản trước chưa phát được FLV / TS liền và đánh dấu hỏng cả nguồn — giờ lõi đổi FLV (0.5.3) và TS liền (0.5.5) sang HLS: bỏ
    // các dấu đó
    NSMutableDictionary *m = nil;
    for (NSString *k in v) {
        if ([CBStr(v, k) hasPrefix:@"Luồng FLV —"] || [CBStr(v, k) hasPrefix:@"Luồng TS liền —"]) {
            if (!m) m = [v mutableCopy];
            [m removeObjectForKey:k];
        }
    }
    if (m) {
        [CBPrefs set:@"iptv_bad" value:m];
        return m;
    }
    return v;
}

+ (NSString *)badReason:(NSString *)url {
    return url ? CBStr([self badMap], url) : nil;
}

+ (void)markBad:(NSString *)url reason:(NSString *)reason {
    if (!url) return;
    NSMutableDictionary *m = [[self badMap] mutableCopy];
    if (m.count > 500) [m removeAllObjects];
    m[url] = reason ?: @"Không phát được";
    [CBPrefs set:@"iptv_bad" value:m];
}

+ (void)clearBad {
    [CBPrefs remove:@"iptv_bad"];
}

+ (void)clearBadFor:(NSDictionary *)channel {
    NSMutableDictionary *m = [[self badMap] mutableCopy];
    for (NSString *u in CBArr(channel, @"urls") ?: @[]) [m removeObjectForKey:u];
    [CBPrefs set:@"iptv_bad" value:m];
}

+ (NSString *)channelBadReason:(NSDictionary *)channel {
    NSArray *urls = CBArr(channel, @"urls");
    if (!urls.count) return nil;
    NSDictionary *bad = [self badMap];
    for (NSString *u in urls) if (!bad[u]) return nil;
    return CBStr(bad, urls[0]);
}

#pragma mark - Cài đặt

/// Chỉ kênh mà mọi nguồn đều đã ghi «máy không giải mã được» (H.265, khổ quá lớn) — lỗi mạng thoáng qua không ghi
+ (BOOL)hideBad {
    id v = [CBPrefs get:@"iptv_hide_bad"];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES;
}

+ (void)setHideBad:(BOOL)on {
    [CBPrefs set:@"iptv_hide_bad" value:@(on)];
}

+ (BOOL)autoSource {
    id v = [CBPrefs get:@"iptv_auto_source"];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES;
}

+ (void)setAutoSource:(BOOL)on {
    [CBPrefs set:@"iptv_auto_source" value:@(on)];
}

#pragma mark - Phát / tiện ích

+ (NSString *)undecodableReason:(NSString *)m3u8 {
    if ([m3u8 rangeOfString:@"#EXT-X-STREAM-INF"].location != NSNotFound) {
        // Danh sách chính: mọi bản đều là H.265 / AV1 (CODECS) → không phát được
        NSUInteger total = 0, other = 0;
        NSString *codec = nil;
        for (NSString *l in [m3u8 componentsSeparatedByString:@"\n"]) {
            if (![l hasPrefix:@"#EXT-X-STREAM-INF"]) continue;
            total++;
            NSString *low = [l lowercaseString];
            if ([low rangeOfString:@"hvc1"].location != NSNotFound || [low rangeOfString:@"hev1"].location != NSNotFound ||
                [low rangeOfString:@"dvh1"].location != NSNotFound) {
                codec = @"H.265 (HEVC)";
            } else if ([low rangeOfString:@"av01"].location != NSNotFound) {
                codec = codec ?: @"AV1";
            } else {
                other++;
            }
        }
        if (total && !other && codec) return [NSString stringWithFormat:@"Video %@ — iOS 5 / 6 chỉ giải mã H.264.", codec];
        NSString *big = CBPlaylistUndecodable(m3u8);
        if (big) return [NSString stringWithFormat:@"Bản duy nhất khổ %@ — máy chỉ giải mã tới 1920×1080.", big];
    }
    return nil;
}

+ (NSString *)norm:(NSString *)name {
    if (!name.length) return @"";
    // Bỏ phần trong ngoặc: «An Ninh TV HD (1080p) [Geo-blocked]» → «An Ninh TV HD»
    static NSRegularExpression *brackets;
    if (!brackets) brackets = [NSRegularExpression regularExpressionWithPattern:@"\\([^)]*\\)|\\[[^\\]]*\\]" options:0 error:NULL];
    NSString *bare = [brackets stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0, name.length) withTemplate:@""];
    if ([bare stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) name = bare;
    NSMutableString *s = [[name lowercaseString] mutableCopy];
    [s replaceOccurrencesOfString:@"đ" withString:@"d" options:0 range:NSMakeRange(0, s.length)];
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformStripCombiningMarks, false);
    static NSRegularExpression *junk, *tail;
    if (!junk) junk = [NSRegularExpression regularExpressionWithPattern:@"[^a-z0-9]+" options:0 error:NULL];
    if (!tail) tail = [NSRegularExpression regularExpressionWithPattern:@"(uhd|fhd|hd|sd|4k|1080p|720p|backup)+$" options:0 error:NULL];
    NSString *t = [junk stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    NSString *u = [tail stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    return u.length ? u : t;
}

+ (NSString *)clock:(NSTimeInterval)t {
    static NSDateFormatter *f;
    if (!f) {
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm";
    }
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

#pragma mark - Trận đấu

+ (CBMatchState)matchState:(NSDictionary *)c at:(NSTimeInterval)now {
    double kick = CBNum(c, @"kick", 0);
    if (kick <= 0) return CBMatchNone;
    if (now < kick - kMatchEarly) return CBMatchLater;
    if (now < kick) return CBMatchSoon;
    if (now < kick + CBNum(c, @"dur", 150) * 60) return CBMatchLive;
    return CBMatchOver;
}

/// «20:00», «02:45 mai», «20:00 18/11» (giờ máy)
+ (NSString *)kickText:(NSTimeInterval)kick now:(NSTimeInterval)now {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *k = [NSDate dateWithTimeIntervalSince1970:kick], *n = [NSDate dateWithTimeIntervalSince1970:now];
    NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
    NSDateComponents *kc = [cal components:units fromDate:k], *nc = [cal components:units fromDate:n];
    NSDate *k0 = [cal dateFromComponents:kc], *n0 = [cal dateFromComponents:nc];
    NSInteger days = (NSInteger)lround([k0 timeIntervalSinceDate:n0] / 86400);
    NSString *clock = [self clock:kick];
    if (days == 0) return clock;
    if (days == 1) return [clock stringByAppendingString:@" mai"];
    if (days == -1) return [clock stringByAppendingString:@" hôm qua"];
    return [NSString stringWithFormat:@"%@ %ld/%ld", clock, (long)kc.day, (long)kc.month];
}

+ (NSString *)matchLine:(NSDictionary *)c at:(NSTimeInterval)now {
    double kick = CBNum(c, @"kick", 0);
    NSString *when = [self kickText:kick now:now];
    switch ([self matchState:c at:now]) {
        case CBMatchNone: return nil;
        case CBMatchLater: {
            long m = (long)ceil((kick - now) / 60);
            if (m >= 24 * 60) return [NSString stringWithFormat:@"Sắp đá %@", when];
            return m >= 60 ? [NSString stringWithFormat:@"Sắp đá %@ · còn %ld giờ %02ld phút", when, m / 60, m % 60]
                           : [NSString stringWithFormat:@"Sắp đá %@ · còn %ld phút", when, m];
        }
        case CBMatchSoon: return [NSString stringWithFormat:@"Sắp đá %@ · còn %ld phút", when, (long)MAX(1, ceil((kick - now) / 60))];
        case CBMatchLive:
            return CBNum(c, @"nolink", 0) ? @"● Đang đá · danh sách chưa có link" : [NSString stringWithFormat:@"● Đang đá · bóng lăn %@", when];
        case CBMatchOver: return [NSString stringWithFormat:@"Đã xong · đá lúc %@", when];
    }
    return nil;
}

+ (NSArray *)sortByMatch:(NSArray *)channels at:(NSTimeInterval)now {
    BOOL any = NO;
    for (NSDictionary *c in channels) if (CBNum(c, @"kick", 0) > 0) { any = YES; break; }
    if (!any) return channels;
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:channels.count];
    [channels enumerateObjectsUsingBlock:^(NSDictionary *c, NSUInteger i, BOOL *stop) {
        CBMatchState st = [self matchState:c at:now];
        // Đang đá (có link trước) → sắp đá (sớm trước) → kênh thường → đã xong (mới xong trước)
        NSInteger rank = st == CBMatchLive ? (CBNum(c, @"nolink", 0) ? 1 : 0)
                       : (st == CBMatchSoon || st == CBMatchLater ? 2 : (st == CBMatchNone ? 3 : 4));
        double kick = CBNum(c, @"kick", 0);
        [rows addObject:@[@(rank), @(rank == 4 ? -kick : kick), @(i), c]];
    }];
    [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSComparisonResult r = [a[0] compare:b[0]];
        if (r == NSOrderedSame) r = [a[1] compare:b[1]];
        if (r == NSOrderedSame) r = [a[2] compare:b[2]];
        return r;
    }];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *r in rows) [out addObject:r[3]];
    return out;
}

+ (UILocalNotification *)kickReminderFor:(NSDictionary *)c {
    NSString *k = CBStr(c, @"k");
    if (!k) return nil;
    for (UILocalNotification *n in [UIApplication sharedApplication].scheduledLocalNotifications) {
        if ([n.userInfo[@"iptv"] isEqualToString:k] && n.userInfo[@"kick"]) return n;
    }
    return nil;
}

+ (BOOL)hasKickReminder:(NSDictionary *)channel {
    return [self kickReminderFor:channel] != nil;
}

+ (BOOL)toggleKickReminder:(NSDictionary *)c {
    UILocalNotification *old = [self kickReminderFor:c];
    if (old) {
        [[UIApplication sharedApplication] cancelLocalNotification:old];
        CBLog(@"Truyền hình: bỏ nhắc %@", CBStr(c, @"n"));
        return NO;
    }
    double kick = CBNum(c, @"kick", 0), now = [[NSDate date] timeIntervalSince1970];
    if (kick <= now) return NO;
    UILocalNotification *n = [[UILocalNotification alloc] init];
    n.fireDate = [NSDate dateWithTimeIntervalSince1970:kick];
    n.timeZone = [NSTimeZone defaultTimeZone];
    n.alertBody = [NSString stringWithFormat:@"Bóng lăn: %@ — %@", CBStr(c, @"n"), CBStr(c, @"g") ?: @"Truyền hình"];
    n.alertAction = @"Xem";
    n.soundName = UILocalNotificationDefaultSoundName;
    n.userInfo = @{@"iptv": CBStr(c, @"k"), @"kick": @(kick), @"title": @"Bóng lăn"};
    [[UIApplication sharedApplication] scheduleLocalNotification:n];
    CBLog(@"Truyền hình: nhắc lúc bóng lăn %@ (%@)", CBStr(c, @"n"), [self clock:kick]);
    return YES;
}

+ (BOOL)isRadio:(NSDictionary *)channel {
    return CBNum(channel, @"radio", 0) != 0;
}

+ (BOOL)isPlaceholderURL:(NSString *)url {
    return url && CBIsPlaceholder(url);
}

+ (BOOL)isPlaceholderPlaylist:(NSString *)m3u8 {
    if ([m3u8 rangeOfString:@"#EXT-X-ENDLIST"].location == NSNotFound || [m3u8 rangeOfString:@"#EXT-X-STREAM-INF"].location != NSNotFound) {
        return NO;
    }
    double total = 0;
    for (NSString *l in [m3u8 componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([l hasPrefix:@"#EXTINF:"]) total += [[l substringFromIndex:8] doubleValue];
    }
    return total < 120;
}

+ (void)refreshIfOlderThan:(double)seconds done:(void (^)(NSString *))done {
    BOOL old = CBNowMs() - (long long)CBNum([self activeList], @"updated", 0) > (long long)(seconds * 1000);
    if (old || gLoading) [self refresh:old done:done];
    else if (done) done(nil);
}

/// Referer / User-Agent của một nguồn (nguồn gộp vào từ dòng khác của danh sách có thể ghi khác kênh)
+ (NSDictionary *)headersFor:(NSDictionary *)c url:(NSString *)url {
    NSDictionary *h = CBDict(CBDict(c, @"hdr"), url);
    NSString *ref = h ? CBStr(h, @"ref") : CBStr(c, @"ref"), *ua = h ? CBStr(h, @"ua") : CBStr(c, @"ua");
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (ref.length) out[@"referer"] = ref;
    if (ua.length) out[@"ua"] = ua;
    return out;
}

@end
