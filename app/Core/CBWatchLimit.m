#import "CBWatchLimit.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"

/// Hết giờ đi ngủ lúc 6:00 sáng
static const NSInteger kMorning = 6 * 60;

/// Giây xem chưa ghi xuống (ghi mỗi 30 giây và khi rời trình phát)
static double gPending;
static long long gLastTick;

static NSInteger CBInt(id v, NSInteger def) {
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
}

@implementation CBWatchLimit

+ (NSArray *)dailyChoices { return @[@0, @30, @45, @60, @90, @120, @180]; }
+ (NSArray *)bedtimeChoices { return @[@-1, @(19 * 60 + 30), @(20 * 60), @(20 * 60 + 30), @(21 * 60), @(21 * 60 + 30), @(22 * 60), @(23 * 60)]; }
+ (NSArray *)grantChoices { return @[@15, @30, @60]; }

#pragma mark - Cài đặt (riêng từng người xem)

+ (NSInteger)dailyLimitFor:(NSString *)pid {
    return CBInt([CBPrefs get:[CBPrefs pk:pid key:@"limit_min"]], 0);
}

+ (void)setDailyLimit:(NSInteger)minutes for:(NSString *)pid {
    [CBPrefs set:[CBPrefs pk:pid key:@"limit_min"] value:@(minutes)];
}

+ (NSInteger)bedtimeFor:(NSString *)pid {
    return CBInt([CBPrefs get:[CBPrefs pk:pid key:@"bedtime"]], -1);
}

+ (void)setBedtime:(NSInteger)minute for:(NSString *)pid {
    [CBPrefs set:[CBPrefs pk:pid key:@"bedtime"] value:@(minute)];
}

+ (BOOL)anyLimits {
    for (NSDictionary *p in [CBPrefs profiles]) {
        NSString *pid = CBStr(p, @"id") ?: @"";
        if ([self dailyLimitFor:pid] > 0 || [self bedtimeFor:pid] >= 0) return YES;
    }
    return NO;
}

#pragma mark - Đếm của người đang xem (watch_day / watch_sec / watch_extra / unblock_until)

+ (NSString *)watchDay { id v = [CBPrefs get:[CBPrefs k:@"watch_day"]]; return CBIsStr(v) ? v : @""; }
+ (NSInteger)watchSeconds { return CBInt([CBPrefs get:[CBPrefs k:@"watch_sec"]], 0); }
+ (NSInteger)watchExtra { return CBInt([CBPrefs get:[CBPrefs k:@"watch_extra"]], 0); }
+ (long long)unblockUntil {
    id v = [CBPrefs get:[CBPrefs k:@"unblock_until"]];
    return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : 0;
}

+ (NSString *)dayOf:(NSDate *)d {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd";
    return [f stringFromDate:d];
}

+ (NSInteger)minuteOfDay:(NSDate *)d {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:d];
    return c.hour * 60 + c.minute;
}

+ (NSInteger)usedToday {
    return ([[self watchDay] isEqualToString:[self dayOf:[NSDate date]]] ? [self watchSeconds] : 0) + (NSInteger)gPending;
}

+ (NSInteger)remaining {
    NSInteger limit = [self dailyLimitFor:[CBPrefs profileId]];
    if (limit <= 0) return NSNotFound;
    NSInteger extra = [[self watchDay] isEqualToString:[self dayOf:[NSDate date]]] ? [self watchExtra] : 0;
    return (limit + extra) * 60 - [self usedToday];
}

+ (CBLimitBlock)blocked {
    if (CBNowMs() < [self unblockUntil]) return CBLimitNone;
    NSInteger bed = [self bedtimeFor:[CBPrefs profileId]];
    if (bed >= 0) {
        NSInteger m = [self minuteOfDay:[NSDate date]];
        if (m >= bed || m < kMorning) return CBLimitBedtime;
    }
    NSInteger r = [self remaining];
    return r != NSNotFound && r <= 0 ? CBLimitDaily : CBLimitNone;
}

