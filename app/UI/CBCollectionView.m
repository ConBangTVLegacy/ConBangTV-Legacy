#import "CBCollectionView.h"

NSString *const CBCollectionElementKindSectionHeader = @"CBCollectionElementKindSectionHeader";
NSString *const CBCollectionElementKindSectionFooter = @"CBCollectionElementKindSectionFooter";

#pragma mark - Ô

@interface CBCollectionReusableView ()
@property (nonatomic, copy, readwrite) NSString *reuseIdentifier;
@end

@implementation CBCollectionReusableView
- (void)prepareForReuse {
}
@end

@implementation CBCollectionViewCell {
    UIView *_contentView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _contentView = [[UIView alloc] initWithFrame:self.bounds];
        _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _contentView.backgroundColor = [UIColor clearColor];
        [self addSubview:_contentView];
    }
    return self;
}

- (UIView *)contentView {
    return _contentView;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    if (self.highlighted) self.highlighted = NO;
}

@end

#pragma mark - Bố cục

@interface CBCollectionView ()
- (void)cb_invalidateLayout;
@end

@interface CBCollectionViewFlowLayout ()
@property (nonatomic, weak, readwrite) CBCollectionView *collectionView;
@end

@implementation CBCollectionViewFlowLayout

- (instancetype)init {
    if ((self = [super init])) {
        // Mặc định như UICollectionViewFlowLayout
        _itemSize = CGSizeMake(50, 50);
        _minimumLineSpacing = 10;
        _minimumInteritemSpacing = 10;
    }
    return self;
}

- (void)invalidateLayout {
    [self.collectionView cb_invalidateLayout];
}

@end

#pragma mark - Lưới

static NSString *CBSuppKey(NSString *kind, NSInteger section) {
    return [NSString stringWithFormat:@"%@|%ld", kind, (long)section];
}

@implementation CBCollectionView {
    CBCollectionViewFlowLayout *_layout;
    NSMutableDictionary *_cellClasses;   // mã ô → lớp
    NSMutableDictionary *_suppClasses;   // «loại|mã» → lớp
    NSMutableDictionary *_pools;         // mã ô / «loại|mã» → ô đã ẩn chờ dùng lại
    // Kết quả bố cục: mỗi mục một NSData chứa CGRect của từng ô; ô đầu / ô cuối (CGRectZero = không có)
    NSMutableArray *_itemFrames;
    NSMutableData *_headerFrames, *_footerFrames;
    NSInteger _sections;
    BOOL _layoutValid;
    CGSize _layoutSize;
    NSMutableDictionary *_visibleCells;  // NSIndexPath → ô
    NSMutableDictionary *_visibleSupps;  // «loại|mục» → ô đầu / ô cuối
    NSIndexPath *_touchPath;
    // Đang dựng ô (tile): ô vừa lấy gọi layoutIfNeeded (ô kênh — đo khung logo) thì CALayer bố cục ngược lên tới lưới nếu lưới
    // cũng đang chờ bố cục → tile lồng trong tile; tile ngoài ghi đè ô tile trong đã đặt cho cùng vị trí, ô đó thành «mồ côi»:
    // vẫn hiện, không ai quản — nằm đè ô thật mãi (iPad 1: ô kênh của danh sách cũ còn đó sau khi đổi danh sách)
    BOOL _tiling, _retile;
    // delegate của UIScrollView trên iOS 5 / 6 là con trỏ «assign» (không tự về nil): màn chủ đã giải phóng mà lưới còn vẽ lại
    // (chuyển cảnh, CATransaction) thì gọi vào vùng nhớ đã trả — văng (iPad 1, «home» khi đang ở màn Truyền hình). Giữ thêm
    // tham chiếu yếu: lưới tự gọi qua nó, và gỡ delegate của UIScrollView khi chủ đã mất.
    __weak id<CBCollectionViewDelegate> _weakDelegate;
}

@dynamic delegate;

- (void)setDelegate:(id<CBCollectionViewDelegate>)delegate {
    _weakDelegate = delegate;
    [super setDelegate:delegate];
}

/// Delegate còn sống (nil nếu chủ đã giải phóng — khi đó gỡ luôn khỏi UIScrollView)
- (id<CBCollectionViewDelegate>)liveDelegate {
    id<CBCollectionViewDelegate> d = _weakDelegate;
    if (!d && [super delegate]) [super setDelegate:nil];
    return d;
}

