#import "CBDetailViewController.h"
#import "CBCore.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBTheme.h"

#pragma mark - Ô tập

@interface CBEpCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
- (void)setTitle:(NSString *)title watched:(BOOL)watched current:(BOOL)current;
@end

@implementation CBEpCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 6;
        self.contentView.clipsToBounds = YES;
        _label = [[UILabel alloc] initWithFrame:CGRectInset(self.contentView.bounds, 4, 2)];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [CBTheme font:13];
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.6;
        [self.contentView addSubview:_label];
    }
    return self;
}

- (void)setTitle:(NSString *)title watched:(BOOL)watched current:(BOOL)current {
    // «Tập 12» → «12» cho gọn ô; tên khác giữ nguyên
    NSString *t = title ?: @"";
    if ([t hasPrefix:@"Tập "] && t.length <= 9) t = [t substringFromIndex:4];
    _label.text = t;
    self.contentView.backgroundColor = watched ? [CBTheme watched] : [CBTheme surface2];
    _label.textColor = [CBTheme text];
    self.contentView.layer.borderWidth = current ? 2 : 0;
    self.contentView.layer.borderColor = [CBTheme focus].CGColor;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1;
}
@end

@interface CBHostView : UICollectionReusableView
@end
@implementation CBHostView
@end

#pragma mark - Trang phim

@interface CBDetailViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@end

@implementation CBDetailViewController {
    NSDictionary *_item;
    NSDictionary *_detail;
    NSInteger _group;
    NSSet *_watched;
    NSDictionary *_hist;
    NSString *_error;
    UICollectionView *_cv;
    // Phần đầu (một bản, đặt vào ô phụ đầu lưới)
    UIView *_header;
    UIImageView *_poster;
    UILabel *_titleLabel, *_otherLabel, *_infoLabel, *_countLabel, *_messageLabel;
    UIButton *_playButton, *_followButton;
    UISegmentedControl *_groups;
    UIActivityIndicatorView *_spinner;
    CGFloat _headerHeight;
    UILabel *_descLabel;
}

- (instancetype)initWithItem:(NSDictionary *)item {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _item = item;
        self.title = CBStr(item, @"title");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    layout.minimumInteritemSpacing = 8;
    _cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _cv.backgroundColor = [CBTheme bg];
    _cv.alwaysBounceVertical = YES;
    _cv.dataSource = self;
    _cv.delegate = self;
    _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_cv registerClass:[CBEpCell class] forCellWithReuseIdentifier:@"ep"];
    [_cv registerClass:[CBHostView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"h"];
    [_cv registerClass:[CBHostView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"f"];
    [self.view addSubview:_cv];
    [self buildHeader];

    id cached = [CBCore sync:@"site.cachedDetail" args:@{@"url": CBStr(_item, @"url") ?: @""}];
    if (CBIsDict(cached)) [self applyDetail:cached];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Từ trình phát quay về: đánh dấu tập đã xem / nút Xem tiếp
    [self refreshMarks];
}

- (void)load {
    if (!_detail) [_spinner startAnimating];
    [CBCore call:@"site.detail" args:@{@"url": CBStr(_item, @"url") ?: @""} done:^(id ok, NSString *err) {
        [self->_spinner stopAnimating];
        if (CBIsDict(ok)) {
            [self applyDetail:ok];
        } else if (!self->_detail) {
            self->_error = [NSString stringWithFormat:@"Không tải được phim.\n%@", err ?: @""];
            [self relayout];
        }
    }];
}

- (void)applyDetail:(NSDictionary *)d {
    BOOL first = _detail == nil;
    _detail = d;
    _error = nil;
    self.title = CBStr(d, @"title") ?: self.title;
    _hist = [CBPrefs historyFor:CBStr(d, @"url") ?: @""];
    if (first) {
        NSInteger g = CBDetailGroupIndexOf(d, CBStr(_hist, @"epUrl"));
        _group = g >= 0 ? g : 0;
    }
    NSArray *groups = CBArr(d, @"groups");
    if (_group >= (NSInteger)groups.count) _group = 0;
    // Phim đang theo dõi: vào trang phim thì cập nhật số tập (chưa coi là đã xem tập mới — xem mới tính)
    if ([CBPrefs followOf:CBStr(d, @"url") ?: @""]) {
        [CBPrefs updateFollow:CBStr(d, @"url") count:CBDetailEpisodeCount(d) latest:CBStr(CBDetailLatestEpisode(d), @"title")
                         seen:NO];
    }
    [self refreshMarks];
}

- (void)refreshMarks {
    _watched = [CBPrefs watchedEpisodes];
    if (_detail) _hist = [CBPrefs historyFor:CBStr(_detail, @"url") ?: @""];
    [self relayout];
}

- (NSArray *)episodes {
    NSArray *groups = CBArr(_detail, @"groups");
    return _group < (NSInteger)groups.count ? (CBArr(groups[_group], @"episodes") ?: @[]) : @[];
}

#pragma mark - Phần đầu

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    [_header addSubview:l];
    return l;
}

