#import "CBDetailViewController.h"
#import "CBCollectionView.h"
#import "CBCore.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBRowCell.h"
#import "CBSheet.h"
#import "CBGlass.h"
#import "CBIcon.h"
#import "CBTheme.h"

#pragma mark - Ô tập

@interface CBEpCell : CBCollectionViewCell
@property (nonatomic, strong) UILabel *label;
- (void)setTitle:(NSString *)title watched:(BOOL)watched current:(BOOL)current;
@end

@implementation CBEpCell {
    UIImageView *_bg;   // nền + viền bo góc: ảnh kéo giãn (không layer.cornerRadius — xem CBTheme imageWithColor:radius:)
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _bg = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_bg];
        _label = [[UILabel alloc] initWithFrame:CGRectInset(self.contentView.bounds, 4, 2)];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [CBTheme medium:14];
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
    // Kiểu iOS 26: viên thuốc; đã xem = xanh nhạt, đang xem dở = viền xanh, còn lại xám
    UIColor *fill = current ? [UIColor colorWithRed:0.25 green:0.79 blue:0.61 alpha:0.14]
                  : watched ? [UIColor colorWithRed:0.17 green:0.69 blue:0.52 alpha:0.13] : [UIColor colorWithWhite:1 alpha:0.08];
    _bg.image = [CBTheme imageWithColor:fill radius:20 border:current ? [CBTheme accent] : nil width:1.5];
    _label.textColor = current ? CBRGB(0x5FDAAE) : watched ? CBRGB(0x8CCDB6) : [CBTheme text];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1;
}
@end

@interface CBHostView : CBCollectionReusableView
@end
@implementation CBHostView
@end

#pragma mark - Trang phim

@interface CBDetailViewController () <CBCollectionViewDataSource, CBCollectionViewDelegate,
                                      UIActionSheetDelegate>
@end

