#import "CBTVViewController.h"
#import "CBImages.h"
#import "CBIPTV.h"
#import "CBJSON.h"
#import "CBLivePlayerViewController.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBTVGuideViewController.h"
#import "CBTVSettingsViewController.h"
#import "CBTheme.h"
#import <objc/runtime.h>

#pragma mark - Ô kênh

@implementation CBChannelCell {
    UIView *_logoBox, *_track, *_fill;
    UIImageView *_logo;
    UILabel *_abbr, *_num, *_name, *_prog, *_time, *_next, *_live;
    UIButton *_star;
    BOOL _compact;
    NSString *_logoUrl;
}

+ (CGSize)compactSize {
    return [CBTheme isPad] ? CGSizeMake(174, 158) : CGSizeMake(146, 140);
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.font = font;
    l.textColor = color;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:l];
    return l;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 10;
        self.contentView.clipsToBounds = YES;
        _logoBox = [[UIView alloc] init];
        _logoBox.backgroundColor = CBRGB(0x262B32);
        _logoBox.layer.cornerRadius = 6;
        _logoBox.clipsToBounds = YES;
        [self.contentView addSubview:_logoBox];
        _abbr = [[UILabel alloc] init];
        _abbr.backgroundColor = [UIColor clearColor];
        _abbr.textColor = [CBTheme text];
        _abbr.textAlignment = NSTextAlignmentCenter;
        _abbr.adjustsFontSizeToFitWidth = YES;
        _abbr.minimumScaleFactor = 0.5;
        [_logoBox addSubview:_abbr];
        _logo = [[UIImageView alloc] init];
        _logo.contentMode = UIViewContentModeScaleAspectFit;
        [_logoBox addSubview:_logo];
        _live = [[UILabel alloc] init];
        _live.backgroundColor = CBRGB(0xD93A3F);
        _live.textColor = [UIColor whiteColor];
        _live.font = [CBTheme bold:9];
        _live.textAlignment = NSTextAlignmentCenter;
        _live.text = @"TRỰC TIẾP";
        _live.layer.cornerRadius = 3;
        _live.clipsToBounds = YES;
        [_logoBox addSubview:_live];
        _num = [self label:[CBTheme font:12] color:CBRGB(0x8D959E)];
        _name = [self label:[CBTheme bold:15] color:[CBTheme text]];
        _prog = [self label:[CBTheme font:14] color:[CBTheme text]];
        _time = [self label:[CBTheme font:12] color:[CBTheme dim]];
        _time.textAlignment = NSTextAlignmentRight;
        _next = [self label:[CBTheme font:12] color:CBRGB(0x8D959E)];
        _track = [[UIView alloc] init];
        _track.backgroundColor = CBRGB(0x2B3036);
        _fill = [[UIView alloc] init];
        _fill.backgroundColor = [CBTheme brand];
        [_track addSubview:_fill];
        [self.contentView addSubview:_track];
        _star = [UIButton buttonWithType:UIButtonTypeCustom];
        _star.titleLabel.font = [CBTheme font:20];
        [_star setTitle:@"★" forState:UIControlStateNormal];
        [_star addTarget:self action:@selector(starTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_star];
    }
    return self;
}

- (void)starTapped {
    if (self.onStar) self.onStar();
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.backgroundColor = highlighted ? CBRGB(0x2A3037) : (_compact ? [UIColor clearColor] : CBRGB(0x1A1D22));
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [CBImages cancel:_logo];
    _logo.image = nil;
    _logoUrl = nil;
}