- (instancetype)initWithFrame:(CGRect)frame collectionViewLayout:(CBCollectionViewFlowLayout *)layout {
    if ((self = [super initWithFrame:frame])) {
        _layout = layout ?: [[CBCollectionViewFlowLayout alloc] init];
        _layout.collectionView = self;
        _cellClasses = [NSMutableDictionary dictionary];
        _suppClasses = [NSMutableDictionary dictionary];
        _pools = [NSMutableDictionary dictionary];
        _itemFrames = [NSMutableArray array];
        _headerFrames = [NSMutableData data];
        _footerFrames = [NSMutableData data];
        _visibleCells = [NSMutableDictionary dictionary];
        _visibleSupps = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame collectionViewLayout:nil];
}

- (CBCollectionViewFlowLayout *)collectionViewLayout {
    return _layout;
}

- (void)setDataSource:(id<CBCollectionViewDataSource>)dataSource {
    _dataSource = dataSource;
    [self reloadData];
}

#pragma mark Đăng ký / lấy ô

- (void)registerClass:(Class)cls forCellWithReuseIdentifier:(NSString *)identifier {
    if (cls && identifier) _cellClasses[identifier] = cls;
}

- (void)registerClass:(Class)cls forSupplementaryViewOfKind:(NSString *)kind withReuseIdentifier:(NSString *)identifier {
    if (cls && kind && identifier) _suppClasses[[NSString stringWithFormat:@"%@|%@", kind, identifier]] = cls;
}

- (id)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)ip {
    CGRect frame = [self frameForItemAt:ip];
    NSMutableArray *pool = _pools[identifier];
    CBCollectionViewCell *cell = pool.lastObject;
    if (cell) {
        [pool removeLastObject];
        [cell prepareForReuse];
        cell.frame = frame;
        return cell;
    }
    Class cls = _cellClasses[identifier] ?: [CBCollectionViewCell class];
    cell = [[cls alloc] initWithFrame:frame];
    cell.reuseIdentifier = identifier;
    return cell;
}

- (id)dequeueReusableSupplementaryViewOfKind:(NSString *)kind withReuseIdentifier:(NSString *)identifier
                                forIndexPath:(NSIndexPath *)ip {
    NSString *key = [NSString stringWithFormat:@"%@|%@", kind, identifier];
    CGRect frame = [self frameForSupplementary:kind section:ip.section];
    NSMutableArray *pool = _pools[key];
    CBCollectionReusableView *view = pool.lastObject;
    if (view) {
        [pool removeLastObject];
        [view prepareForReuse];
        view.frame = frame;
        return view;
    }
    Class cls = _suppClasses[key] ?: [CBCollectionReusableView class];
    view = [[cls alloc] initWithFrame:frame];
    view.reuseIdentifier = key;
    return view;
}

/// Cất ô vào kho chờ dùng lại: chỉ ẩn đi, không gỡ khỏi lưới (thêm / gỡ view mỗi lần cuộn tốn hơn)
- (void)enqueue:(CBCollectionReusableView *)view {
    if (!view) return;
    if ([view isKindOfClass:[CBCollectionViewCell class]] && ((CBCollectionViewCell *)view).highlighted) {
        ((CBCollectionViewCell *)view).highlighted = NO;
    }
    view.hidden = YES;
    NSString *key = view.reuseIdentifier;
    if (!key) {
        [view removeFromSuperview];
        return;
    }
    NSMutableArray *pool = _pools[key];
    if (!pool) {
        pool = [NSMutableArray array];
        _pools[key] = pool;
    }
    [pool addObject:view];
}

#pragma mark Dữ liệu

- (void)reloadData {
    for (CBCollectionReusableView *v in _visibleCells.allValues) [self enqueue:v];
    for (CBCollectionReusableView *v in _visibleSupps.allValues) [self enqueue:v];
    [_visibleCells removeAllObjects];
    [_visibleSupps removeAllObjects];
    _touchPath = nil;
    _layoutValid = NO;
    [self setNeedsLayout];
}

- (void)cb_invalidateLayout {
    _layoutValid = NO;
    [self setNeedsLayout];
}

- (NSIndexPath *)indexPathForItemAtPoint:(CGPoint)point {
    [self ensureLayout];
    for (NSInteger s = 0; s < _sections; s++) {
        NSData *data = _itemFrames[s];
        const CGRect *frames = data.bytes;
        NSInteger n = data.length / sizeof(CGRect);
        for (NSInteger i = 0; i < n; i++) {
            if (CGRectContainsPoint(frames[i], point)) return [NSIndexPath indexPathForRow:i inSection:s];
        }
    }
    return nil;
}