+ (void)tick:(BOOL)playing {
    long long now = CBNowMs();
    double dt = (now - gLastTick) / 1000.0;
    gLastTick = now;
    if (!playing || dt <= 0 || dt > 3) return;
    gPending += dt;
    if (gPending >= 30) [self flush];
}

+ (void)flush {
    NSString *d = [self dayOf:[NSDate date]];
    if (![[self watchDay] isEqualToString:d]) {
        [CBPrefs set:[CBPrefs k:@"watch_day"] value:d];
        [CBPrefs set:[CBPrefs k:@"watch_sec"] value:@0];
        [CBPrefs set:[CBPrefs k:@"watch_extra"] value:@0];
    }
    NSInteger whole = (NSInteger)gPending;
    if (whole > 0) [CBPrefs set:[CBPrefs k:@"watch_sec"] value:@([self watchSeconds] + whole)];
    gPending -= whole;
}

+ (void)reset {
    gPending = 0;
    gLastTick = 0;
}

+ (void)grant:(NSInteger)minutes {
    [self flush];
    if ([self blocked] == CBLimitBedtime) {
        [CBPrefs set:[CBPrefs k:@"unblock_until"] value:@(CBNowMs() + minutes * 60000LL)];
    } else {
        [CBPrefs set:[CBPrefs k:@"watch_extra"] value:@([self watchExtra] + minutes)];
    }
    CBLog(@"Cho xem thêm %ld phút", (long)minutes);
}

+ (void)grantUntilMorning {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    c.hour = kMorning / 60;
    NSDate *six = [cal dateFromComponents:c];
    if ([six compare:now] != NSOrderedDescending) six = [six dateByAddingTimeInterval:24 * 3600];
    [CBPrefs set:[CBPrefs k:@"unblock_until"] value:@((long long)([six timeIntervalSince1970] * 1000))];
    CBLog(@"Cho xem tới 6 giờ sáng");
}

#pragma mark - Chữ

+ (NSString *)dailyLabel:(NSInteger)minutes {
    if (minutes <= 0) return @"Không giới hạn";
    if (minutes < 60) return [NSString stringWithFormat:@"%ld phút", (long)minutes];
    if (minutes % 60 == 0) return [NSString stringWithFormat:@"%ld giờ", (long)(minutes / 60)];
    return [NSString stringWithFormat:@"%ld giờ %ld phút", (long)(minutes / 60), (long)(minutes % 60)];
}

+ (NSString *)bedtimeLabel:(NSInteger)minute {
    return minute < 0 ? @"Không" : [NSString stringWithFormat:@"%ld:%02ld", (long)(minute / 60), (long)(minute % 60)];
}

+ (NSString *)minutesText:(NSInteger)seconds {
    return [self dailyLabel:MAX(1, (seconds + 59) / 60)];
}

+ (NSString *)summaryFor:(NSString *)pid {
    NSMutableArray *parts = [NSMutableArray array];
    NSInteger d = [self dailyLimitFor:pid], b = [self bedtimeFor:pid];
    if (d > 0) [parts addObject:[[self dailyLabel:d] stringByAppendingString:@"/ngày"]];
    if (b >= 0) [parts addObject:[@"ngủ lúc " stringByAppendingString:[self bedtimeLabel:b]]];
    return parts.count ? [parts componentsJoinedByString:@", "] : @"không giới hạn";
}

+ (NSString *)reason:(CBLimitBlock)block {
    NSString *who = CBStr([CBPrefs currentProfile], @"name") ?: @"Người xem";
    if (block == CBLimitBedtime) {
        return [NSString stringWithFormat:@"Đã tới giờ đi ngủ của %@ (từ %@ tới 6 giờ sáng).", who,
                                          [self bedtimeLabel:[self bedtimeFor:[CBPrefs profileId]]]];
    }
    return [NSString stringWithFormat:@"%@ đã xem hết %@ của hôm nay.", who, [self dailyLabel:[self dailyLimitFor:[CBPrefs profileId]]]];
}

@end