@implementation CBDetailViewController {
    NSDictionary *_item;
    NSDictionary *_detail;
    NSInteger _group;
    NSSet *_watched;
    NSDictionary *_hist;
    NSString *_error;
    CBCollectionView *_cv;
    // Phần đầu (một bản, đặt vào ô phụ đầu lưới)
    UIView *_header;
    CBCoverView *_poster;
    UIImageView *_posterBg;   // nền xám bo góc lúc chưa có ảnh (ảnh kéo giãn — không layer.cornerRadius)
    UIImageView *_backdrop;   // nền đầu trang: ảnh bìa thu nhỏ rồi phóng to (mờ) — máy yếu (CBTheme lite) không có
    UIImageView *_backdropFade;
    UIImage *_backdropFrom;   // ảnh bìa đã làm nền (đổi ảnh thì làm lại)
    UILabel *_titleLabel, *_otherLabel, *_infoLabel, *_countLabel, *_messageLabel;
    UIButton *_playButton, *_followButton;
    // Hàng nút phụ: «Mới nhất: Tập N», «Từ tập đầu» (khi đang xem dở), «⇄ <trang> ▾» (phim có ở nhiều trang — từ trang chủ tổng hợp)
    UIButton *_latestButton, *_firstButton, *_sourceButton;
    NSString *_latestEp;
    UISegmentedControl *_groups;
    UIScrollView *_groupsStrip;
    UIActivityIndicatorView *_spinner;
    CGFloat _headerHeight;
    UILabel *_descLabel;
    // Phần cuối: mô tả + các hàng «phim liên quan» (tải sau khi trang phim đã hiện; nil = chưa xong)
    UIView *_footer;
    NSArray *_related;
    BOOL _relatedLoading;
    // Màn đang trượt vào (chưa viewDidAppear): bản tải mới / hàng liên quan về giữa cú trượt thì để sau — dựng lại lúc đó làm
    // cú trượt giật (iPad mini 1 iOS 8: ~40 khung/s)
    BOOL _appeared, _pendingRelated;
    NSDictionary *_pendingDetail;
    NSMutableArray *_relatedViews;  // [UILabel tên hàng, CBRowCell] cho từng hàng
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
    CBCollectionViewFlowLayout *layout = [[CBCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    layout.minimumInteritemSpacing = 8;
    _cv = [[CBCollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _cv.backgroundColor = [CBTheme bg];
    _cv.alwaysBounceVertical = YES;
    _cv.dataSource = self;
    _cv.delegate = self;
    _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_cv registerClass:[CBEpCell class] forCellWithReuseIdentifier:@"ep"];
    [_cv registerClass:[CBHostView class] forSupplementaryViewOfKind:CBCollectionElementKindSectionHeader withReuseIdentifier:@"h"];
    [_cv registerClass:[CBHostView class] forSupplementaryViewOfKind:CBCollectionElementKindSectionFooter withReuseIdentifier:@"f"];
    [self.view addSubview:_cv];
    [self buildHeader];

    id cached = [CBCore sync:@"site.cachedDetail" args:@{@"url": CBStr(_item, @"url") ?: @""}];
    if (CBIsDict(cached)) [self applyDetail:cached];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Từ trình phát quay về: đánh dấu tập đã xem / nút Xem tiếp. Lần đầu viewDidLoad vừa dựng xong — dựng lại ở đây chỉ làm cú
    // trượt vào bắt đầu chậm hơn
    if (_appeared) [self refreshMarks];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _appeared = YES;
    if (_pendingDetail) {
        NSDictionary *d = _pendingDetail;
        _pendingDetail = nil;
        [self applyDetail:d];
    }
    if (_pendingRelated) {
        _pendingRelated = NO;
        [self buildRelated];
    }
}

- (void)load {
    if (!_detail) [_spinner startAnimating];
    long long t0 = CBNowMs();
    NSString *url = CBStr(_item, @"url") ?: @"";
    CBLog(@"Mở trang phim %@ (%@)%@", CBStr(_item, @"title"), url, _detail ? @" — có bản lưu" : @"");
    [CBCore call:@"site.detail" args:@{@"url": url} done:^(id ok, NSString *err) {
        [self->_spinner stopAnimating];
        CBLog(@"Trang phim %@: %@ sau %lld ms", url,
              CBIsDict(ok) ? [NSString stringWithFormat:@"%ld tập", (long)CBDetailEpisodeCount(ok)] : [@"LỖI " stringByAppendingString:err ?: @"?"],
              CBNowMs() - t0);
        if (CBIsDict(ok)) {
            if (self->_appeared) [self applyDetail:ok];
            else self->_pendingDetail = ok;
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
    // «Có tập mới» tự động của trang chủ: đã mở phim thì thôi (như bản Windows — lõi ghi tập lớn nhất đã thấy)
    if (![CBPrefs privateMode]) [CBCore call:@"home.markSeen" args:@{@"detail": d} done:nil];   // không chờ (lõi ghi dữ liệu)
    // Phim đang theo dõi: vào trang phim thì cập nhật số tập (chưa coi là đã xem tập mới — xem mới tính)
    if ([CBPrefs followOf:CBStr(d, @"url") ?: @""]) {
        [CBPrefs updateFollow:CBStr(d, @"url") count:CBDetailEpisodeCount(d) latest:CBStr(CBDetailLatestEpisode(d), @"title")
                         seen:NO];
    }
    [self refreshMarks];
    if (!_related && !_relatedLoading) [self loadRelated];
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

- (UIButton *)smallButton:(SEL)action {
    UIButton *b = [CBTheme button:@"" primary:NO];
    b.titleLabel.font = [CBTheme medium:[CBTheme isPad] ? 15 : 13];
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.7;
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    b.hidden = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:b];
    return b;
}

- (void)buildHeader {
    _header = [[UIView alloc] init];
    _header.backgroundColor = [CBTheme bg];
    _header.clipsToBounds = YES;
    if (![CBTheme lite]) {
        _backdrop = [[UIImageView alloc] init];
        _backdrop.contentMode = UIViewContentModeScaleAspectFill;
        _backdrop.alpha = 0.85;
        [_header addSubview:_backdrop];
        _backdropFade = [[UIImageView alloc] initWithImage:[self fadeImage]];
        [_header addSubview:_backdropFade];
    }
    _posterBg = [[UIImageView alloc] initWithImage:[CBTheme imageWithColor:[CBTheme surface2] radius:12]];
    [_header addSubview:_posterBg];
    _poster = [[CBCoverView alloc] init];
    _poster.placeholder = _posterBg;
    _poster.contentMode = UIViewContentModeScaleToFill;  // ảnh đã cắt đúng khổ + bo góc sẵn (CBImages … radius:)
    [_header addSubview:_poster];
    _titleLabel = [self label:[CBTheme bold:[CBTheme isPad] ? 26 : 21] color:[CBTheme text]];
    _otherLabel = [self label:[CBTheme font:14] color:CBRGB(0xB8BFCA)];
    _infoLabel = [self label:[CBTheme font:13] color:CBRGB(0xB8BFCA)];
    _countLabel = [self label:[CBTheme bold:17] color:[CBTheme text]];
    _messageLabel = [self label:[CBTheme font:15] color:[CBTheme dim]];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _playButton = [CBTheme button:@"Xem" primary:YES];
    [(CBPillButton *)_playButton setIcon:@"play" size:15];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_playButton];
    // Theo dõi: nút tròn biểu tượng dấu trang (tô kín khi đang theo dõi)
    _followButton = [CBPillButton pill:nil style:CBPillSubtle];
    _followButton.contentEdgeInsets = UIEdgeInsetsZero;
    _followButton.accessibilityLabel = @"Theo dõi";
    [_followButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_followButton];
    _latestButton = [self smallButton:@selector(latestTapped)];
    _firstButton = [self smallButton:@selector(firstTapped)];
    [_firstButton setTitle:@"Từ tập đầu" forState:UIControlStateNormal];
    _sourceButton = [self smallButton:@selector(sourceTapped)];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [_header addSubview:_spinner];
    _descLabel = [[UILabel alloc] init];
    _descLabel.backgroundColor = [UIColor clearColor];
    _descLabel.textColor = [CBTheme dim];
    _descLabel.font = [CBTheme font:14];
    _descLabel.numberOfLines = 0;
    _footer = [[UIView alloc] init];
    _footer.backgroundColor = [CBTheme bg];
    [_footer addSubview:_descLabel];
    _relatedViews = [NSMutableArray array];
}

- (void)relayout {
    NSString *poster = CBStr(_detail, @"poster") ?: CBStr(_item, @"poster");
    CGFloat pw = [CBTheme isPad] ? 170 : 110;   // như layoutHeader:
    [CBImages load:poster size:CGSizeMake(pw, ceil(pw * 1.5)) radius:12 into:_poster];
    [self updateBackdrop];
    _titleLabel.text = CBStr(_detail, @"title") ?: CBStr(_item, @"title");
    _otherLabel.text = CBStr(_detail, @"otherTitle");
    _infoLabel.text = CBStr(_detail, @"info");
    NSArray *groups = CBArr(_detail, @"groups");
    [_groupsStrip removeFromSuperview];
    _groupsStrip = nil;
    _groups = nil;
    if (groups.count > 1) {
        NSMutableArray *names = [NSMutableArray array];
        for (id g in groups) [names addObject:CBStr(g, @"name") ?: @"?"];
        _groups = [[UISegmentedControl alloc] initWithItems:names];
        _groups.segmentedControlStyle = UISegmentedControlStyleBar;
        _groups.selectedSegmentIndex = _group;
        [_groups addTarget:self action:@selector(groupChanged) forControlEvents:UIControlEventValueChanged];
        _groupsStrip = [[UIScrollView alloc] init];
        [_groupsStrip addSubview:_groups];
        [_header addSubview:_groupsStrip];
    }
    NSArray *eps = [self episodes];
    _countLabel.text = _detail ? (eps.count ? [NSString stringWithFormat:@"Danh sách tập (%lu)", (unsigned long)eps.count]
                                            : @"Phim này chưa có tập nào.")
                               : nil;
    _messageLabel.text = _error;
    // Nút Xem: xem tiếp tập trong lịch sử, hoặc tập đầu của bản (mùa) đang chọn. Phim chia mùa ghi kèm mùa.
    BOOL seasons = CBDetailSeasons(_detail);
    NSString *histEp = CBStr(_hist, @"epTitle") ? CBDetailEpisodeLabel(_detail, CBStr(_hist, @"epUrl"), CBStr(_hist, @"epTitle")) : nil;
    NSString *play = histEp ? [NSString stringWithFormat:@"Xem tiếp · %@", histEp] : (eps.count > 1 ? @"Xem từ tập đầu" : @"Xem");
    if (!histEp && seasons && _group < (NSInteger)groups.count) {
        play = [NSString stringWithFormat:@"Xem %@", CBStr(groups[_group], @"name") ?: @"từ tập đầu"];
    }
    [_playButton setTitle:play forState:UIControlStateNormal];
    [(CBPillButton *)_playButton setIcon:@"play" size:15];
    _playButton.enabled = _detail && (eps.count || histEp);
    if (!_detail && _error) {  // tải lỗi: nút Xem thành «Thử lại» (trước phải lùi ra rồi vào lại)
        [_playButton setTitle:@"Thử lại" forState:UIControlStateNormal];
        [(CBPillButton *)_playButton setIcon:@"reload" size:16];
        _playButton.enabled = YES;
    }
    BOOL following = [CBPrefs followOf:CBStr(_detail, @"url") ?: CBStr(_item, @"url") ?: @""] != nil;
    [_followButton setImage:[CBIcon named:@"bookmark" size:20 color:following ? [CBTheme accent] : [CBTheme text] filled:following]
                   forState:UIControlStateNormal];
    _followButton.accessibilityLabel = following ? @"Đang theo dõi — chạm để bỏ" : @"Theo dõi";
    _followButton.enabled = _detail != nil;
    // Đang xem dở phim nhiều tập: thêm «Mới nhất» (tập cuối của bản đang chọn) và «Từ tập đầu» (như bản Windows / iPad)
    // Phim chia mùa: «Mới nhất» = tập cuối của mùa cuối, «Từ tập đầu» = Mùa 1, Tập 1 (không theo mùa đang chọn)
    NSString *histUrl = CBStr(_hist, @"epUrl");
    NSDictionary *last = seasons ? CBDetailLatestEpisode(_detail) : eps.lastObject;
    NSInteger total = seasons ? CBDetailEpisodeCount(_detail) : (NSInteger)eps.count;
    BOOL showLatest = histUrl && total > 1 && CBStr(last, @"url") && ![CBStr(last, @"url") isEqualToString:histUrl];
    _latestEp = showLatest ? CBStr(last, @"url") : nil;
    NSString *lastLabel = seasons ? CBDetailEpisodeLabel(_detail, CBStr(last, @"url"), CBStr(last, @"title")) : CBStr(last, @"title");
    [_latestButton setTitle:[NSString stringWithFormat:@"Mới nhất: %@", lastLabel ?: @""] forState:UIControlStateNormal];
    _latestButton.hidden = !showLatest;
    NSString *firstUrl = CBStr([self firstEpisode], @"url");
    _firstButton.hidden = !(histUrl && total > 1 && firstUrl && ![firstUrl isEqualToString:histUrl]);
    NSArray *links = CBArr(_item, @"links");
    _sourceButton.hidden = links.count < 2;
    [_sourceButton setTitle:[self hostOf:CBStr(_detail, @"url") ?: CBStr(_item, @"url")] forState:UIControlStateNormal];
    [(CBPillButton *)_sourceButton setIcon:@"swap" size:15];
    _descLabel.text = CBStr(_detail, @"description");
    _headerHeight = [self layoutHeader:_cv.bounds.size.width];
    [_cv reloadData];
}

/// Đặt khung các phần của đầu trang theo bề ngang w, trả chiều cao
- (CGFloat)layoutHeader:(CGFloat)w {
    BOOL pad = [CBTheme isPad];
    CGFloat pw = pad ? 170 : 110, m = pad ? 20 : 16;
    _poster.frame = CGRectMake(m, 14, pw, ceil(pw * 1.5));
    _posterBg.frame = _poster.frame;
    CGFloat x = m + pw + 16, cw = w - x - m, y = 18;
    _titleLabel.frame = CGRectMake(x, y, cw, [CBTheme heightOf:_titleLabel.text font:_titleLabel.font width:cw]);
    y = CGRectGetMaxY(_titleLabel.frame) + 4;
    _otherLabel.frame = CGRectMake(x, y, cw, [CBTheme heightOf:_otherLabel.text font:_otherLabel.font width:cw]);
    y = CGRectGetMaxY(_otherLabel.frame) + 6;
    CGFloat infoH = [CBTheme heightOf:_infoLabel.text font:_infoLabel.font width:cw];
    CGFloat maxInfo = CGRectGetMaxY(_poster.frame) - y;
    _infoLabel.frame = CGRectMake(x, y, cw, MIN(infoH, MAX(maxInfo, 0)));
    _spinner.center = CGPointMake(x + 14, y + 14);
    // Nền mờ đầu trang phủ tới dưới ảnh bìa
    CGFloat backH = CGRectGetMaxY(_poster.frame) + 40;
    _backdrop.frame = CGRectMake(0, 0, w, backH);
    _backdropFade.frame = _backdrop.frame;
    y = MAX(CGRectGetMaxY(_poster.frame), CGRectGetMaxY(_infoLabel.frame)) + 18;
    // Nút chính viên thuốc + nút tròn «Theo dõi» (iPad: nút chính không dài quá 360)
    CGFloat bh = 46;
    _followButton.frame = CGRectMake(w - m - bh, y, bh, bh);
    CGFloat pw2 = w - m * 2 - bh - 10;
    if (pad) {
        pw2 = MIN(pw2, 360);
        _followButton.frame = CGRectMake(m + pw2 + 10, y, bh, bh);
    }
    _playButton.frame = CGRectMake(m, y, pw2, bh);
    y += bh + 10;
    NSMutableArray *extra = [NSMutableArray array];
    for (UIButton *b in @[_latestButton, _firstButton, _sourceButton]) if (!b.hidden) [extra addObject:b];
    if (extra.count) {
        CGFloat gap = 10, bw = floor((w - m * 2 - gap * (extra.count - 1)) / extra.count);
        if (pad) bw = MIN(bw, 200);
        for (NSUInteger i = 0; i < extra.count; i++) [extra[i] setFrame:CGRectMake(m + i * (bw + gap), y, bw, 36)];
        y += 48;
    }
    if (_groups) {
        [CBTheme layoutSegments:_groups inStrip:_groupsStrip frame:CGRectMake(m, y, w - m * 2, 34)];
        y += 46;
    }
    if (_messageLabel.text) {
        CGFloat mh = [CBTheme heightOf:_messageLabel.text font:_messageLabel.font width:w - 40];
        _messageLabel.frame = CGRectMake(20, y, w - 40, mh);
        y += mh + 12;
    } else {
        _messageLabel.frame = CGRectZero;
    }
    _countLabel.frame = CGRectMake(m, y, w - m * 2, _countLabel.text ? 22 : 0);
    y += _countLabel.text ? 32 : 0;
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

#pragma mark - Nền mờ đầu trang

/// Dải phủ màu nền: trong suốt phía trên → đặc ở mép dưới (nền mờ tan vào trang)
- (UIImage *)fadeImage {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [[CBTheme bg] getRed:&r green:&g blue:&b alpha:&a];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 64), NO, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {r, g, b, 0.25, r, g, b, 0.62, r, g, b, 1};
    CGFloat locs[] = {0, 0.55, 1};
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, locs, 3);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), grad, CGPointZero, CGPointMake(0, 64), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

/// Ảnh bìa đã về: thu về 12 × 18 điểm ảnh (gộp màu) — UIImageView phóng to bằng nội suy tuyến tính thành nền mờ. Một lần mỗi ảnh,
/// rẻ hơn làm mờ thật (vImage) nhiều; máy yếu bỏ hẳn
- (void)updateBackdrop {
    if (!_backdrop) return;
    UIImage *src = _poster.image;
    if (!src || src == _backdropFrom) {
        if (!src) {
            // ảnh bìa nạp không đồng bộ — hỏi lại sau
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->_poster.image && self->_poster.image != self->_backdropFrom) [self updateBackdrop];
            });
        }
        return;
    }
    _backdropFrom = src;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(12, 18), YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [src drawInRect:CGRectMake(-1, -1, 14, 20)];   // bỏ mép bo góc
    UIImage *tiny = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    _backdrop.image = tiny;
    _backdrop.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{ self->_backdrop.alpha = 0.85; }];
}

