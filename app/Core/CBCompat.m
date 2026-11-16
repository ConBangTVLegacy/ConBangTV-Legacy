// Bù phần iOS 6 mà app dùng khi chạy trên iOS 5. Thêm lúc nạp app (+load, trước main), chỉ khi iOS thiếu — trên iOS 6 giữ
// nguyên hàm gốc của hệ thống.
//   • a[i] / d[k] (Objective-C subscripting): clang gọi objectAtIndexedSubscript: / objectForKeyedSubscript:… — có từ iOS 6;
//     Xcode thêm libarclite để bù khi dựng cho iOS 5, bộ dựng Theos trên Linux không có → tự bù ở đây.
//   • NSIndexPath item / indexPathForItem:inSection: (UIKit iOS 6) = row / indexPathForRow:inSection:.
//   • UILabel minimumScaleFactor (iOS 6) → minimumFontSize của iOS 5.
//   • AVPlayerItem canPlaySlowForward (iOS 6) → NO.
//   • Xoay màn hình: iOS 5 hỏi shouldAutorotateToInterfaceOrientation:, iOS 6 hỏi supportedInterfaceOrientations — màn nào
//     khai báo supportedInterfaceOrientations thì iOS 5 cũng theo đúng mặt nạ đó. Riêng màn trình bày đè lên (modal: trình phát, «Ai đang
//     xem?», miễn trừ) iOS 5 không theo hàm thay chung này — các màn đó tự khai báo shouldAutorotateToInterfaceOrientation:
//     (0.5.0 trên iPad 1: trình phát bị kéo về dọc); thanh điều hướng cũng tự khai báo (CBNavController).
//   • Thiếu bộ nhớ: iOS 5 gỡ view của các màn đang khuất (viewDidUnload) rồi dựng lại khi quay về — các màn của app dựng view
//     một lần trong viewDidLoad (đăng ký thông báo, tải dữ liệu…), dựng lại sẽ tải lại / đăng ký hai lần. iOS 6 không gỡ view
//     nữa → trên iOS 5 cũng giữ view cho các màn của app (ảnh bìa vẫn tự xoá khỏi bộ đệm khi thiếu bộ nhớ).
#import "CBCompat.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

BOOL CBOldIOS(void) {
    return NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_6_0;
}

#pragma mark - Hàm thay

static id cb_arrayAt(NSArray *self, SEL _cmd, NSUInteger i) {
    return [self objectAtIndex:i];
}

static void cb_marraySet(NSMutableArray *self, SEL _cmd, id obj, NSUInteger i) {
    if (i == self.count) [self addObject:obj];
    else [self replaceObjectAtIndex:i withObject:obj];
}

static id cb_dictGet(NSDictionary *self, SEL _cmd, id key) {
    return [self objectForKey:key];
}

static void cb_mdictSet(NSMutableDictionary *self, SEL _cmd, id obj, id key) {
    if (obj) [self setObject:obj forKey:key];
    else [self removeObjectForKey:key];
}

static id cb_osetAt(NSOrderedSet *self, SEL _cmd, NSUInteger i) {
    return [self objectAtIndex:i];
}

static void cb_mosetSet(NSMutableOrderedSet *self, SEL _cmd, id obj, NSUInteger i) {
    if (i == self.count) [self addObject:obj];
    else [self replaceObjectAtIndex:i withObject:obj];
}

static NSInteger cb_ipItem(NSIndexPath *self, SEL _cmd) {
    return (NSInteger)[self indexAtPosition:1];
}

static NSIndexPath *cb_ipForItem(Class self, SEL _cmd, NSInteger item, NSInteger section) {
    return [NSIndexPath indexPathForRow:item inSection:section];
}

static const void *kCBScaleKey = &kCBScaleKey;

static void cb_setMinScale(UILabel *self, SEL _cmd, CGFloat f) {
    objc_setAssociatedObject(self, kCBScaleKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.minimumFontSize = MAX(6, floor(self.font.pointSize * f));
}

static CGFloat cb_minScale(UILabel *self, SEL _cmd) {
    return [objc_getAssociatedObject(self, kCBScaleKey) floatValue];
}

static BOOL cb_no(id self, SEL _cmd) {
    return NO;
}

static IMP cb_origAutorotate;

static BOOL cb_autorotate(UIViewController *self, SEL _cmd, UIInterfaceOrientation o) {
    if ([self respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        NSUInteger mask = [(id)self supportedInterfaceOrientations];
        return (mask & (1u << o)) != 0;
    }
    // Màn không khai báo: iPad mọi chiều, iPhone dọc (như iOS 6 với thanh điều hướng của app)
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) return YES;
    return ((BOOL (*)(id, SEL, UIInterfaceOrientation))cb_origAutorotate)(self, _cmd, o);
}

static IMP cb_origMemoryWarning;

static void cb_memoryWarning(UIViewController *self, SEL _cmd) {
    if ([NSStringFromClass([self class]) hasPrefix:@"CB"]) return;  // màn của app: giữ view như iOS 6
    ((void (*)(id, SEL))cb_origMemoryWarning)(self, _cmd);
}

#pragma mark - Gắn

/// Thêm hàm cho lớp nếu lớp (kể cả lớp cha) chưa có. Chuỗi kiểu viết sẵn cho armv7 (NSUInteger = I, NSInteger = i,
/// CGFloat = f, BOOL = c) — app chỉ dựng armv7.
static void cb_add(Class cls, SEL sel, IMP imp, const char *types) {
    if (!cls || [cls instancesRespondToSelector:sel]) return;
    class_addMethod(cls, sel, imp, types);
}

@interface CBCompat : NSObject
@end

@implementation CBCompat

+ (void)load {
    if (!CBOldIOS()) return;
    @autoreleasepool {
        cb_add([NSArray class], @selector(objectAtIndexedSubscript:), (IMP)cb_arrayAt, "@@:I");
        cb_add([NSMutableArray class], @selector(setObject:atIndexedSubscript:), (IMP)cb_marraySet, "v@:@I");
        cb_add([NSDictionary class], @selector(objectForKeyedSubscript:), (IMP)cb_dictGet, "@@:@");
        cb_add([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:), (IMP)cb_mdictSet, "v@:@@");
        cb_add([NSOrderedSet class], @selector(objectAtIndexedSubscript:), (IMP)cb_osetAt, "@@:I");
        cb_add([NSMutableOrderedSet class], @selector(setObject:atIndexedSubscript:), (IMP)cb_mosetSet, "v@:@I");

        cb_add([NSIndexPath class], @selector(item), (IMP)cb_ipItem, "i@:");
        cb_add(object_getClass([NSIndexPath class]), @selector(indexPathForItem:inSection:), (IMP)cb_ipForItem, "@#:ii");

        cb_add([UILabel class], @selector(setMinimumScaleFactor:), (IMP)cb_setMinScale, "v@:f");
        cb_add([UILabel class], @selector(minimumScaleFactor), (IMP)cb_minScale, "f@:");

        cb_add([AVPlayerItem class], @selector(canPlaySlowForward), (IMP)cb_no, "c@:");

        Method rot = class_getInstanceMethod([UIViewController class], @selector(shouldAutorotateToInterfaceOrientation:));
        if (rot) cb_origAutorotate = method_setImplementation(rot, (IMP)cb_autorotate);
        Method mem = class_getInstanceMethod([UIViewController class], @selector(didReceiveMemoryWarning));
        if (mem) cb_origMemoryWarning = method_setImplementation(mem, (IMP)cb_memoryWarning);
    }
}

@end
