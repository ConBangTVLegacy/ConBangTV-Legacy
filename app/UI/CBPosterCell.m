#import "CBPosterCell.h"
#import "CBImages.h"
#import "CBJSON.h"
#import "CBTheme.h"

@implementation CBPosterCell {
    UIImageView *_poster;
    UILabel *_title;
    UILabel *_sub;
    UILabel *_badge;
    UIView *_track;
    UIView *_bar;
    UILabel *_placeholder;
    double _progress;
}

+ (CGFloat)defaultWidth {
    return [CBTheme isPad] ? 132 : 96;
}

+ (CGSize)sizeForWidth:(CGFloat)w {
    return CGSizeMake(w, ceil(w * 1.5) + ([CBTheme isPad] ? 54 : 48));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        // Nền xám + tên phim nằm dưới ảnh: ảnh tải xong tự che đi
        _placeholder = [[UILabel alloc] init];
        _placeholder.backgroundColor = [CBTheme surface2];
        _placeholder.textColor = [CBTheme dim];
        _placeholder.font = [CBTheme font:11];
        _placeholder.numberOfLines = 4;
        _placeholder.textAlignment = NSTextAlignmentCenter;
        _placeholder.layer.cornerRadius = 6;
        _placeholder.clipsToBounds = YES;
        [self.contentView addSubview:_placeholder];

        _poster = [[UIImageView alloc] init];
        _poster.backgroundColor = [UIColor clearColor];
        _poster.contentMode = UIViewContentModeScaleAspectFill;
        _poster.clipsToBounds = YES;
        _poster.layer.cornerRadius = 6;
        [self.contentView addSubview:_poster];

        _badge = [[UILabel alloc] init];
        _badge.backgroundColor = [CBTheme brand];
        _badge.textColor = [CBTheme onBrand];
        _badge.font = [CBTheme bold:10];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 3;
        _badge.clipsToBounds = YES;
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
    [CBImages load:CBStr(item, @"poster") size:CGSizeMake(self.bounds.size.width, self.bounds.size.width * 1.5) into:_poster];
    [self setNeedsLayout];
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