#pragma mark - Lưới tập

- (CGSize)epSize {
    CGFloat m = [CBTheme isPad] ? 20 : 16, w = _cv.bounds.size.width - m * 2;
    NSInteger cols = MAX(4, (NSInteger)floor((w + 8) / ([CBTheme isPad] ? 96 : 66)));
    return CGSizeMake(floor((w - 8 * (cols - 1)) / cols), 40);
}

- (NSInteger)collectionView:(CBCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return [self episodes].count;
}

- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return [self epSize];
}

- (UIEdgeInsets)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)l insetForSectionAtIndex:(NSInteger)s {
    CGFloat m = [CBTheme isPad] ? 20 : 16;
    return UIEdgeInsetsMake(0, m, 16, m);
}

- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)l referenceSizeForHeaderInSection:(NSInteger)s {
    return CGSizeMake(cv.bounds.size.width, _headerHeight);
}

- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)l referenceSizeForFooterInSection:(NSInteger)s {
    CGFloat h = [self layoutFooter:cv.bounds.size.width];
    return h > 0 ? CGSizeMake(cv.bounds.size.width, h) : CGSizeZero;
}

- (CBCollectionReusableView *)collectionView:(CBCollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)ip {
    BOOL head = [kind isEqualToString:CBCollectionElementKindSectionHeader];
    CBHostView *v = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:head ? @"h" : @"f" forIndexPath:ip];
    UIView *content = head ? _header : _footer;
    if (content.superview != v) {
        [content removeFromSuperview];
        [v addSubview:content];
    }
    if (!head) [self layoutFooter:v.bounds.size.width];
    return v;
}

