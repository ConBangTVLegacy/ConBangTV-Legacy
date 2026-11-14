#import <UIKit/UIKit.h>

/// Một hàng phim cuộn ngang (trang chủ). Phần tử: như CBPosterCell.
@interface CBRowCell : UITableViewCell
@property (nonatomic, copy) void (^onSelect)(NSDictionary *item);
@property (nonatomic, copy) void (^onLongPress)(NSDictionary *item);
@property (nonatomic, readonly) CGFloat offset;
- (void)setItems:(NSArray *)items offset:(CGFloat)offset;
+ (CGFloat)height;
@end

/// Phần tử hiển thị từ một Film của lõi {url, title, poster, badge, imdb: {score, votes}}
NSDictionary *CBItemFromFilm(NSDictionary *film);
