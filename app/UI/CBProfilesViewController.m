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
    UIScrollView *_scroll;  // nhiều người xem (tối đa 8) không vừa một màn iPhone
    UIButton *_closeButton;
    UILabel *_title;
    NSDictionary *_pending;  // người xem đang hỏi mã PIN
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];
    if (self.closable) {
        _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_closeButton setTitle:@"✕ Đóng" forState:UIControlStateNormal];
        [_closeButton setTitleColor:[CBTheme dim] forState:UIControlStateNormal];
        [_closeButton setTitleColor:[CBTheme text] forState:UIControlStateHighlighted];
        _closeButton.titleLabel.font = [CBTheme bold:16];
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:_closeButton];
    }
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = [CBTheme text];
    _title.font = [CBTheme bold:24];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.text = @"Ai đang xem?";
    [_scroll addSubview:_title];
    [self buildTiles];
}

// iPhone: dọc như các màn khác (màn trình bày đè lên không theo khoá chiều của thanh điều hướng)
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [CBTheme isPad] ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

// iOS 5 hỏi hàm này (iOS 6 dùng supportedInterfaceOrientations). Phải khai báo ngay trong lớp: màn trình bày đè lên (modal) trên
// iOS 5 không theo hàm thay chung ở CBCompat — trình phát bị kéo về dọc, không xoay ngang được (iPad 1, 0.5.0)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return ([self supportedInterfaceOrientations] & (1u << o)) != 0;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [CBTheme isPad] ? [UIApplication sharedApplication].statusBarOrientation : UIInterfaceOrientationPortrait;
}

- (void)closeTapped {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
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
            avatar.layer.cornerRadius = 40;   // viền tròn theo ảnh (màn tĩnh — không ngại bo góc lớp)
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
    for (UIView *v in _tiles) [_scroll addSubview:v];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    _closeButton.frame = CGRectMake(8, 20, 90, 44);
    // iPhone dọc: 3 cột (ô 100 điểm) — trước 2 cột, 6 người xem trở lên tràn khỏi màn
    CGFloat tw = [CBTheme isPad] ? 110 : MIN(110, floor((w - 12) / 3)), th = 120;
    NSInteger cols = MAX(1, MIN((NSInteger)_tiles.count, (NSInteger)floor((w - 12) / tw)));
    NSInteger rows = ((NSInteger)_tiles.count + cols - 1) / cols;
    CGFloat y0 = MAX(110, (h - rows * th) / 2);
    _title.frame = CGRectMake(0, y0 - 60, w, 34);
    _scroll.contentSize = CGSizeMake(w, y0 + rows * th + 30);
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
            UIAlertView *a = [[CBAlert alloc] initWithTitle:@"Thêm người xem" message:@"Tên người xem" delegate:self
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
    UIAlertView *a = [[CBAlert alloc] initWithTitle:CBStr(p, @"name") message:@"Nhập mã PIN" delegate:self
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
        NSDictionary *np = [CBPrefs addProfile:text];  // tên trống → «Người xem» (như ở Cài đặt)
        CBLog(@"Thêm người xem %@", CBStr(np, @"name"));
        [self buildTiles];
        return;
    }
    if (!_pending) return;
    if ([CBPrefs checkPin:text profile:_pending]) {
        [self choose:_pending];
    } else {
        [[[CBAlert alloc] initWithTitle:@"Sai mã PIN" message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
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