- (void)setChannel:(NSDictionary *)c compact:(BOOL)compact {
    _compact = compact;
    self.contentView.backgroundColor = compact ? [UIColor clearColor] : CBRGB(0x1A1D22);
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *p = [CBIPTV nowFor:c at:now], *n = [CBIPTV nextFor:c at:now];
    NSString *bad = [CBIPTV channelBadReason:c];
    _abbr.text = CBStr(c, @"n");
    _num.text = CBStr(c, @"num");
    _name.text = CBStr(c, @"n");
    BOOL fav = [CBIPTV isFavorite:c];
    [_star setTitleColor:fav ? [CBTheme focus] : CBRGB(0x4A5058) forState:UIControlStateNormal];
    double s = CBNum(p, @"s", 0), e = CBNum(p, @"e", 0);
    double f = p && e > s ? MAX(0, MIN(1, (now - s) / (e - s))) : 0;
    // Kênh trận đấu (danh sách thể thao): dòng trạng thái trận thay cho lịch phát sóng
    CBMatchState ms = [CBIPTV matchState:c at:now];
    NSString *match = [CBIPTV matchLine:c at:now];
    _track.hidden = !(p || ms == CBMatchLive) || bad;
    _fill.frame = CGRectMake(0, 0, 0, 4);
    if (bad) {
        _prog.text = @"Máy này không phát được";
        _prog.textColor = CBRGB(0xF0B44C);
        _next.text = bad;
        _time.text = nil;
    } else if (match) {
        double kick = CBNum(c, @"kick", 0);
        _prog.text = match;
        _prog.textColor = ms == CBMatchLive ? CBRGB(0xFF6166) : (ms == CBMatchSoon ? [CBTheme focus] : (ms == CBMatchOver ? [CBTheme dim] : [CBTheme text]));
        _time.text = nil;
        NSString *g = CBStr(c, @"g") ?: @"";
        _next.text = [CBIPTV hasKickReminder:c] ? [NSString stringWithFormat:@"🔔 Nhắc lúc bóng lăn · %@", g] : g;
        if (ms == CBMatchLive) f = MAX(0, MIN(1, (now - kick) / (CBNum(c, @"dur", 150) * 60)));
    } else {
        _prog.textColor = [CBTheme text];
        _prog.text = p ? CBStr(p, @"t") : (compact ? CBStr(c, @"n") : CBStr(c, @"g"));
        _time.text = p ? [NSString stringWithFormat:@"%@–%@", [CBIPTV clock:s], [CBIPTV clock:e]] : nil;
        _next.text = n ? [NSString stringWithFormat:@"Tiếp: %@ %@", [CBIPTV clock:CBNum(n, @"s", 0)], CBStr(n, @"t")] : nil;
    }
    if (compact && match && !bad) {
        _prog.text = CBStr(c, @"n");
        _prog.textColor = [CBTheme text];
        _next.text = match;
    } else if (compact) {
        _next.text = p ? [NSString stringWithFormat:@"%@ · %@", CBStr(c, @"n"), _time.text] : CBStr(c, @"g");
    }
    self.contentView.alpha = bad ? 0.55 : (ms == CBMatchOver ? 0.7 : 1);
    _live.hidden = !compact;
    _num.hidden = _name.hidden = _star.hidden = _time.hidden = compact;
    NSString *logo = CBStr(c, @"logo");
    if (logo && ![logo isEqualToString:_logoUrl]) {
        _logoUrl = logo;
        _logo.image = nil;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        [CBImages load:logo size:_logo.bounds.size into:_logo];
    } else if (!logo) {
        _logo.image = nil;
    }
    _fill.tag = (NSInteger)(f * 1000);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (_compact) {
        CGFloat lh = w * 0.56;
        _logoBox.frame = CGRectMake(0, 0, w, lh);
        _abbr.font = [CBTheme bold:22];
        _abbr.frame = CGRectInset(_logoBox.bounds, 8, 8);
        _logo.frame = CGRectInset(_logoBox.bounds, 14, 12);
        _live.frame = CGRectMake(6, 6, 58, 15);
        _track.frame = CGRectMake(0, lh + 6, w, 4);
        _prog.font = [CBTheme bold:14];
        _prog.frame = CGRectMake(0, lh + 14, w, 18);
        _next.frame = CGRectMake(0, lh + 33, w, 16);
    } else {
        _logoBox.frame = CGRectMake(10, 10, 62, 42);
        _abbr.font = [CBTheme bold:13];
        _abbr.frame = CGRectInset(_logoBox.bounds, 3, 3);
        _logo.frame = CGRectInset(_logoBox.bounds, 3, 3);
        _num.frame = CGRectMake(82, 10, w - 124, 16);
        _name.frame = CGRectMake(82, 26, w - 124, 20);
        _star.frame = CGRectMake(w - 40, 8, 34, 34);
        _prog.font = [CBTheme font:14];
        _prog.frame = CGRectMake(10, 60, w - 20, 18);
        CGFloat tw = _time.text ? 84 : 0;
        _time.frame = CGRectMake(w - 10 - tw, 79, tw, 14);
        _track.frame = CGRectMake(10, 84, w - 20 - tw - (tw ? 8 : 0), 4);
        _next.frame = CGRectMake(10, _track.hidden && !_time.text ? 80 : 94, w - 20, 16);
    }
    _fill.frame = CGRectMake(0, 0, _track.bounds.size.width * _fill.tag / 1000.0, 4);
}

