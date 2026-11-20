#import "CBIcon.h"

/// Mỗi biểu tượng: danh sách phần vẽ (khung 24 × 24). Tiền tố của phần:
///   S:<đường SVG>          nét          F:<đường SVG>        tô kín
///   C:cx,cy,r              vòng tròn    c:cx,cy,r            chấm tròn tô kín
///   R:x,y,w,h,bo           khung        r:x,y,w,h,bo         khối tô kín
///   T:chữ,x,y,cỡ           chữ đậm canh giữa tại (x, đường chân chữ y)
///   W:độ dày               độ dày nét cho các phần sau (mặc định 2)
/// Dấu * trước tiền tố: khi filled = YES thì tô kín phần đó thay vì vẽ nét (biểu tượng tab đang chọn).
static NSDictionary *CBIconTable(void) {
    static NSDictionary *t;
    if (t) return t;
    NSString *gear = @"S:M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z";
    t = @{
        @"home": @[@"W:1.9", @"*S:M3.5 10.2 12 3.5l8.5 6.7V19a1.5 1.5 0 0 1-1.5 1.5h-4.2v-5.8H9.2v5.8H5A1.5 1.5 0 0 1 3.5 19z"],
        @"tv": @[@"W:1.9", @"*R:2.5,4.5,19,13,2.5", @"S:M8 21h8"],
        @"bookmark": @[@"W:1.9", @"*S:M6.5 3.5h11a1 1 0 0 1 1 1v16l-6.5-4.2-6.5 4.2v-16a1 1 0 0 1 1-1z"],
        @"gear": @[@"W:1.9", @"C:12,12,3", gear],
        @"search": @[@"W:2.3", @"C:10.8,10.8,6.8", @"S:m20 20-4.3-4.3"],
        @"back": @[@"W:2.6", @"S:M15 18l-6-6 6-6"],
        @"forward": @[@"W:2.6", @"S:m9 18 6-6-6-6"],
        @"down": @[@"W:2.5", @"S:m6 9 6 6 6-6"],
        @"up": @[@"W:2.5", @"S:m6 15 6-6 6 6"],
        @"more": @[@"c:5,12,2", @"c:12,12,2", @"c:19,12,2"],
        @"play": @[@"F:M7 4.2v15.6c0 .8.9 1.3 1.6.9l12.2-7.8a1 1 0 0 0 0-1.7L8.6 3.3C7.9 2.9 7 3.4 7 4.2z"],
        @"pause": @[@"r:5.5,4,4.6,16,1.4", @"r:13.9,4,4.6,16,1.4"],
        @"close": @[@"W:2.6", @"S:M6 6l12 12M18 6 6 18"],
        @"list": @[@"W:2.4", @"S:M8.5 6h12M8.5 12h12M8.5 18h12M3.8 6h.01M3.8 12h.01M3.8 18h.01"],
        @"float": @[@"W:2", @"R:2.5,4.5,19,15,2.5", @"r:11.5,11,7.5,6,1.2"],
        @"back10": @[@"W:1.9", @"S:M3.5 12a8.5 8.5 0 1 0 2.8-6.3L3.5 8", @"S:M3.5 3.5V8H8", @"T:10,12.3,15.6,7.2"],
        @"fwd10": @[@"W:1.9", @"S:M20.5 12a8.5 8.5 0 1 1-2.8-6.3L20.5 8", @"S:M20.5 3.5V8H16", @"T:10,11.7,15.6,7.2"],
        @"swap": @[@"W:2.2", @"S:M4 8h15l-4-4M20 16H5l4 4"],
        @"star": @[@"W:1.9", @"*S:m12 2.8 2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.6l-5.8 3.1 1.1-6.5-4.7-4.6 6.5-.9z"],
        @"plus": @[@"W:2.4", @"S:M12 5v14M5 12h14"],
        @"sliders": @[@"W:2.1", @"S:M4 7h10M18 7h2M4 17h4M12 17h8", @"C:16,7,2.2", @"C:10,17,2.2"],
        @"lock": @[@"W:2.2", @"R:5,11,14,10,2", @"S:M8 11V7.5a4 4 0 0 1 8 0V11"],
        @"clock": @[@"W:2.2", @"C:12,12,8.5", @"S:M12 7.5V12l3 2"],
        @"grid": @[@"W:2.2", @"R:3.5,3.5,7,7,1.5", @"R:13.5,3.5,7,7,1.5", @"R:3.5,13.5,7,7,1.5", @"R:13.5,13.5,7,7,1.5"],
        @"smile": @[@"W:2.2", @"C:12,12,8.5", @"S:M8.5 14.2a4 4 0 0 0 7 0M9.2 9.6h.01M14.8 9.6h.01"],
        @"gauge": @[@"W:2.2", @"S:M3.5 17.5a8.5 8.5 0 1 1 17 0", @"S:m12 14 4-4.5"],
        @"next": @[@"F:M5 5.3v13.4c0 .8.9 1.3 1.5.8l9-6.7a1 1 0 0 0 0-1.6l-9-6.7C5.9 4 5 4.5 5 5.3z", @"r:17,4.5,2.6,15,1"],
        @"prev": @[@"F:M19 5.3v13.4c0 .8-.9 1.3-1.5.8l-9-6.7a1 1 0 0 1 0-1.6l9-6.7c.6-.5 1.5 0 1.5.8z", @"r:4.4,4.5,2.6,15,1"],
        @"people": @[@"W:2.2", @"C:9,8,3.5", @"S:M2.5 20a6.5 6.5 0 0 1 13 0", @"S:M16 4.5a3.5 3.5 0 0 1 0 7M18.5 20a6.5 6.5 0 0 0-2.6-5.2"],
        @"person": @[@"W:2.1", @"C:12,8,4", @"S:M4 21a8 8 0 0 1 16 0"],
        @"trash": @[@"W:2.1", @"S:M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"],
        @"info": @[@"W:2.1", @"C:12,12,8.5", @"S:M12 11v5.5M12 7.6h.01"],
        @"captions": @[@"W:2.1", @"R:3,5,18,14,2.5", @"S:M10.5 10a2.2 2.2 0 1 0 0 4M17 10a2.2 2.2 0 1 0 0 4"],
        @"moon": @[@"W:2.1", @"S:M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"],
        @"reload": @[@"W:2.1", @"S:M20 12a8 8 0 1 1-2.3-5.7L20 8.5", @"S:M20 4v4.5h-4.5"],
        @"skip": @[@"F:M3.5 6.4v11.2c0 .8.9 1.2 1.5.8l7-5.6a1 1 0 0 0 0-1.6l-7-5.6c-.6-.4-1.5 0-1.5.8zM12.5 6.4v11.2c0 .8.9 1.2 1.5.8l7-5.6a1 1 0 0 0 0-1.6l-7-5.6c-.6-.4-1.5 0-1.5.8z"],
        @"expand": @[@"W:2.6", @"S:M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"],
        @"check": @[@"W:2.6", @"S:M5 12.5l4.5 4.5L19 7.5"],
        @"radio": @[@"W:2", @"R:3,8,18,12,2.5", @"C:15.5,14,2.5", @"S:M7 12h3M7 16h3M6 8l11-4.5"],
        @"globe": @[@"W:2", @"C:12,12,8.5", @"S:M3.5 12h17M12 3.5c2.5 2.3 3.6 5.2 3.6 8.5s-1.1 6.2-3.6 8.5c-2.5-2.3-3.6-5.2-3.6-8.5s1.1-6.2 3.6-8.5z"],
        @"shield": @[@"W:2.1", @"S:M12 3 5 6v6c0 4.5 3 7.7 7 9 4-1.3 7-4.5 7-9V6z"],
        @"sync": @[@"W:2.1", @"S:M20 11a8 8 0 0 0-14.3-4.9L4 8M4 4v4h4M4 13a8 8 0 0 0 14.3 4.9L20 16M20 20v-4h-4"],
        @"eyeoff": @[@"W:2.1", @"S:M3 3l18 18M10.6 6.1A9.8 9.8 0 0 1 12 6c5 0 9 6 9 6a17 17 0 0 1-2.7 3.3M6.6 6.6C4.3 8.1 3 12 3 12s4 6 9 6a9.4 9.4 0 0 0 4.4-1.1"],
        @"speaker": @[@"W:2.1", @"S:M4 9.5h3.5L12 5.5v13l-4.5-4H4z", @"S:M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"],
        @"calendar": @[@"W:2.1", @"R:3.5,5,17,15.5,2.5", @"S:M3.5 10h17M8 3v4M16 3v4"],
        @"pencil": @[@"W:2.1", @"S:M4 20h4L19 9l-4-4L4 16z"],
        @"wifi": @[@"W:2.2", @"S:M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0M12 19.5h.01"],
        @"doc": @[@"W:2", @"S:M6 3h8l4 4v14H6z", @"S:M14 3v4h4"],
        @"link": @[@"W:2.1", @"S:M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"],
        @"bell": @[@"W:2", @"*S:M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z", @"S:M10 20.5a2 2 0 0 0 4 0"],
        @"server": @[@"W:2", @"R:4,4,16,7,2", @"R:4,13,16,7,2", @"S:M8 7.5h.01M8 16.5h.01"],
        @"photo": @[@"W:2", @"R:3,5,18,14,2.5", @"C:8.5,10,1.8", @"S:M21 16l-5-5-8 8"],
        @"history": @[@"W:2.1", @"S:M3.5 12a8.5 8.5 0 1 0 2.5-6L3.5 8.5", @"S:M3.5 4v4.5H8", @"S:M12 8v4.5l3 2"],
        @"send": @[@"W:2", @"S:M21 3 10 14M21 3l-7 18-4-7-7-4z"],
        @"download": @[@"W:2.2", @"S:M12 3v12M7 10l5 5 5-5M5 21h14"],
        @"keypad": @[@"c:6,5,1.6", @"c:12,5,1.6", @"c:18,5,1.6", @"c:6,11,1.6", @"c:12,11,1.6", @"c:18,11,1.6", @"c:6,17,1.6", @"c:12,17,1.6", @"c:18,17,1.6", @"c:12,22,1.6"],
    };
    return t;
}