- (CBCollectionViewCell *)collectionView:(CBCollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBEpCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ep" forIndexPath:ip];
    NSDictionary *ep = [self episodes][ip.item];
    NSString *url = CBStr(ep, @"url") ?: @"";
    [cell setTitle:CBStr(ep, @"title") watched:[_watched containsObject:url] current:[url isEqualToString:CBStr(_hist, @"epUrl")]];
    return cell;
}

- (void)collectionView:(CBCollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *ep = [self episodes][ip.item];
    [self playEpisode:CBStr(ep, @"url") resume:NO];
}

#pragma mark - Phim liên quan

- (void)loadRelated {
    NSString *title = CBStr(_detail, @"title") ?: CBStr(_item, @"title");
    NSString *url = CBStr(_detail, @"url") ?: CBStr(_item, @"url");
    if (!title.length || !url.length) return;
    _relatedLoading = YES;
    long long t0 = CBNowMs();
    [CBCore call:@"related.load" args:@{@"title": title, @"url": url} done:^(id ok, NSString *err) {
        self->_relatedLoading = NO;
        NSArray *rows = CBIsArr(ok) ? ok : @[];
        CBLog(@"Phim liên quan «%@»: %lu hàng sau %lld ms%@", title, (unsigned long)rows.count, CBNowMs() - t0,
              err ? [@" — LỖI " stringByAppendingString:err] : @"");
        self->_related = rows;
        if (self->_appeared) [self buildRelated];
        else self->_pendingRelated = YES;
    }];
}