@end

#pragma mark - Hàng «Kênh vừa xem»

@interface CBTVRowCell () <CBCollectionViewDataSource, CBCollectionViewDelegate>
@end

@implementation CBTVRowCell {
    CBCollectionView *_cv;
    NSArray *_channels;
}

+ (CGFloat)height {
    return [CBChannelCell compactSize].height + 6;
}

- (void)dealloc {
    _cv.delegate = nil;
    _cv.dataSource = nil;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [CBTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        CBCollectionViewFlowLayout *layout = [[CBCollectionViewFlowLayout alloc] init];
        layout.scrollDirection = CBCollectionViewScrollDirectionHorizontal;
        layout.itemSize = [CBChannelCell compactSize];
        layout.minimumLineSpacing = 12;
        layout.sectionInset = UIEdgeInsetsMake(0, 12, 0, 12);
        _cv = [[CBCollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:layout];
        _cv.backgroundColor = [CBTheme bg];
        _cv.showsHorizontalScrollIndicator = NO;
        _cv.scrollsToTop = NO;
        _cv.dataSource = self;
        _cv.delegate = self;
        _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_cv registerClass:[CBChannelCell class] forCellWithReuseIdentifier:@"ch"];
        [self.contentView addSubview:_cv];
    }
    return self;
}

- (void)setChannels:(NSArray *)channels {
    _channels = channels;
    [_cv reloadData];
}

- (NSInteger)collectionView:(CBCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return _channels.count;
}

- (CBCollectionViewCell *)collectionView:(CBCollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBChannelCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ch" forIndexPath:ip];
    [cell setChannel:_channels[ip.item] compact:YES];
    return cell;
}

- (void)collectionView:(CBCollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.onSelect) self.onSelect(ip.item);
}

@end

#pragma mark - Màn Truyền hình

@interface CBTVViewController () <CBCollectionViewDataSource, CBCollectionViewDelegate, UISearchBarDelegate, UIActionSheetDelegate>
@end