#pragma mark - Đọc đường vẽ SVG

typedef struct {
    const char *s;
    size_t i, n;
} CBScan;

static void CBSkip(CBScan *sc) {
    while (sc->i < sc->n && (sc->s[sc->i] == ' ' || sc->s[sc->i] == ',' || sc->s[sc->i] == '\n' || sc->s[sc->i] == '\t')) sc->i++;
}

/// Còn số ở trước không (sau dấu cách / phẩy)
static BOOL CBHasNumber(CBScan *sc) {
    CBSkip(sc);
    if (sc->i >= sc->n) return NO;
    char c = sc->s[sc->i];
    return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.';
}

static CGFloat CBNumber(CBScan *sc) {
    CBSkip(sc);
    size_t start = sc->i;
    if (sc->i < sc->n && (sc->s[sc->i] == '-' || sc->s[sc->i] == '+')) sc->i++;
    BOOL dot = NO;
    while (sc->i < sc->n) {
        char c = sc->s[sc->i];
        if (c >= '0' && c <= '9') sc->i++;
        else if (c == '.' && !dot) { dot = YES; sc->i++; }
        else break;
    }
    if (sc->i < sc->n && (sc->s[sc->i] == 'e' || sc->s[sc->i] == 'E')) {
        sc->i++;
        if (sc->i < sc->n && (sc->s[sc->i] == '-' || sc->s[sc->i] == '+')) sc->i++;
        while (sc->i < sc->n && sc->s[sc->i] >= '0' && sc->s[sc->i] <= '9') sc->i++;
    }
    char buf[32];
    size_t len = MIN(sc->i - start, sizeof(buf) - 1);
    memcpy(buf, sc->s + start, len);
    buf[len] = 0;
    return (CGFloat)strtod(buf, NULL);
}

