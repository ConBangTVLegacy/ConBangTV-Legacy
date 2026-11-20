#import <UIKit/UIKit.h>

@class CBNavController;

/// Các tab của app (thanh tab nổi kiểu iOS 26)
typedef NS_ENUM(NSInteger, CBTab) {
    CBTabHome = 0,
    CBTabTV,
    CBTabFollows,
    CBTabSettings,
    CBTabSearch,      // nút tìm tròn tách riêng (iPhone) / biểu tượng cuối thanh (iPad)
};

/// Màn gốc của cửa sổ (iPhone + iPad): mỗi tab một thanh điều hướng (CBNavController); thanh tab nổi bằng kính —
///  • iPhone: ở đáy (4 tab + nút tìm tròn bên phải); cuộn xuống thì thu thành một nút tròn, cuộn lên mở lại. Thanh thu nhỏ của
///    CBMiniPlayer (bottomBar) là viên kính nằm ngay trên thanh tab (thanh tab thu gọn: nằm giữa nút tab và nút tìm).
///  • iPad: giữa mép trên, chỉ hiện ở màn gốc của tab (màn đẩy vào có thanh điều hướng thì ẩn).
/// Nội dung tràn dưới thanh tab (thanh nổi); danh sách chính của màn đang hiện được đặt lề dưới (contentInset) cho khỏi bị che.
/// Màn được trình bày đè (trình phát, «Ai đang xem?»…) phủ cả thanh tab.
@interface CBRootViewController : UIViewController
- (instancetype)init;
/// Thanh điều hướng của tab đang chọn
@property (nonatomic, readonly) UIViewController *content;
@property (nonatomic, readonly) CBTab selectedTab;
- (void)selectTab:(CBTab)tab;
/// Thanh điều hướng của một tab (tạo khi cần)
- (CBNavController *)navForTab:(CBTab)tab;
/// Chấm báo (vd «Theo dõi» có tập mới)
- (void)setBadge:(BOOL)on forTab:(CBTab)tab;
@property (nonatomic, readonly) UIView *bottomBar;
/// Gắn / bỏ thanh thu nhỏ (nil = bỏ) — iPhone. Thanh tự đặt khung, nằm trên nội dung.
- (void)setBottomBar:(UIView *)bar height:(CGFloat)height;
/// Đỉnh bàn phím trong toạ độ view (0 = không có bàn phím)
@property (nonatomic, readonly) CGFloat keyboardTop;
/// Bàn phím hiện / ẩn (khung nổi của CBMiniPlayer dời lên trên bàn phím)
@property (nonatomic, copy) void (^keyboardChanged)(NSTimeInterval duration);
/// Phần đáy màn bị thanh tab (+ thanh thu nhỏ) che — lề dưới cho danh sách / khung nổi
@property (nonatomic, readonly) CGFloat overlayBottom;
/// Phần đỉnh màn bị thanh tab che (iPad, màn gốc của tab) + thanh trạng thái (iOS 7+)
@property (nonatomic, readonly) CGFloat overlayTop;
/// Thanh tab đang thu gọn (iPhone)
@property (nonatomic, readonly) BOOL compact;
/// Đặt lại lề của danh sách chính (màn vừa hiện / đổi khung)
- (void)applyInsetsTo:(UIViewController *)vc;
/// Màn gốc của cửa sổ chính, không thì nil
+ (CBRootViewController *)current;
/// Thanh trạng thái đè lên nội dung (iOS 7+: 20 điểm; iOS 5 / 6: cửa sổ đã chừa sẵn)
+ (CGFloat)statusInset;
@end

/// Màn trong tab có thể chỉ rõ danh sách chính (để đặt lề dưới / thu gọn thanh tab khi cuộn); không khai báo thì tự tìm
@protocol CBTabContent <NSObject>
@optional
- (UIScrollView *)cbMainScrollView;
@end