@implementation CBTVViewController {
    NSArray *_all, *_visible, *_groups;
    NSString *_group;     // «*fav», «*all» hoặc tên nhóm
    NSString *_query;
    UILabel *_info, *_message;
    UIButton *_changeButton, *_addButton;
    UIScrollView *_chips;
    UISearchBar *_search;
    CBCollectionView *_cv;
    UIActivityIndicatorView *_spinner;
    NSTimer *_timer;
    NSDictionary *_sheetChannel;
    BOOL _favsChosen, _appeared;
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = @"Truyền hình";
        _group = @"*all";
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    _cv.delegate = nil;   // iOS 5 / 6: delegate của UIScrollView không tự về nil
    _cv.dataSource = nil;
    _search.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cài đặt" style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(openSettings)];
    _info = [[UILabel alloc] init];
    _info.backgroundColor = [UIColor clearColor];
    _info.textColor = [CBTheme dim];
    _info.font = [CBTheme font:13];
    _info.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:_info];
    _changeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_changeButton setTitle:@"Đổi danh sách ›" forState:UIControlStateNormal];
    [_changeButton setTitleColor:[CBTheme brand] forState:UIControlStateNormal];
    [_changeButton setTitleColor:[CBTheme dim] forState:UIControlStateHighlighted];
    _changeButton.titleLabel.font = [CBTheme bold:13];
    _changeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [_changeButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_changeButton];
    _chips = [[UIScrollView alloc] init];
    _chips.showsHorizontalScrollIndicator = NO;
    _chips.scrollsToTop = NO;
    [self.view addSubview:_chips];
    _search = [[UISearchBar alloc] init];
    _search.placeholder = @"Tìm kênh hoặc gõ số kênh";
    _search.delegate = self;
    _search.tintColor = [CBTheme surface];
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:_search];

    CBCollectionViewFlowLayout *layout = [[CBCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(4, 12, 20, 12);
    _cv = [[CBCollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _cv.backgroundColor = [CBTheme bg];
    _cv.alwaysBounceVertical = YES;
    _cv.dataSource = self;
    _cv.delegate = self;
    [_cv registerClass:[CBChannelCell class] forCellWithReuseIdentifier:@"ch"];
    [_cv addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    [self.view addSubview:_cv];

    _message = [CBTheme messageLabel];
    [self.view addSubview:_message];
    _addButton = [CBTheme button:@"+ Thêm danh sách kênh" primary:YES];
    [_addButton addTarget:self action:@selector(addList) forControlEvents:UIControlEventTouchUpInside];
    _addButton.hidden = YES;
    [self.view addSubview:_addButton];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:CBIPTVChangedNotification object:nil];
    _timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tickGuide) userInfo:nil repeats:YES];
    [self rebuild];
    if ([CBIPTV activeList]) [CBIPTV refresh:NO done:^(NSString *err) { if (err) [CBTheme toast:err]; }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];  // danh sách / người xem có thể vừa đổi (Cài đặt › Truyền hình)
    // Quay lại màn (xem xong kênh…): danh sách thể thao cũ quá 30 phút thì tải lại — trận / link mới thêm liên tục
    if (_appeared && [CBIPTV activeList] && ![CBIPTV loading]) [CBIPTV refresh:NO done:nil];
    _appeared = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) [_timer invalidate];
}

