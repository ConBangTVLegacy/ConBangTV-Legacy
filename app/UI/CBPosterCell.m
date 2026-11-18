#import "CBPosterCell.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBTheme.h"

/// Góc bo của ảnh bìa (điểm)
static const CGFloat kPosterRadius = 6;

@implementation CBPosterCell {
    CBCoverView *_poster;
    UILabel *_title;
    UILabel *_sub;
    UILabel *_badge;
    UIView *_track;
    UIView *_bar;
    UILabel *_placeholder;
    double _progress;
    NSString *_posterUrl;
    BOOL _purged;  // ảnh đã bỏ lúc ô khuất (máy RAM thấp) — hiện lại thì nạp lại
}

+ (CGFloat)defaultWidth {
    return [CBTheme isPad] ? 132 : 96;
}

+ (CGSize)sizeForWidth:(CGFloat)w {
    return CGSizeMake(w, ceil(w * 1.5) + ([CBTheme isPad] ? 54 : 48));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(purge) name:CBImagesPurgeNotification object:nil];
        self.backgroundColor = [UIColor clearColor];
        // Nền xám + tên phim nằm dưới ảnh: có ảnh thì ẩn đi. Không lớp nào trong ô dùng layer.cornerRadius (GPU vẽ ngoài màn hình mỗi
        // khung khi cuộn — xem CBTheme imageWithColor:radius:): nền bo vẽ vào nội dung nhãn, ảnh bìa bo sẵn lúc giải mã
        _placeholder = [CBTheme roundLabel:[CBTheme surface2] radius:kPosterRadius];
        _placeholder.textColor = [CBTheme dim];
        _placeholder.font = [CBTheme font:11];
        _placeholder.numberOfLines = 4;
        _placeholder.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_placeholder];

        _poster = [[CBCoverView alloc] init];
        _poster.placeholder = _placeholder;
        _poster.backgroundColor = [UIColor clearColor];
        _poster.contentMode = UIViewContentModeScaleToFill;  // ảnh đã cắt đúng khổ ô
        [self.contentView addSubview:_poster];

        _badge = [CBTheme roundLabel:[CBTheme brand] radius:3];
        _badge.textColor = [CBTheme onBrand];
        _badge.font = [CBTheme bold:10];
        _badge.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_badge];

        _track = [[UIView alloc] init];
        _track.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        [self.contentView addSubview:_track];
        _bar = [[UIView alloc] init];
        _bar.backgroundColor = [CBTheme brand];
        [_track addSubview:_bar];

        _title = [[UILabel alloc] init];
        _title.backgroundColor = [UIColor clearColor];
        _title.textColor = [CBTheme text];
        _title.font = [CBTheme font:[CBTheme isPad] ? 13 : 12];
        _title.numberOfLines = 2;
        [self.contentView addSubview:_title];

        _sub = [[UILabel alloc] init];
        _sub.backgroundColor = [UIColor clearColor];
        _sub.textColor = [CBTheme dim];
        _sub.font = [CBTheme font:11];
        [self.contentView addSubview:_sub];
    }
    return self;
}

- (UIImageView *)poster {
    return _poster;
}

- (void)setItem:(NSDictionary *)item {
    _title.text = CBStr(item, @"title");
    _sub.text = CBStr(item, @"sub");
    NSString *badge = CBStr(item, @"badge");
    _badge.text = badge ? [NSString stringWithFormat:@" %@ ", badge] : nil;
    _badge.hidden = !badge;
    _placeholder.text = CBStr(item, @"title");
    _progress = CBNum(item, @"progress", -1);
    _posterUrl = CBStr(item, @"poster");
    _purged = NO;
    [self loadPoster];
    [self setNeedsLayout];
}

- (void)loadPoster {
    CGFloat w = self.bounds.size.width;
    [CBImages load:_posterUrl size:CGSizeMake(w, ceil(w * 1.5)) radius:kPosterRadius into:_poster];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// CBImages purgeOffscreen: ô đang khuất (màn dưới trình phát…) bỏ ảnh đã giải mã cho đỡ RAM
- (void)purge {
    if ((self.window && !self.hidden) || !_poster.image) return;  // ô ẩn = đang nằm kho chờ dùng lại của lưới
    [CBImages cancel:_poster];
    _poster.image = nil;
    _purged = YES;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _purged) {
        _purged = NO;
        [self loadPoster];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [CBImages cancel:_poster];
    _poster.image = nil;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _poster.alpha = highlighted ? 0.6 : 1;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat ph = ceil(w * 1.5);
    _poster.frame = CGRectMake(0, 0, w, ph);
    _placeholder.frame = _poster.frame;
    [_badge sizeToFit];
    _badge.frame = CGRectMake(4, 4, MIN(_badge.bounds.size.width, w - 8), 16);
    _track.hidden = _progress < 0;
    _track.frame = CGRectMake(0, ph - 4, w, 4);
    _bar.frame = CGRectMake(0, 0, w * MAX(0, MIN(1, _progress)), 4);
    CGFloat th = [CBTheme heightOf:_title.text font:_title.font width:w];
    th = MIN(th, ceil(_title.font.lineHeight * 2));
    _title.frame = CGRectMake(0, ph + 4, w, th);
    _sub.frame = CGRectMake(0, ph + 4 + th, w, 15);
}

@end