- (void)buildHeader {
    _header = [[UIView alloc] init];
    _header.backgroundColor = [CBTheme bg];
    _poster = [[UIImageView alloc] init];
    _poster.backgroundColor = [CBTheme surface2];
    _poster.contentMode = UIViewContentModeScaleAspectFill;
    _poster.clipsToBounds = YES;
    _poster.layer.cornerRadius = 8;
    [_header addSubview:_poster];
    _titleLabel = [self label:[CBTheme bold:[CBTheme isPad] ? 22 : 18] color:[CBTheme text]];
    _otherLabel = [self label:[CBTheme font:14] color:[CBTheme dim]];
    _infoLabel = [self label:[CBTheme font:13] color:[CBTheme dim]];
    _countLabel = [self label:[CBTheme bold:16] color:[CBTheme text]];
    _messageLabel = [self label:[CBTheme font:15] color:[CBTheme dim]];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _playButton = [CBTheme button:@"▶ Xem" primary:YES];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_playButton];
    _followButton = [CBTheme button:@"Theo dõi" primary:NO];
    [_followButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_followButton];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [_header addSubview:_spinner];
    _descLabel = [[UILabel alloc] init];
    _descLabel.backgroundColor = [UIColor clearColor];
    _descLabel.textColor = [CBTheme dim];
    _descLabel.font = [CBTheme font:14];
    _descLabel.numberOfLines = 0;
}

- (void)relayout {
    NSString *poster = CBStr(_detail, @"poster") ?: CBStr(_item, @"poster");
    [CBImages load:poster size:CGSizeMake(160, 240) into:_poster];
    _titleLabel.text = CBStr(_detail, @"title") ?: CBStr(_item, @"title");
    _otherLabel.text = CBStr(_detail, @"otherTitle");
    _infoLabel.text = CBStr(_detail, @"info");
    NSArray *groups = CBArr(_detail, @"groups");
    [_groups removeFromSuperview];
    _groups = nil;
    if (groups.count > 1) {
        NSMutableArray *names = [NSMutableArray array];
        for (id g in groups) [names addObject:CBStr(g, @"name") ?: @"?"];
        _groups = [[UISegmentedControl alloc] initWithItems:names];
        _groups.segmentedControlStyle = UISegmentedControlStyleBar;
        _groups.selectedSegmentIndex = _group;
        [_groups addTarget:self action:@selector(groupChanged) forControlEvents:UIControlEventValueChanged];
        [_header addSubview:_groups];
    }
    NSArray *eps = [self episodes];
    _countLabel.text = _detail ? (eps.count ? [NSString stringWithFormat:@"Danh sách tập (%lu)", (unsigned long)eps.count]
                                            : @"Phim này chưa có tập nào.")
                               : nil;
    _messageLabel.text = _error;
    // Nút Xem: xem tiếp tập trong lịch sử, hoặc tập đầu của bản đang chọn
    NSString *histEp = CBStr(_hist, @"epTitle");
    NSString *play = histEp ? [NSString stringWithFormat:@"▶ Xem tiếp: %@", histEp] : (eps.count > 1 ? @"▶ Xem từ tập đầu" : @"▶ Xem");
    [_playButton setTitle:play forState:UIControlStateNormal];
    _playButton.enabled = _detail && (eps.count || histEp);
    BOOL following = [CBPrefs followOf:CBStr(_detail, @"url") ?: CBStr(_item, @"url") ?: @""] != nil;
    [_followButton setTitle:following ? @"Đang theo dõi" : @"Theo dõi" forState:UIControlStateNormal];
    _followButton.enabled = _detail != nil;
    _descLabel.text = CBStr(_detail, @"description");
    _headerHeight = [self layoutHeader:_cv.bounds.size.width];
    [_cv reloadData];
}