/// Phần tử ô phim cho hàng liên quan: phim ở trang khác gắn nhãn tên trang (như «kkphim» ở trang chủ)
- (NSDictionary *)relatedItem:(NSDictionary *)film {
    NSMutableDictionary *item = [CBItemFromFilm(film) mutableCopy];
    NSString *mine = CBHostOf(CBStr(_detail, @"url") ?: CBStr(_item, @"url") ?: @"");
    NSString *host = CBHostOf(CBStr(film, @"url") ?: @"");
    if (host && mine && ![host isEqualToString:mine]) {
        id tag = [CBCore sync:@"site.tag" args:@{@"host": host, @"sites": [CBPrefs sites] ?: @[]}];
        if (CBIsStr(tag) && [tag length]) {
            if (!item[@"sub"] && item[@"badge"]) item[@"sub"] = item[@"badge"];
            item[@"badge"] = tag;
        }
    }
    return item;
}

- (void)buildRelated {
    for (NSArray *pair in _relatedViews) for (UIView *v in pair) [v removeFromSuperview];
    [_relatedViews removeAllObjects];
    __weak CBDetailViewController *weakSelf = self;
    for (NSDictionary *row in _related) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *f in CBArr(row, @"films")) if (CBIsDict(f)) [items addObject:[self relatedItem:f]];
        if (!items.count) continue;
        UILabel *t = [[UILabel alloc] init];
        t.backgroundColor = [UIColor clearColor];
        t.textColor = [CBTheme text];
        t.font = [CBTheme bold:[CBTheme isPad] ? 22 : 19];
        t.text = CBStr(row, @"title");
        CBRowCell *cell = [[CBRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.onSelect = ^(NSDictionary *item) {
            CBDetailViewController *d = [[CBDetailViewController alloc] initWithItem:item];
            [weakSelf.navigationController pushViewController:d animated:YES];
        };
        [_footer addSubview:t];
        [_footer addSubview:cell];
        [_relatedViews addObject:@[t, cell]];
        cell.frame = CGRectMake(0, 0, _cv.bounds.size.width, [CBRowCell height]);
        [cell layoutIfNeeded];
        [cell setItems:items offset:0];
    }
    [_cv.collectionViewLayout invalidateLayout];
}