- (void)tickGuide {
    for (CBChannelCell *c in _cv.visibleCells) {
        NSIndexPath *ip = [_cv indexPathForItemAtPoint:c.center];
        if (ip && ip.item < (NSInteger)_visible.count) [c setChannel:_visible[ip.item] compact:NO];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    BOOL hasList = [CBIPTV activeList] != nil;
    _changeButton.frame = CGRectMake(w - 132, 4, 120, 26);
    _info.frame = CGRectMake(12, 4, w - 150, 26);
    CGFloat y = 32;
    _chips.frame = CGRectMake(0, y, w, hasList ? 48 : 0);
    y += _chips.frame.size.height;
    _search.frame = CGRectMake(0, y, w, hasList ? 44 : 0);
    _search.hidden = !hasList;
    y += _search.frame.size.height;
    _cv.frame = CGRectMake(0, y, w, h - y);
    [_cv.collectionViewLayout invalidateLayout];
    _message.frame = CGRectMake(24, y + 30, w - 48, 120);
    CGSize as = [_addButton sizeThatFits:CGSizeMake(300, 44)];
    _addButton.frame = CGRectMake((w - as.width - 40) / 2, y + 160, as.width + 40, 44);
    _spinner.center = CGPointMake(w / 2, y + 20);
}

#pragma mark - Dữ liệu

- (void)rebuild {
    NSDictionary *list = [CBIPTV activeList];
    NSArray *channels = [CBIPTV channels];
    BOOL kids = [CBPrefs kids];
    if (kids && channels) channels = [CBIPTV kidsFilter:channels];
    _all = channels ?: @[];
    _groups = [CBIPTV groupsOf:_all];
    // Đổi danh sách: nhóm đang chọn không còn thì về «Tất cả»
    if (![_group hasPrefix:@"*"] && ![[_groups valueForKey:@"name"] containsObject:_group]) _group = @"*all";
    // Lần đầu vào: có kênh yêu thích thì mở sẵn nhóm «★ Yêu thích»
    if (!_favsChosen && _all.count) {
        _favsChosen = YES;
        if ([self favorites].count) _group = @"*fav";
    }
    [self filter];
    [self buildChips];
    NSString *when = @"";
    if (CBNum(list, @"updated", 0) > 0) when = [@" · cập nhật " stringByAppendingString:[CBIPTV clock:CBNum(list, @"updated", 0) / 1000]];
    if (!list) {
        _info.text = nil;
    } else if ([CBIPTV status]) {
        _info.text = [NSString stringWithFormat:@"%@ · %@", CBStr(list, @"name"), [CBIPTV status]];
    } else {
        _info.text = [NSString stringWithFormat:@"%@ · %lu kênh%@%@", CBStr(list, @"name"), (unsigned long)_all.count, when,
                                                kids ? @" · hồ sơ trẻ em: kênh thiếu nhi" : @""];
    }
    _changeButton.hidden = !list;
    _addButton.hidden = list != nil;
    if (!list) {
        _message.text = @"Chưa có danh sách kênh.\nApp không kèm sẵn kênh: thêm địa chỉ danh sách M3U / M3U8 mà anh có quyền xem.";
        _message.hidden = NO;
    } else if (!channels && [CBIPTV loading]) {
        _message.text = @"Đang tải danh sách kênh…";
        _message.hidden = NO;
    } else if (!channels) {
        NSString *err = CBStr(list, @"err");
        _message.text = err ? [NSString stringWithFormat:@"Chưa tải được danh sách «%@».\n%@", CBStr(list, @"name"), err]
                            : @"Chưa tải danh sách kênh.";
        _message.hidden = NO;
    } else if (!_visible.count) {
        _message.text = _query.length ? @"Không có kênh nào khớp." :
            ([_group isEqualToString:@"*fav"] ? @"Chưa có kênh yêu thích — chạm ★ trên ô kênh để thêm." :
             (kids ? @"Danh sách này không có kênh thiếu nhi." : @"Nhóm này không có kênh."));
        _message.hidden = NO;
    } else {
        _message.hidden = YES;
    }
    if ([CBIPTV loading] && !channels) [_spinner startAnimating];
    else [_spinner stopAnimating];
    [_cv reloadData];
    [self.view setNeedsLayout];
}

- (NSArray *)favorites {
    NSSet *keys = [NSSet setWithArray:[CBIPTV favoriteKeys]];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in _all) if ([keys containsObject:CBStr(c, @"k")]) [out addObject:c];
    return out;
}

- (void)filter {
    NSArray *base;
    if ([_group isEqualToString:@"*fav"]) base = [self favorites];
    else if ([_group isEqualToString:@"*all"]) base = _all;
    else {
        NSMutableArray *g = [NSMutableArray array];
        for (NSDictionary *c in _all) if ([CBStr(c, @"g") isEqualToString:_group]) [g addObject:c];
        base = g;
    }
    BOOL hide = [CBIPTV hideBad];
    NSString *q = [CBIPTV norm:_query ?: @""];
    NSString *digits = [[_query ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] copy];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in base) {
        if (hide && [CBIPTV channelBadReason:c]) continue;
        if (q.length && [CBStr(c, @"k") rangeOfString:q].location == NSNotFound && ![CBStr(c, @"num") isEqualToString:digits]) continue;
        [out addObject:c];
    }
    // Danh sách thể thao: trận đang đá lên đầu, rồi trận sắp đá theo giờ, trận đã xong xuống cuối
    _visible = [CBIPTV sortByMatch:out at:[[NSDate date] timeIntervalSince1970]];
}

- (NSArray *)visibleChannels {
    return _visible;
}

