#import <UIKit/UIKit.h>
#import "CBCollectionView.h"

/// Ô một kênh: logo (chữ tên kênh khi chưa có / không có ảnh), số, tên, ★, chương trình đang phát + thanh tiến độ, kế tiếp.
/// compact: ô ngang của hàng «Kênh vừa xem» ở trang chủ (logo to, nhãn TRỰC TIẾP).
@interface CBChannelCell : CBCollectionViewCell
@property (nonatomic, copy) void (^onStar)(void);
- (void)setChannel:(NSDictionary *)channel compact:(BOOL)compact;
+ (CGSize)compactSize;
@end

/// Hàng «Kênh vừa xem» ở trang chủ
@interface CBTVRowCell : UITableViewCell
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
- (void)setChannels:(NSArray *)channels;
+ (CGFloat)height;
@end

/// Màn «Truyền hình»: danh sách kênh của danh sách M3U đang chọn — nhóm (★ Yêu thích, Tất cả, nhóm của danh sách), tìm theo
/// tên / số kênh, lưới kênh kèm chương trình đang phát. Chạm: phát (CBLivePlayerViewController với các kênh đang lọc); nhấn giữ:
/// lịch phát sóng / yêu thích / thử lại kênh lỗi. Chưa có danh sách: nút thêm địa chỉ M3U.
@interface CBTVViewController : UIViewController
/// Kênh đang hiện (sau khi lọc)
- (NSArray *)visibleChannels;
- (void)openChannelAt:(NSInteger)index;
- (void)selectGroupAt:(NSInteger)index;
- (void)showGuideAt:(NSInteger)index;
- (void)setQuery:(NSString *)query;
/// Hỏi địa chỉ danh sách M3U rồi thêm (Cài đặt › Truyền hình cũng dùng)
+ (void)askAddList:(void (^)(NSDictionary *list))done;
/// Phát kênh theo khoá (thông báo «Nhắc tôi», hàng «Kênh vừa xem»); chưa tải danh sách thì tải trước
+ (void)playKey:(NSString *)key from:(UIViewController *)host;
@end