/// Đặt khung mô tả + hàng liên quan theo bề ngang w, trả chiều cao phần cuối (0 = không có gì)
- (CGFloat)layoutFooter:(CGFloat)w {
    CGFloat y = 0;
    if (_descLabel.text.length) {
        CGFloat m = [CBTheme isPad] ? 20 : 16;
        CGFloat dh = [CBTheme heightOf:_descLabel.text font:_descLabel.font width:w - m * 2];
        _descLabel.frame = CGRectMake(m, 12, w - m * 2, dh);
        y = 12 + dh + 20;
    } else {
        _descLabel.frame = CGRectZero;
    }
    for (NSArray *pair in _relatedViews) {
        [pair[0] setFrame:CGRectMake([CBTheme isPad] ? 20 : 16, y, w - 32, 26)];
        y += 32;
        CGRect f = CGRectMake(0, y, w, [CBRowCell height]);
        if (!CGRectEqualToRect([pair[1] frame], f)) [pair[1] setFrame:f];
        y += [CBRowCell height] + 16;
    }
    _footer.frame = CGRectMake(0, 0, w, y);
    return y;
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
    if (!_detail) {  // «↻ Thử lại» sau khi tải lỗi
        _error = nil;
        [self relayout];
        [_spinner startAnimating];
        [self load];
        return;
    }
    NSString *histEp = CBStr(_hist, @"epUrl");
    if (histEp) {
        [self playEpisode:histEp resume:YES];
        return;
    }
    NSArray *eps = [self episodes];
    if (eps.count) [self playEpisode:CBStr(eps[0], @"url") resume:NO];
}

