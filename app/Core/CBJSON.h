// Đọc an toàn dữ liệu JSON của lõi (NSDictionary / NSArray từ NSJSONSerialization): sai kiểu → nil / giá trị mặc định.
#import <Foundation/Foundation.h>

static inline BOOL CBIsDict(id x) { return [x isKindOfClass:[NSDictionary class]]; }
static inline BOOL CBIsArr(id x) { return [x isKindOfClass:[NSArray class]]; }
static inline BOOL CBIsStr(id x) { return [x isKindOfClass:[NSString class]]; }

static inline id CBVal(id d, NSString *k) { return CBIsDict(d) ? [(NSDictionary *)d objectForKey:k] : nil; }
static inline NSDictionary *CBDict(id d, NSString *k) { id v = CBVal(d, k); return CBIsDict(v) ? v : nil; }
static inline NSArray *CBArr(id d, NSString *k) { id v = CBVal(d, k); return CBIsArr(v) ? v : nil; }
/// Chuỗi (rỗng / sai kiểu → nil)
static inline NSString *CBStr(id d, NSString *k) {
    id v = CBVal(d, k);
    return CBIsStr(v) && [(NSString *)v length] ? v : nil;
}
static inline double CBNum(id d, NSString *k, double def) {
    id v = CBVal(d, k);
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : def;
}
static inline BOOL CBBool(id d, NSString *k, BOOL def) {
    id v = CBVal(d, k);
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}
