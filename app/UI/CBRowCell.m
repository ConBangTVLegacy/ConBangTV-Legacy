#import "CBRowCell.h"
#import "CBJSON.h"
#import "CBPosterCell.h"
#import "CBTheme.h"

NSDictionary *CBItemFromFilm(NSDictionary *film) {
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    if (CBStr(film, @"url")) item[@"url"] = CBStr(film, @"url");
    if (CBStr(film, @"title")) item[@"title"] = CBStr(film, @"title");
    if (CBStr(film, @"poster")) item[@"poster"] = CBStr(film, @"poster");
    if (CBStr(film, @"badge")) item[@"badge"] = CBStr(film, @"badge");
    NSDictionary *imdb = CBDict(film, @"imdb");
    if (imdb && CBNum(imdb, @"votes", 0) >= 100) item[@"sub"] = [NSString stringWithFormat:@"IMDb %.1f", CBNum(imdb, @"score", 0)];
    return item;
}

@interface CBRowCell () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@end

@implementation CBRowCell {
    UICollectionView *_cv;
    NSArray *_items;
}

+ (CGFloat)height {
    return [CBPosterCell sizeForWidth:[CBPosterCell defaultWidth]].height + 8;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [CBTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.itemSize = [CBPosterCell sizeForWidth:[CBPosterCell defaultWidth]];
        layout.minimumLineSpacing = 10;
        layout.sectionInset = UIEdgeInsetsMake(0, 12, 0, 12);
        _cv = [[UICollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:layout];
        _cv.backgroundColor = [CBTheme bg];
        _cv.showsHorizontalScrollIndicator = NO;
        _cv.dataSource = self;
        _cv.delegate = self;
        _cv.scrollsToTop = NO;
        _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_cv registerClass:[CBPosterCell class] forCellWithReuseIdentifier:@"poster"];
        [self.contentView addSubview:_cv];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        [_cv addGestureRecognizer:lp];
    }
    return self;
}

- (void)setItems:(NSArray *)items offset:(CGFloat)offset {
    _items = items;
    [_cv reloadData];
    [_cv layoutIfNeeded];
    CGFloat maxX = MAX(0, _cv.contentSize.width - _cv.bounds.size.width);
    _cv.contentOffset = CGPointMake(MIN(offset, maxX), 0);
}

- (CGFloat)offset {
    return _cv.contentOffset.x;
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || !self.onLongPress) return;
    NSIndexPath *ip = [_cv indexPathForItemAtPoint:[g locationInView:_cv]];
    if (ip && ip.item < (NSInteger)_items.count) self.onLongPress(_items[ip.item]);
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return _items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBPosterCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"poster" forIndexPath:ip];
    [cell setItem:_items[ip.item]];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.onSelect && ip.item < (NSInteger)_items.count) self.onSelect(_items[ip.item]);
}

@end