- (CBCollectionViewCell *)cellForItemAtIndexPath:(NSIndexPath *)ip {
    return ip ? _visibleCells[ip] : nil;
}

- (NSArray *)visibleCells {
    return _visibleCells.allValues;
}

- (void)scrollToItemAtIndexPath:(NSIndexPath *)ip atScrollPosition:(CBCollectionViewScrollPosition)position animated:(BOOL)animated {
    [self ensureLayout];
    CGRect f = [self frameForItemAt:ip];
    if (CGRectIsEmpty(f)) return;
    CGSize size = self.bounds.size, content = self.contentSize;
    UIEdgeInsets in = self.contentInset;
    CGPoint off = self.contentOffset;
    if (_layout.scrollDirection == CBCollectionViewScrollDirectionHorizontal) {
        CGFloat x = position == CBCollectionViewScrollPositionTop ? f.origin.x : CGRectGetMidX(f) - size.width / 2;
        off.x = MAX(-in.left, MIN(x, content.width + in.right - size.width));
    } else {
        CGFloat y = position == CBCollectionViewScrollPositionTop ? f.origin.y : CGRectGetMidY(f) - size.height / 2;
        off.y = MAX(-in.top, MIN(y, content.height + in.bottom - size.height));
    }
    [self setContentOffset:off animated:animated];
}

#pragma mark Bố cục

- (CGRect)frameForItemAt:(NSIndexPath *)ip {
    [self ensureLayout];
    if (!ip || ip.section < 0 || ip.section >= _sections) return CGRectZero;
    NSData *data = _itemFrames[ip.section];
    NSInteger i = ip.row;
    if (i < 0 || i >= (NSInteger)(data.length / sizeof(CGRect))) return CGRectZero;
    return ((const CGRect *)data.bytes)[i];
}

- (CGRect)frameForSupplementary:(NSString *)kind section:(NSInteger)s {
    [self ensureLayout];
    if (s < 0 || s >= _sections) return CGRectZero;
    BOOL head = [kind isEqualToString:CBCollectionElementKindSectionHeader];
    return ((const CGRect *)(head ? _headerFrames : _footerFrames).bytes)[s];
}

- (void)ensureLayout {
    if (!_layoutValid || !CGSizeEqualToSize(self.bounds.size, _layoutSize)) [self computeLayout];
}

