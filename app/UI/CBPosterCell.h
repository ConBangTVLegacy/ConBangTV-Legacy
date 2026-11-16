#import "CBCollectionView.h"

/// Một phim trên lưới / hàng ngang. item: {url, title, poster, badge, sub, progress (0..1), epUrl}
@interface CBPosterCell : CBCollectionViewCell
@property (nonatomic, strong, readonly) UIImageView *poster;
- (void)setItem:(NSDictionary *)item;
/// Cỡ ô cho bề ngang poster w (ảnh 2:3 + 2 dòng tên + 1 dòng phụ)
+ (CGSize)sizeForWidth:(CGFloat)w;
/// Bề ngang poster mặc định (iPhone / iPad)
+ (CGFloat)defaultWidth;
@end