/// Cờ của lệnh cung (một ký tự 0 / 1, có thể dính liền nhau: «a1 1 0 011 2»)
static BOOL CBFlag(CBScan *sc) {
    CBSkip(sc);
    if (sc->i >= sc->n) return NO;
    return sc->s[sc->i++] == '1';
}

static CGFloat CBAngle(CGFloat ux, CGFloat uy, CGFloat vx, CGFloat vy) {
    CGFloat a = atan2(vy, vx) - atan2(uy, ux);
    return a;
}

/// Cung SVG (điểm đầu → điểm cuối) → tâm + góc (SVG 1.1, phụ lục F.6.5)
static void CBAddArc(CGMutablePathRef p, CGPoint from, CGFloat rx, CGFloat ry, CGFloat rotDeg, BOOL large, BOOL sweep, CGPoint to) {
    if (CGPointEqualToPoint(from, to)) return;
    rx = fabs(rx); ry = fabs(ry);
    if (rx < 1e-6 || ry < 1e-6) { CGPathAddLineToPoint(p, NULL, to.x, to.y); return; }
    CGFloat phi = rotDeg * M_PI / 180, cp = cos(phi), sp = sin(phi);
    CGFloat dx = (from.x - to.x) / 2, dy = (from.y - to.y) / 2;
    CGFloat x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy;
    CGFloat lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry);
    if (lam > 1) { CGFloat s = sqrt(lam); rx *= s; ry *= s; }
    CGFloat num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
    CGFloat den = rx * rx * y1 * y1 + ry * ry * x1 * x1;
    CGFloat coef = (large != sweep ? 1 : -1) * sqrt(MAX(0, num / den));
    CGFloat cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx;
    CGFloat cx = cp * cxp - sp * cyp + (from.x + to.x) / 2, cy = sp * cxp + cp * cyp + (from.y + to.y) / 2;
    CGFloat ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry, vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry;
    CGFloat t1 = CBAngle(1, 0, ux, uy), dt = CBAngle(ux, uy, vx, vy);
    while (dt > M_PI) dt -= 2 * M_PI;
    while (dt < -M_PI) dt += 2 * M_PI;
    // cờ cung lớn đã quyết tâm ở trên (dấu coef); chiều đi theo cờ sweep là ra đúng cung
    if (sweep && dt < 0) dt += 2 * M_PI;
    if (!sweep && dt > 0) dt -= 2 * M_PI;
    CGAffineTransform t = CGAffineTransformMakeTranslation(cx, cy);
    t = CGAffineTransformRotate(t, phi);
    t = CGAffineTransformScale(t, rx, ry);
    // clockwise = NO: góc tăng dần (trên toạ độ y hướng xuống là đi theo chiều kim đồng hồ — đúng sweep = 1 của SVG)
    CGPathAddArc(p, &t, 0, 0, 1, t1, t1 + dt, dt < 0);
}