- (void)computeLayout {
    _layoutValid = YES;
    _layoutSize = self.bounds.size;
    [_itemFrames removeAllObjects];
    _headerFrames.length = 0;
    _footerFrames.length = 0;
    id<CBCollectionViewDataSource> ds = self.dataSource;
    id<CBCollectionViewDelegate> dg = [self liveDelegate];
    CBCollectionViewFlowLayout *L = _layout;
    _sections = !ds ? 0 : ([ds respondsToSelector:@selector(numberOfSectionsInCollectionView:)] ? [ds numberOfSectionsInCollectionView:self] : 1);
    BOOL horizontal = L.scrollDirection == CBCollectionViewScrollDirectionHorizontal;
    BOOL askSize = [dg respondsToSelector:@selector(collectionView:layout:sizeForItemAtIndexPath:)];
    BOOL askInset = [dg respondsToSelector:@selector(collectionView:layout:insetForSectionAtIndex:)];
    BOOL askHead = [dg respondsToSelector:@selector(collectionView:layout:referenceSizeForHeaderInSection:)];
    BOOL askFoot = [dg respondsToSelector:@selector(collectionView:layout:referenceSizeForFooterInSection:)];
    CGFloat W = _layoutSize.width, H = _layoutSize.height;
    CGFloat pos = 0;  // y (cuộn dọc) / x (cuộn ngang) đã dùng tới
    for (NSInteger s = 0; s < _sections; s++) {
        CGSize hs = askHead ? [dg collectionView:self layout:L referenceSizeForHeaderInSection:s] : L.headerReferenceSize;
        CGRect hf = CGRectZero;
        if (horizontal && hs.width > 0) {
            hf = CGRectMake(pos, 0, hs.width, H);
            pos += hs.width;
        } else if (!horizontal && hs.height > 0) {
            hf = CGRectMake(0, pos, W, hs.height);
            pos += hs.height;
        }
        [_headerFrames appendBytes:&hf length:sizeof(CGRect)];

        UIEdgeInsets in = askInset ? [dg collectionView:self layout:L insetForSectionAtIndex:s] : L.sectionInset;
        NSInteger n = MAX(0, [ds collectionView:self numberOfItemsInSection:s]);
        NSMutableData *frames = [NSMutableData dataWithLength:n * sizeof(CGRect)];
        CGRect *out = frames.mutableBytes;
        if (horizontal) {
            // Một hàng ngang (app chỉ dùng kiểu này cho hàng phim), ô giữa theo chiều cao
            CGFloat x = pos + in.left, avail = H - in.top - in.bottom;
            for (NSInteger i = 0; i < n; i++) {
                CGSize is = askSize ? [dg collectionView:self layout:L sizeForItemAtIndexPath:[NSIndexPath indexPathForRow:i inSection:s]]
                                    : L.itemSize;
                out[i] = CGRectMake(round(x), round(in.top + MAX(0, (avail - is.height) / 2)), is.width, is.height);
                x += is.width + L.minimumLineSpacing;
            }
            pos = (n ? x - L.minimumLineSpacing : x) + in.right;
        } else {
            CGFloat avail = W - in.left - in.right, y = pos + in.top, lastGap = L.minimumInteritemSpacing;
            NSInteger i = 0;
            CGSize *sizes = malloc(sizeof(CGSize) * (n ? n : 1));
            for (NSInteger k = 0; k < n; k++) {
                sizes[k] = askSize ? [dg collectionView:self layout:L sizeForItemAtIndexPath:[NSIndexPath indexPathForRow:k inSection:s]]
                                   : L.itemSize;
            }
            while (i < n) {
                NSInteger start = i;
                CGFloat used = 0, rowH = 0;
                while (i < n) {
                    CGFloat need = i == start ? sizes[i].width : used + L.minimumInteritemSpacing + sizes[i].width;
                    if (i > start && need > avail + 0.5) break;
                    used = need;
                    rowH = MAX(rowH, sizes[i].height);
                    i++;
                }
                NSInteger count = i - start;
                CGFloat gap = L.minimumInteritemSpacing;
                // Hàng đầy: dàn đều phần thừa vào các khe như UICollectionViewFlowLayout; hàng cuối: cùng khe với hàng trên
                if (i < n && count > 1) {
                    gap += MAX(0, avail - used) / (count - 1);
                    lastGap = gap;
                } else if (count > 1) {
                    gap = lastGap;
                }
                CGFloat x = in.left;
                for (NSInteger k = start; k < i; k++) {
                    out[k] = CGRectMake(round(x), round(y + (rowH - sizes[k].height) / 2), sizes[k].width, sizes[k].height);
                    x += sizes[k].width + gap;
                }
                y += rowH + L.minimumLineSpacing;
            }
            free(sizes);
            if (n) y -= L.minimumLineSpacing;
            pos = y + in.bottom;
        }
        [_itemFrames addObject:frames];

        CGSize fs = askFoot ? [dg collectionView:self layout:L referenceSizeForFooterInSection:s] : L.footerReferenceSize;
        CGRect ff = CGRectZero;
        if (horizontal && fs.width > 0) {
            ff = CGRectMake(pos, 0, fs.width, H);
            pos += fs.width;
        } else if (!horizontal && fs.height > 0) {
            ff = CGRectMake(0, pos, W, fs.height);
            pos += fs.height;
        }
        [_footerFrames appendBytes:&ff length:sizeof(CGRect)];
    }
    CGSize content = horizontal ? CGSizeMake(ceil(pos), H) : CGSizeMake(W, ceil(pos));
    if (!CGSizeEqualToSize(content, self.contentSize)) self.contentSize = content;
    // Ít ô hơn trước (tìm lại, đổi bản…): đừng để chỗ cuộn nằm quá cuối nội dung (màn trống tới khi chạm)
    UIEdgeInsets in = self.contentInset;
    CGPoint off = self.contentOffset;
    CGFloat maxX = MAX(-in.left, content.width + in.right - W), maxY = MAX(-in.top, content.height + in.bottom - H);
    if (!self.dragging && !self.decelerating && (off.x > maxX + 0.5 || off.y > maxY + 0.5)) {
        self.contentOffset = CGPointMake(MIN(off.x, maxX), MIN(off.y, maxY));
    }
}

- (void)layoutSubviews {
    [self liveDelegate];  // chủ đã mất: gỡ delegate trước khi UIScrollView gọi scrollViewDidScroll:
    [super layoutSubviews];
    if (_tiling) {
        _retile = YES;    // bố cục lồng (xem _tiling): lần đang chạy dựng lại thêm một lượt
        return;
    }
    _tiling = YES;
    for (int pass = 0; pass < 2; pass++) {
        _retile = NO;
        [self ensureLayout];
        [self tile];
        if (!_retile) break;
    }
    _tiling = NO;
    _retile = NO;
}