- (void)buildChips {
    for (UIView *v in _chips.subviews) [v removeFromSuperview];
    NSMutableArray *chips = [NSMutableArray array];
    [chips addObject:@{@"id": @"*fav", @"title": [NSString stringWithFormat:@"★ Yêu thích  %lu", (unsigned long)[self favorites].count]}];
    [chips addObject:@{@"id": @"*all", @"title": [NSString stringWithFormat:@"Tất cả  %lu", (unsigned long)_all.count]}];
    for (NSDictionary *g in _groups) {
        [chips addObject:@{@"id": CBStr(g, @"name"), @"title": [NSString stringWithFormat:@"%@  %@", CBStr(g, @"name"), g[@"count"]]}];
    }
    CGFloat x = 12, h = 34;
    UIFont *font = [CBTheme font:[CBTheme isPad] ? 15 : 14];
    UIButton *selected = nil;
    for (NSUInteger i = 0; i < chips.count; i++) {
        NSString *t = chips[i][@"title"];
        BOOL on = [chips[i][@"id"] isEqualToString:_group];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        b.titleLabel.font = font;
        [b setTitle:t forState:UIControlStateNormal];
        UIColor *fg = on ? [CBTheme onBrand] : (i == 0 ? [CBTheme focus] : [CBTheme text]);
        [b setTitleColor:fg forState:UIControlStateNormal];
        [b setBackgroundImage:[CBTheme imageWithColor:on ? [CBTheme brand] : [CBTheme surface]] forState:UIControlStateNormal];
        [b setBackgroundImage:[CBTheme imageWithColor:[CBTheme surface2]] forState:UIControlStateHighlighted];
        b.layer.cornerRadius = h / 2;
        b.clipsToBounds = YES;
        CGFloat bw = ceil([t sizeWithFont:font].width) + 28;
        b.frame = CGRectMake(x, 7, bw, h);
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chips addSubview:b];
        if (on) selected = b;
        x += bw + 8;
    }
    _chips.contentSize = CGSizeMake(x + 4, 48);
    objc_setAssociatedObject(_chips, "ids", [chips valueForKey:@"id"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Nhóm đang chọn khuất bên phải (chọn bằng lệnh / mở lại màn): cuộn tới — chỉ khi dải đã có bề ngang
    CGFloat vw = _chips.bounds.size.width;
    if (selected && vw > 0 && CGRectGetMaxX(selected.frame) > _chips.contentOffset.x + vw) {
        [_chips setContentOffset:CGPointMake(MAX(0, MIN(selected.frame.origin.x - 12, _chips.contentSize.width - vw)), 0) animated:NO];
    } else if (!selected || vw <= 0) {
        _chips.contentOffset = CGPointZero;
    }
}

- (void)chipTapped:(UIButton *)b {
    [self selectGroupAt:b.tag];
}

- (void)selectGroupAt:(NSInteger)index {
    NSArray *ids = objc_getAssociatedObject(_chips, "ids");
    if (index < 0 || index >= (NSInteger)ids.count) return;
    _group = ids[index];
    [self rebuild];
    [_cv setContentOffset:CGPointZero animated:NO];
}

- (void)setQuery:(NSString *)query {
    _query = query;
    _search.text = query;
    [self rebuild];
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    _query = text;
    [self rebuild];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

#pragma mark - Lưới

- (NSInteger)collectionView:(CBCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return _visible.count;
}

- (CGSize)collectionView:(CBCollectionView *)cv layout:(CBCollectionViewFlowLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat w = cv.bounds.size.width - 24;
    CGFloat minW = [CBTheme isPad] ? 228 : 260;
    NSInteger cols = MAX(1, (NSInteger)floor((w + 12) / (minW + 12)));
    return CGSizeMake(floor((w - 12 * (cols - 1)) / cols), 116);
}

- (CBCollectionViewCell *)collectionView:(CBCollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CBChannelCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ch" forIndexPath:ip];
    NSDictionary *c = _visible[ip.item];
    [cell setChannel:c compact:NO];
    __weak CBTVViewController *weakSelf = self;
    cell.onStar = ^{ [weakSelf toggleFavorite:c]; };
    return cell;
}

- (void)collectionView:(CBCollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [self openChannelAt:ip.item];
}

- (void)openChannelAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_visible.count) return;
    [_search resignFirstResponder];
    CBLimitBlock b = [CBWatchLimit blocked];
    if (b != CBLimitNone) {
        [CBParental limitReached:b film:nil episode:nil host:self];
        return;
    }
    NSDictionary *c = _visible[index];
    if ([CBIPTV matchState:c at:[[NSDate date] timeIntervalSince1970]] == CBMatchLater) {
        [self askBeforeKick:c];
        return;
    }
    [self presentPlayerAt:index];
}