@implementation CBIcon

+ (CGPathRef)newPathFromSVG:(NSString *)d {
    CGMutablePathRef p = CGPathCreateMutable();
    const char *s = d.UTF8String;
    CBScan sc = {s, 0, strlen(s)};
    char cmd = 0;
    CGPoint cur = CGPointZero, start = CGPointZero, ctrl = CGPointZero;
    char last = 0;
    while (1) {
        CBSkip(&sc);
        if (sc.i >= sc.n) break;
        char c = sc.s[sc.i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            cmd = c;
            sc.i++;
        } else if (!cmd) {
            break;
        }
        BOOL rel = cmd >= 'a';
        char up = rel ? cmd - 32 : cmd;
        CGFloat ox = rel ? cur.x : 0, oy = rel ? cur.y : 0;
        switch (up) {
            case 'M': {
                CGFloat x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathMoveToPoint(p, NULL, x, y);
                cur = start = CGPointMake(x, y);
                cmd = rel ? 'l' : 'L';   // cặp số tiếp theo là lệnh L
                break;
            }
            case 'L': {
                CGFloat x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathAddLineToPoint(p, NULL, x, y);
                cur = CGPointMake(x, y);
                break;
            }
            case 'H': {
                CGFloat x = CBNumber(&sc) + ox;
                CGPathAddLineToPoint(p, NULL, x, cur.y);
                cur.x = x;
                break;
            }
            case 'V': {
                CGFloat y = CBNumber(&sc) + oy;
                CGPathAddLineToPoint(p, NULL, cur.x, y);
                cur.y = y;
                break;
            }
            case 'C': {
                CGFloat x1 = CBNumber(&sc) + ox, y1 = CBNumber(&sc) + oy, x2 = CBNumber(&sc) + ox, y2 = CBNumber(&sc) + oy;
                CGFloat x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathAddCurveToPoint(p, NULL, x1, y1, x2, y2, x, y);
                ctrl = CGPointMake(x2, y2);
                cur = CGPointMake(x, y);
                break;
            }
            case 'S': {
                CGPoint r = (last == 'C' || last == 'S') ? CGPointMake(2 * cur.x - ctrl.x, 2 * cur.y - ctrl.y) : cur;
                CGFloat x2 = CBNumber(&sc) + ox, y2 = CBNumber(&sc) + oy, x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathAddCurveToPoint(p, NULL, r.x, r.y, x2, y2, x, y);
                ctrl = CGPointMake(x2, y2);
                cur = CGPointMake(x, y);
                break;
            }
            case 'Q': {
                CGFloat x1 = CBNumber(&sc) + ox, y1 = CBNumber(&sc) + oy, x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathAddQuadCurveToPoint(p, NULL, x1, y1, x, y);
                ctrl = CGPointMake(x1, y1);
                cur = CGPointMake(x, y);
                break;
            }
            case 'T': {
                CGPoint r = (last == 'Q' || last == 'T') ? CGPointMake(2 * cur.x - ctrl.x, 2 * cur.y - ctrl.y) : cur;
                CGFloat x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CGPathAddQuadCurveToPoint(p, NULL, r.x, r.y, x, y);
                ctrl = r;
                cur = CGPointMake(x, y);
                break;
            }
            case 'A': {
                CGFloat rx = CBNumber(&sc), ry = CBNumber(&sc), rot = CBNumber(&sc);
                BOOL large = CBFlag(&sc), sweep = CBFlag(&sc);
                CGFloat x = CBNumber(&sc) + ox, y = CBNumber(&sc) + oy;
                CBAddArc(p, cur, rx, ry, rot, large, sweep, CGPointMake(x, y));
                cur = CGPointMake(x, y);
                break;
            }
            case 'Z':
                CGPathCloseSubpath(p);
                cur = start;
                break;
            default:
                CGPathRelease(p);
                return CGPathCreateMutable();
        }
        last = up;
        if (up == 'Z' && !CBHasNumber(&sc)) cmd = 0;
    }
    return p;
}