/// Hiện đúng các ô nằm trong khung đang thấy, cất ô đã ra khỏi khung
- (void)tile {
    id<CBCollectionViewDataSource> ds = self.dataSource;
    CGRect visible = self.bounds;
    NSMutableSet *want = [NSMutableSet set];
    for (NSInteger s = 0; s < _sections; s++) {
        NSData *data = _itemFrames[s];
        const CGRect *frames = data.bytes;
        NSInteger n = data.length / sizeof(CGRect);
        for (NSInteger i = 0; i < n; i++) {
            if (CGRectIntersectsRect(frames[i], visible)) [want addObject:[NSIndexPath indexPathForRow:i inSection:s]];
        }
    }
    for (NSIndexPath *ip in _visibleCells.allKeys) {
        if ([want containsObject:ip]) continue;
        [self enqueue:_visibleCells[ip]];
        [_visibleCells removeObjectForKey:ip];
    }
    for (NSIndexPath *ip in want) {
        CBCollectionViewCell *cell = _visibleCells[ip];
        if (!cell) {
            cell = [ds collectionView:self cellForItemAtIndexPath:ip];
            if (!cell) continue;
            // Phòng hờ: trong lúc lấy ô, chỗ này đã có ô khác (gọi lồng) — cất ô kia, đừng để nó mồ côi
            CBCollectionViewCell *other = _visibleCells[ip];
            if (other && other != cell) [self enqueue:other];
            _visibleCells[ip] = cell;
        }
        [self show:cell frame:((const CGRect *)[_itemFrames[ip.section] bytes])[ip.row]];
    }

    BOOL askSupp = [ds respondsToSelector:@selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)];
    NSMutableSet *wantSupp = [NSMutableSet set];
    for (int pass = 0; pass < 2; pass++) {
        NSString *kind = pass == 0 ? CBCollectionElementKindSectionHeader : CBCollectionElementKindSectionFooter;
        const CGRect *frames = (pass == 0 ? _headerFrames : _footerFrames).bytes;
        for (NSInteger s = 0; s < _sections && askSupp; s++) {
            CGRect f = frames[s];
            if (CGRectIsEmpty(f) || !CGRectIntersectsRect(f, visible)) continue;
            NSString *key = CBSuppKey(kind, s);
            [wantSupp addObject:key];
            CBCollectionReusableView *v = _visibleSupps[key];
            if (!v) {
                v = [ds collectionView:self viewForSupplementaryElementOfKind:kind atIndexPath:[NSIndexPath indexPathForRow:0 inSection:s]];
                if (!v) continue;
                _visibleSupps[key] = v;
            }
            [self show:v frame:f];
        }
    }
    for (NSString *key in _visibleSupps.allKeys) {
        if ([wantSupp containsObject:key]) continue;
        [self enqueue:_visibleSupps[key]];
        [_visibleSupps removeObjectForKey:key];
    }
}

- (void)show:(UIView *)view frame:(CGRect)frame {
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
    if (view.superview != self) [self insertSubview:view atIndex:0];  // dưới thanh cuộn của UIScrollView
    if (view.hidden) view.hidden = NO;
}

#pragma mark Chạm

// Như UITableView: UIScrollView đưa chạm vào ô sau ~0,15 s nếu không phải cuộn; cuộn thì chạm bị huỷ (touchesCancelled).
// Ô chứa nút (UIButton…) thì nút tự nhận chạm. Không chuyển tiếp lên trên (lưới nằm trong ô bảng: bảng không chọn dòng).

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    _touchPath = touches.count == 1 ? [self indexPathForItemAtPoint:[t locationInView:self]] : nil;
    if (_touchPath) [self cellForItemAtIndexPath:_touchPath].highlighted = YES;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_touchPath) return;
    NSIndexPath *ip = [self indexPathForItemAtPoint:[[touches anyObject] locationInView:self]];
    [self cellForItemAtIndexPath:_touchPath].highlighted = [ip isEqual:_touchPath];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    NSIndexPath *start = _touchPath;
    _touchPath = nil;
    if (!start) return;
    [self cellForItemAtIndexPath:start].highlighted = NO;
    NSIndexPath *ip = [self indexPathForItemAtPoint:[[touches anyObject] locationInView:self]];
    id<CBCollectionViewDelegate> dg = [self liveDelegate];
    if ([ip isEqual:start] && [dg respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [dg collectionView:self didSelectItemAtIndexPath:ip];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_touchPath) [self cellForItemAtIndexPath:_touchPath].highlighted = NO;
    _touchPath = nil;
}

@end