- (void)presentPlayerAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_visible.count) return;
    CBLivePlayerViewController *p = [[CBLivePlayerViewController alloc] initWithChannels:_visible index:index];
    [self presentViewController:p animated:YES completion:nil];
}

/// Trận còn hơn 30 phút mới đá: kênh thường chưa lên sóng — hỏi đặt nhắc thay vì mở ra màn lỗi
- (void)askBeforeKick:(NSDictionary *)c {
    double kick = CBNum(c, @"kick", 0), now = [[NSDate date] timeIntervalSince1970];
    long m = (long)ceil((kick - now) / 60);
    NSString *left = m >= 24 * 60 ? [NSString stringWithFormat:@"%ld ngày", (m + 720) / 1440]
                   : (m >= 60 ? [NSString stringWithFormat:@"%ld giờ %02ld phút", m / 60, m % 60] : [NSString stringWithFormat:@"%ld phút", m]);
    NSString *msg = [NSString stringWithFormat:@"%@\nBóng lăn lúc %@ (còn %@).\nKênh trận đấu thường chỉ lên sóng trước giờ đá 15–30 phút.",
                                               CBStr(c, @"n"), [CBIPTV kickText:kick now:now], left];
    BOOL has = [CBIPTV hasKickReminder:c];
    __weak CBTVViewController *weakSelf = self;
    [[CBAlert title:@"Trận chưa bắt đầu" message:msg cancel:@"Đóng" others:@[has ? @"Bỏ nhắc" : @"Nhắc lúc bóng lăn", @"Vẫn mở"]
               done:^(CBAlert *a, NSInteger i) {
        CBTVViewController *s = weakSelf;
        if (!s || i == a.cancelButtonIndex) return;
        if ([[a buttonTitleAtIndex:i] isEqualToString:@"Vẫn mở"]) {
            NSUInteger idx = [s->_visible indexOfObject:c];
            if (idx != NSNotFound) [s presentPlayerAt:(NSInteger)idx];
        } else {
            [s toggleKickReminder:c];
        }
    }] show];
}

- (void)toggleKickReminder:(NSDictionary *)c {
    double kick = CBNum(c, @"kick", 0);
    if ([CBIPTV toggleKickReminder:c]) {
        [CBTheme toast:[NSString stringWithFormat:@"Sẽ nhắc lúc bóng lăn (%@).", [CBIPTV kickText:kick now:[[NSDate date] timeIntervalSince1970]]]];
    } else {
        [CBTheme toast:@"Đã bỏ nhắc."];
    }
    [self tickGuide];
}

- (void)showGuideAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_visible.count) return;
    [self.navigationController pushViewController:[[CBTVGuideViewController alloc] initWithChannel:_visible[index]] animated:YES];
}