- (NSString *)hostOf:(NSString *)url {
    NSString *h = CBHostOf(url ?: @"") ?: @"";
    return [h hasPrefix:@"www."] ? [h substringFromIndex:4] : h;
}

- (void)latestTapped {
    if (_latestEp) [self playEpisode:_latestEp resume:YES];
}

/// Tập đầu: của bản đang chọn; phim chia mùa thì tập 1 của mùa đầu tiên
- (NSDictionary *)firstEpisode {
    NSArray *eps = [self episodes];
    if (CBDetailSeasons(_detail)) {
        for (id g in CBArr(_detail, @"groups") ?: @[]) {
            id e = CBArr(g, @"episodes").firstObject;
            if (CBIsDict(e)) return e;
        }
    }
    return eps.count && CBIsDict(eps[0]) ? eps[0] : nil;
}

- (void)firstTapped {
    NSString *url = CBStr([self firstEpisode], @"url");
    if (url) [self playEpisode:url resume:NO];
}

/// Phim có ở nhiều trang (thẻ trang chủ tổng hợp mang «links» của lõi): chọn trang khác → mở trang phim đó thay màn này
- (void)sourceTapped {
    NSArray *links = CBArr(_item, @"links");
    if (links.count < 2) return;
    NSString *cur = [self hostOf:CBStr(_detail, @"url") ?: CBStr(_item, @"url")];
    UIActionSheet *sheet = [[CBSheet alloc] initWithTitle:@"Xem ở trang" delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    for (id l in links) {
        NSString *host = [self hostOf:CBStr(l, @"url")];
        NSString *badge = CBStr(l, @"badge");
        NSString *label = badge.length ? [NSString stringWithFormat:@"%@ · %@", host, badge] : host;
        [sheet addButtonWithTitle:[host isEqualToString:cur] ? [@"✓ " stringByAppendingString:label] : label];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Huỷ"];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    NSArray *links = CBArr(_item, @"links");
    if (index == sheet.cancelButtonIndex || index < 0 || index >= (NSInteger)links.count) return;
    NSDictionary *l = links[index];
    if ([[self hostOf:CBStr(l, @"url")] isEqualToString:[self hostOf:CBStr(_detail, @"url") ?: CBStr(_item, @"url")]]) return;
    NSMutableDictionary *item = [CBItemFromFilm(l) mutableCopy];
    item[@"links"] = links;
    CBLog(@"Đổi nguồn phim %@ → %@", CBStr(_item, @"title"), CBStr(l, @"url"));
    CBDetailViewController *vc = [[CBDetailViewController alloc] initWithItem:item];
    NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
    if (stack.lastObject == self) [stack removeLastObject];
    [stack addObject:vc];
    [self.navigationController setViewControllers:stack animated:NO];
}

- (void)followTapped {
    if (!_detail) return;
    NSString *url = CBStr(_detail, @"url");
    if ([CBPrefs followOf:url]) [CBPrefs unfollow:url];
    else [CBPrefs follow:_detail];
    [self relayout];
}

@end
