#import "CBProfilesViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBParental.h"
#import "CBPrefs.h"
#import "CBTheme.h"

enum { CBAskPin = 1, CBAskAdd = 2 };
static const NSUInteger CBMaxProfiles = 8;

@interface CBProfilesViewController () <UIAlertViewDelegate>
@end

@implementation CBProfilesViewController {
    NSArray *_profiles;
    NSMutableArray *_tiles;
    UILabel *_title;
    NSDictionary *_pending;  // người xem đang hỏi mã PIN
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = [CBTheme text];
    _title.font = [CBTheme bold:24];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.text = @"Ai đang xem?";
    [self.view addSubview:_title];
    [self buildTiles];
}

- (UIButton *)tileWithAvatar:(UIView *)avatar name:(NSString *)text tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    avatar.userInteractionEnabled = NO;
    avatar.tag = 1;
    [b addSubview:avatar];
    UILabel *name = [[UILabel alloc] init];
    name.tag = 2;
    name.backgroundColor = [UIColor clearColor];
    name.textColor = [CBTheme text];
    name.font = [CBTheme font:15];
    name.textAlignment = NSTextAlignmentCenter;
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumScaleFactor = 0.7;
    name.text = text;
    [b addSubview:name];
    return b;
}

/// Ô cho từng người xem + ô «Thêm» (giống màn chọn người xem bản Windows)
- (void)buildTiles {
    for (UIView *v in _tiles) [v removeFromSuperview];
    _profiles = [CBPrefs profiles];
    _tiles = [NSMutableArray array];
    NSString *current = [CBPrefs profileId];
    for (NSUInteger i = 0; i < _profiles.count; i++) {
        NSDictionary *p = _profiles[i];
        UIView *avatar = [CBTheme avatarFor:p size:80];
        if ([(CBStr(p, @"id") ?: @"") isEqualToString:current]) {
            avatar.layer.borderColor = [CBTheme focus].CGColor;
            avatar.layer.borderWidth = 3;
        }
        NSString *name = [NSString stringWithFormat:@"%@%@", CBStr(p, @"name") ?: @"?", CBStr(p, @"pin") ? @" 🔒" : @""];
        [_tiles addObject:[self tileWithAvatar:avatar name:name tag:(NSInteger)i]];
    }
    if (_profiles.count < CBMaxProfiles) {
        UILabel *plus = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
        plus.backgroundColor = [CBTheme surface];
        plus.textColor = [CBTheme dim];
        plus.textAlignment = NSTextAlignmentCenter;
        plus.font = [CBTheme font:44];
        plus.text = @"+";
        plus.layer.cornerRadius = 40;
        plus.layer.borderColor = [CBTheme dim].CGColor;
        plus.layer.borderWidth = 2;
        plus.clipsToBounds = YES;
        UIButton *add = [self tileWithAvatar:plus name:@"Thêm" tag:-1];
        [(UILabel *)[add viewWithTag:2] setTextColor:[CBTheme dim]];
        [_tiles addObject:add];
    }
    for (UIView *v in _tiles) [self.view addSubview:v];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat tw = 110, th = 120;
    NSInteger cols = MAX(1, MIN((NSInteger)_tiles.count, (NSInteger)floor((w - 20) / tw)));
    NSInteger rows = ((NSInteger)_tiles.count + cols - 1) / cols;
    CGFloat y0 = MAX(80, (h - rows * th) / 2);
    _title.frame = CGRectMake(0, y0 - 60, w, 34);
    for (NSUInteger i = 0; i < _tiles.count; i++) {
        NSInteger r = (NSInteger)i / cols, c = (NSInteger)i % cols;
        NSInteger inRow = MIN(cols, (NSInteger)_tiles.count - r * cols);
        CGFloat x0 = (w - inRow * tw) / 2;
        UIButton *b = _tiles[i];
        b.frame = CGRectMake(x0 + c * tw, y0 + r * th, tw, th);
        [b viewWithTag:1].frame = CGRectMake((tw - 80) / 2, 4, 80, 80);
        [b viewWithTag:2].frame = CGRectMake(4, 90, tw - 8, 22);
    }
}

- (void)tapped:(UIButton *)b {
    if (b.tag < 0) {
        void (^ask)(void) = ^{
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Thêm người xem" message:@"Tên người xem" delegate:self
                                              cancelButtonTitle:@"Huỷ" otherButtonTitles:@"Thêm", nil];
            a.tag = CBAskAdd;
            a.alertViewStyle = UIAlertViewStylePlainTextInput;
            [a show];
        };
        // Đang có giới hạn giờ xem: thêm người xem cần mã phụ huynh (trẻ khỏi tự tạo người không bị giới hạn)
        if (![CBWatchLimit anyLimits]) {
            ask();
        } else {
            [CBParental checkParent:@"Đang có giới hạn giờ xem — nhập mã PIN phụ huynh để thêm người xem." done:^(BOOL ok) {
                if (ok) ask();
            }];
        }
        return;
    }
    NSDictionary *p = _profiles[b.tag];
    if (!CBStr(p, @"pin")) {
        [self choose:p];
        return;
    }
    _pending = p;
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:CBStr(p, @"name") message:@"Nhập mã PIN" delegate:self
                                      cancelButtonTitle:@"Huỷ" otherButtonTitles:@"Vào", nil];
    a.tag = CBAskPin;
    a.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
    [a show];
}

- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)index {
    if (index == a.cancelButtonIndex) {
        _pending = nil;
        return;
    }
    NSString *text = [[a textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (a.tag == CBAskAdd) {
        if (!text.length) return;
        NSDictionary *np = [CBPrefs addProfile:text];
        CBLog(@"Thêm người xem %@", CBStr(np, @"name"));
        [self buildTiles];
        return;
    }
    if (!_pending) return;
    if ([CBPrefs checkPin:text profile:_pending]) {
        [self choose:_pending];
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Sai mã PIN" message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    _pending = nil;
}

- (void)choose:(NSDictionary *)p {
    [CBPrefs switchProfile:CBStr(p, @"id") ?: @""];
    CBLog(@"Người xem: %@", CBStr(p, @"name"));
    void (^done)(void) = self.onDone;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (done) done();
    }];
}

@end