- (void)toggleFavorite:(NSDictionary *)c {
    BOOL on = ![CBIPTV isFavorite:c];
    [CBIPTV setFavorite:c on:on];
    [CBTheme toast:on ? [NSString stringWithFormat:@"Đã thêm %@ vào Yêu thích.", CBStr(c, @"n")]
                      : [NSString stringWithFormat:@"Đã bỏ %@ khỏi Yêu thích.", CBStr(c, @"n")]];
    [self rebuild];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [_cv indexPathForItemAtPoint:[g locationInView:_cv]];
    if (!ip || ip.item >= (NSInteger)_visible.count) return;
    _sheetChannel = _visible[ip.item];
    BOOL fav = [CBIPTV isFavorite:_sheetChannel];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:CBStr(_sheetChannel, @"n") delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:@"Xem"];
    CBMatchState ms = [CBIPTV matchState:_sheetChannel at:[[NSDate date] timeIntervalSince1970]];
    if (ms == CBMatchLater || ms == CBMatchSoon) {
        [sheet addButtonWithTitle:[CBIPTV hasKickReminder:_sheetChannel] ? @"Bỏ nhắc bóng lăn" : @"🔔 Nhắc lúc bóng lăn"];
    }
    if (ms == CBMatchNone) [sheet addButtonWithTitle:@"Lịch phát sóng"];
    [sheet addButtonWithTitle:fav ? @"Bỏ khỏi Yêu thích" : @"★ Thêm vào Yêu thích"];
    if ([CBIPTV channelBadReason:_sheetChannel]) [sheet addButtonWithTitle:@"Thử lại kênh này"];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Huỷ"];
    CBCollectionViewCell *cell = [_cv cellForItemAtIndexPath:ip];
    if ([CBTheme isPad] && cell) [sheet showFromRect:cell.bounds inView:cell animated:YES];
    else [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    NSDictionary *c = _sheetChannel;
    _sheetChannel = nil;
    if (!c || index == sheet.cancelButtonIndex || index < 0) return;
    NSString *t = [sheet buttonTitleAtIndex:index];
    NSInteger i = (NSInteger)[_visible indexOfObject:c];
    if ([t isEqualToString:@"Xem"]) [self openChannelAt:i];
    else if ([t isEqualToString:@"Lịch phát sóng"]) [self showGuideAt:i];
    else if ([t hasSuffix:@"hắc lúc bóng lăn"] || [t isEqualToString:@"Bỏ nhắc bóng lăn"]) [self toggleKickReminder:c];
    else if ([t isEqualToString:@"Thử lại kênh này"]) {
        [CBIPTV clearBadFor:c];
        [self rebuild];
        [self openChannelAt:(NSInteger)[_visible indexOfObject:c]];
    } else [self toggleFavorite:c];
}

#pragma mark - Danh sách

- (void)openSettings {
    [self.navigationController pushViewController:[[CBTVSettingsViewController alloc] init] animated:YES];
}

- (void)addList {
    [CBTVViewController askAddList:^(NSDictionary *list) {
        [self rebuild];
    }];
}

+ (void)askAddList:(void (^)(NSDictionary *))done {
    CBAlert *a = [CBAlert title:@"Thêm danh sách kênh" message:@"Địa chỉ danh sách M3U / M3U8 (http…)" cancel:@"Huỷ"
                         others:@[@"Thêm"] done:^(CBAlert *alert, NSInteger index) {
        if (index == alert.cancelButtonIndex) return;
        NSString *url = [[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (url.length < 8) {
            [CBTheme toast:@"Chưa có địa chỉ danh sách."];
            return;
        }
        NSDictionary *l = [CBIPTV addList:url name:nil];
        CBLog(@"Truyền hình: thêm danh sách %@", url);
        [CBIPTV refresh:YES done:^(NSString *err) {
            [CBTheme toast:err ?: [NSString stringWithFormat:@"Đã tải %lu kênh.", (unsigned long)[CBIPTV channels].count]];
        }];
        if (done) done(l);
    }];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *f = [a textFieldAtIndex:0];
    f.keyboardType = UIKeyboardTypeURL;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.placeholder = @"http://…/danh-sach.m3u";
    [a show];
}

+ (void)playKey:(NSString *)key from:(UIViewController *)host {
    void (^go)(void) = ^{
        NSArray *channels = [CBIPTV channels];
        if ([CBPrefs kids]) channels = [CBIPTV kidsFilter:channels];
        NSInteger idx = NSNotFound;
        for (NSUInteger i = 0; i < channels.count; i++) {
            if ([CBStr(channels[i], @"k") isEqualToString:key]) {
                idx = (NSInteger)i;
                break;
            }
        }
        if (idx == NSNotFound) {
            [CBTheme toast:@"Danh sách kênh đang chọn không có kênh này."];
            return;
        }
        UIViewController *top = host;
        while (top.presentedViewController) top = top.presentedViewController;
        CBLivePlayerViewController *p = [[CBLivePlayerViewController alloc] initWithChannels:channels index:idx];
        [top presentViewController:p animated:YES completion:nil];
    };
    if ([CBIPTV channels]) go();
    else [CBIPTV refresh:NO done:^(NSString *err) {
        if (err) [CBTheme toast:err];
        else go();
    }];
}

@end
