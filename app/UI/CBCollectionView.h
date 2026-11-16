#import <UIKit/UIKit.h>

/// Lưới tự vẽ thay UICollectionView (chỉ có từ iOS 6) để app chạy được cả iOS 5 — dùng chung cho mọi bản iOS.
/// Chỉ làm phần app cần: bố cục kiểu UICollectionViewFlowLayout (cuộn dọc: ô xếp trái → phải, hết chỗ thì xuống hàng, hàng
/// đầy dàn đều; cuộn ngang: một hàng), ô đầu / ô cuối của mục, tái dùng ô, chạm chọn ô (tô ô khi đang chạm), cuộn tới ô.
/// Tên hàm / hàm uỷ quyền giống UICollectionView nên mã các màn gần như giữ nguyên.

extern NSString *const CBCollectionElementKindSectionHeader;
extern NSString *const CBCollectionElementKindSectionFooter;

typedef NS_ENUM(NSInteger, CBCollectionViewScrollDirection) {
    CBCollectionViewScrollDirectionVertical,
    CBCollectionViewScrollDirectionHorizontal,
};

typedef NS_ENUM(NSInteger, CBCollectionViewScrollPosition) {
    CBCollectionViewScrollPositionTop,
    CBCollectionViewScrollPositionCenteredVertically,
};

@class CBCollectionView;

@interface CBCollectionReusableView : UIView
@property (nonatomic, copy, readonly) NSString *reuseIdentifier;
/// Gọi ngay trước khi lấy lại ô cũ ra dùng (như UIKit)
- (void)prepareForReuse;
@end

@interface CBCollectionViewCell : CBCollectionReusableView
@property (nonatomic, strong, readonly) UIView *contentView;
/// Đang bị chạm (lớp con đổi giao diện trong setHighlighted:)
@property (nonatomic, getter=isHighlighted) BOOL highlighted;
@end

@interface CBCollectionViewFlowLayout : NSObject
@property (nonatomic) CBCollectionViewScrollDirection scrollDirection;
@property (nonatomic) CGSize itemSize;
/// Cuộn dọc: khoảng cách giữa các hàng; cuộn ngang: giữa các ô
@property (nonatomic) CGFloat minimumLineSpacing;
/// Khoảng cách tối thiểu giữa hai ô cùng hàng (cuộn dọc)
@property (nonatomic) CGFloat minimumInteritemSpacing;
@property (nonatomic) UIEdgeInsets sectionInset;
@property (nonatomic) CGSize headerReferenceSize;
@property (nonatomic) CGSize footerReferenceSize;
@property (nonatomic, weak, readonly) CBCollectionView *collectionView;
/// Tính lại vị trí mọi ô (hỏi lại cỡ ô / cỡ ô đầu, ô cuối) ở lần dựng sau — không hỏi lại ô
- (void)invalidateLayout;
@end

@protocol CBCollectionViewDataSource <NSObject>
- (NSInteger)collectionView:(CBCollectionView *)cv numberOfItemsInSection:(NSInteger)section;
- (CBCollectionViewCell *)collectionView:(CBCollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip;
@optional
- (NSInteger)numberOfSectionsInCollectionView:(CBCollectionView *)cv;
- (CBCollectionReusableView *)collectionView:(CBCollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)ip;
@end

@protocol CBCollectionViewDelegate <UIScrollViewDelegate>
@optional
- (void)collectionView:(CBCollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip;
- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip;
- (UIEdgeInsets)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)layout insetForSectionAtIndex:(NSInteger)s;
- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)layout referenceSizeForHeaderInSection:(NSInteger)s;
- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)layout referenceSizeForFooterInSection:(NSInteger)s;
@end

@interface CBCollectionView : UIScrollView
- (instancetype)initWithFrame:(CGRect)frame collectionViewLayout:(CBCollectionViewFlowLayout *)layout;
@property (nonatomic, strong, readonly) CBCollectionViewFlowLayout *collectionViewLayout;
@property (nonatomic, weak) id<CBCollectionViewDataSource> dataSource;
@property (nonatomic, weak) id<CBCollectionViewDelegate> delegate;
- (void)registerClass:(Class)cls forCellWithReuseIdentifier:(NSString *)identifier;
- (void)registerClass:(Class)cls forSupplementaryViewOfKind:(NSString *)kind withReuseIdentifier:(NSString *)identifier;
- (id)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)ip;
- (id)dequeueReusableSupplementaryViewOfKind:(NSString *)kind withReuseIdentifier:(NSString *)identifier
                                forIndexPath:(NSIndexPath *)ip;
/// Bỏ mọi ô đang hiện, hỏi lại dữ liệu ở lần dựng sau (gọi layoutIfNeeded nếu cần contentSize ngay)
- (void)reloadData;
- (NSIndexPath *)indexPathForItemAtPoint:(CGPoint)point;
- (CBCollectionViewCell *)cellForItemAtIndexPath:(NSIndexPath *)ip;
- (NSArray *)visibleCells;
- (void)scrollToItemAtIndexPath:(NSIndexPath *)ip atScrollPosition:(CBCollectionViewScrollPosition)position animated:(BOOL)animated;
@end