/// Đặt khung các phần của đầu trang theo bề ngang w, trả chiều cao
- (CGFloat)layoutHeader:(CGFloat)w {
    BOOL pad = [CBTheme isPad];
    CGFloat pw = pad ? 170 : 110;
    _poster.frame = CGRectMake(12, 12, pw, ceil(pw * 1.5));
    CGFloat x = 12 + pw + 12, cw = w - x - 12, y = 12;
    _titleLabel.frame = CGRectMake(x, y, cw, [CBTheme heightOf:_titleLabel.text font:_titleLabel.font width:cw]);
    y = CGRectGetMaxY(_titleLabel.frame) + 4;
    _otherLabel.frame = CGRectMake(x, y, cw, [CBTheme heightOf:_otherLabel.text font:_otherLabel.font width:cw]);
    y = CGRectGetMaxY(_otherLabel.frame) + 6;
    CGFloat infoH = [CBTheme heightOf:_infoLabel.text font:_infoLabel.font width:cw];
    CGFloat maxInfo = CGRectGetMaxY(_poster.frame) - y;
    _infoLabel.frame = CGRectMake(x, y, cw, MIN(infoH, MAX(maxInfo, 0)));
    _spinner.center = CGPointMake(x + 14, y + 14);
    y = MAX(CGRectGetMaxY(_poster.frame), CGRectGetMaxY(_infoLabel.frame)) + 14;
    CGSize fs = [_followButton sizeThatFits:CGSizeMake(200, 40)];
    CGFloat fw = MAX(fs.width, 110);
    _followButton.frame = CGRectMake(w - 12 - fw, y, fw, 40);
    _playButton.frame = CGRectMake(12, y, w - 36 - fw, 40);
    y += 52;
    if (_groups) {
        _groups.frame = CGRectMake(12, y, w - 24, 32);
        y += 44;
    }
    if (_messageLabel.text) {
        CGFloat mh = [CBTheme heightOf:_messageLabel.text font:_messageLabel.font width:w - 40];
        _messageLabel.frame = CGRectMake(20, y, w - 40, mh);
        y += mh + 12;
    } else {
        _messageLabel.frame = CGRectZero;
    }
    _countLabel.frame = CGRectMake(12, y, w - 24, _countLabel.text ? 22 : 0);
    y += _countLabel.text ? 30 : 0;
    _header.frame = CGRectMake(0, 0, w, y);
    return y;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat h = [self layoutHeader:_cv.bounds.size.width];
    if (h != _headerHeight) {
        _headerHeight = h;
        [_cv.collectionViewLayout invalidateLayout];
    }
}

#pragma mark - Lưới tập

- (CGSize)epSize {
    CGFloat w = _cv.bounds.size.width - 24;
    NSInteger cols = MAX(4, (NSInteger)floor((w + 8) / ([CBTheme isPad] ? 96 : 72)));
    return CGSizeMake(floor((w - 8 * (cols - 1)) / cols), 40);
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return [self episodes].count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return [self epSize];
}

- (UIEdgeInsets)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l insetForSectionAtIndex:(NSInteger)s {
    return UIEdgeInsetsMake(0, 12, 12, 12);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l referenceSizeForHeaderInSection:(NSInteger)s {
    return CGSizeMake(cv.bounds.size.width, _headerHeight);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l referenceSizeForFooterInSection:(NSInteger)s {
    if (!_descLabel.text) return CGSizeZero;
    return CGSizeMake(cv.bounds.size.width, [CBTheme heightOf:_descLabel.text font:_descLabel.font width:cv.bounds.size.width - 24] + 32);
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)ip {
    BOOL head = [kind isEqualToString:UICollectionElementKindSectionHeader];
    CBHostView *v = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:head ? @"h" : @"f" forIndexPath:ip];
    UIView *content = head ? _header : _descLabel;
    if (content.superview != v) {
        [content removeFromSuperview];
        [v addSubview:content];
    }
    if (!head) _descLabel.frame = CGRectMake(12, 12, v.bounds.size.width - 24, v.bounds.size.height - 24);
    return v;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBEpCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ep" forIndexPath:ip];
    NSDictionary *ep = [self episodes][ip.item];
    NSString *url = CBStr(ep, @"url") ?: @"";
    [cell setTitle:CBStr(ep, @"title") watched:[_watched containsObject:url] current:[url isEqualToString:CBStr(_hist, @"epUrl")]];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *ep = [self episodes][ip.item];
    [self playEpisode:CBStr(ep, @"url") resume:NO];
}

#pragma mark - Thao tác

- (void)groupChanged {
    _group = _groups.selectedSegmentIndex;
    [self relayout];
}

- (void)playEpisode:(NSString *)epUrl resume:(BOOL)resume {
    if (!_detail || !epUrl) return;
    CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:CBStr(_detail, @"url") detail:_detail episode:epUrl
                                                                       resume:resume];
    [self presentViewController:p animated:YES completion:nil];
}

- (void)playTapped {
    NSString *histEp = CBStr(_hist, @"epUrl");
    if (histEp) {
        [self playEpisode:histEp resume:YES];
        return;
    }
    NSArray *eps = [self episodes];
    if (eps.count) [self playEpisode:CBStr(eps[0], @"url") resume:NO];
}

- (void)followTapped {
    if (!_detail) return;
    NSString *url = CBStr(_detail, @"url");
    if ([CBPrefs followOf:url]) [CBPrefs unfollow:url];
    else [CBPrefs follow:_detail];
    [self relayout];
}

@end