+ (UIImage *)named:(NSString *)name size:(CGFloat)size color:(UIColor *)color {
    return [self named:name size:size color:color filled:NO];
}

+ (UIImage *)named:(NSString *)name size:(CGFloat)size color:(UIColor *)color filled:(BOOL)filled {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSArray *parts = CBIconTable()[name];
    // «back5» / «fwd30»…: vòng tua có số giây (bước tua đặt trong Cài đặt) — lấy hình back10 / fwd10, thay chữ số
    if (!parts && ([name hasPrefix:@"back"] || [name hasPrefix:@"fwd"])) {
        BOOL back = [name hasPrefix:@"back"];
        NSString *n = [name substringFromIndex:back ? 4 : 3];
        if (n.length && n.integerValue > 0) {
            NSMutableArray *m = [CBIconTable()[back ? @"back10" : @"fwd10"] mutableCopy];
            NSString *t = m.lastObject;
            m[m.count - 1] = [t stringByReplacingOccurrencesOfString:@"T:10," withString:[NSString stringWithFormat:@"T:%@,", n]];
            parts = m;
        }
    }
    if (!parts || size <= 0) return nil;
    color = color ?: [UIColor whiteColor];
    CGFloat r = 1, g = 1, b = 1, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a] && [color getWhite:&r alpha:&a]) g = b = r;
    NSString *key = [NSString stringWithFormat:@"%@ %.1f %.3f %.3f %.3f %.3f %d", name, size, r, g, b, a, filled];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(ctx, size / 24.0, size / 24.0);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    [color setStroke];
    [color setFill];
    CGFloat width = 2;
    for (NSString *raw in parts) {
        NSString *part = raw;
        BOOL fillable = [part hasPrefix:@"*"];
        if (fillable) part = [part substringFromIndex:1];
        if (part.length < 2) continue;
        unichar kind = [part characterAtIndex:0];
        NSString *body = [part substringFromIndex:2];
        BOOL fill = (kind == 'F' || kind == 'c' || kind == 'r') || (fillable && filled);
        CGPathRef path = NULL;
        if (kind == 'W') {
            width = body.doubleValue;
            continue;
        } else if (kind == 'T') {
            NSArray *f = [body componentsSeparatedByString:@","];
            if (f.count < 4) continue;
            UIFont *font = [UIFont boldSystemFontOfSize:[f[3] doubleValue]];
            CGSize ts = [f[0] sizeWithFont:font];
            [f[0] drawAtPoint:CGPointMake([f[1] doubleValue] - ts.width / 2, [f[2] doubleValue] - font.ascender) withFont:font];
            continue;
        } else if (kind == 'S' || kind == 'F') {
            path = [self newPathFromSVG:body];
        } else if (kind == 'C' || kind == 'c') {
            NSArray *f = [body componentsSeparatedByString:@","];
            if (f.count < 3) continue;
            CGFloat cx = [f[0] doubleValue], cy = [f[1] doubleValue], rr = [f[2] doubleValue];
            path = CGPathCreateWithEllipseInRect(CGRectMake(cx - rr, cy - rr, rr * 2, rr * 2), NULL);
        } else if (kind == 'R' || kind == 'r') {
            NSArray *f = [body componentsSeparatedByString:@","];
            if (f.count < 5) continue;
            CGRect rc = CGRectMake([f[0] doubleValue], [f[1] doubleValue], [f[2] doubleValue], [f[3] doubleValue]);
            path = CGPathRetain([UIBezierPath bezierPathWithRoundedRect:rc cornerRadius:[f[4] doubleValue]].CGPath);
        }
        if (!path) continue;
        CGContextAddPath(ctx, path);
        if (fill) {
            CGContextFillPath(ctx);
        } else {
            CGContextSetLineWidth(ctx, width);
            CGContextStrokePath(ctx);
        }
        CGPathRelease(path);
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) [cache setObject:img forKey:key];
    return img;
}

@end
