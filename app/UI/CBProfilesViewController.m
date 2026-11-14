#import "CBProfilesViewController.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"

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
    _profiles = [CBPrefs profiles];
    _tiles = [NSMutableArray array];
    NSString *current = [CBPrefs profileId];
    for (NSUInteger i = 0; i < _profiles.count; i++) {
        NSDictionary *p = _profiles[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        UIView *avatar = [CBTheme avatarFor:p size:80];
        avatar.userInteractionEnabled = NO;
        avatar.tag = 1;
        if ([(CBStr(p, @"id") ?: @"") isEqualToString:current]) {
            avatar.layer.borderColor = [CBTheme focus].CGColor;
            avatar.layer.borderWidth = 3;
        }
        [b addSubview:avatar];
        UILabel *name = [[UILabel alloc] init];
        name.tag = 2;
        name.backgroundColor = [UIColor clearColor];
        name.textColor = [CBTheme text];
        name.font = [CBTheme font:15];
        name.textAlignment = NSTextAlignmentCenter;
        name.text = [NSString stringWithFormat:@"%@%@", CBStr(p, @"name") ?: @"?", CBStr(p, @"pin") ? @" 🔒" : @""];
        [b addSubview:name];
        [self.view addSubview:b];
        [_tiles addObject:b];
    }
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
        [b viewWithTag:2].frame = CGRectMake(0, 90, tw, 22);
    }
}

- (void)tapped:(UIButton *)b {
    NSDictionary *p = _profiles[b.tag];
    if (!CBStr(p, @"pin")) {
        [self choose:p];
        return;
    }
    _pending = p;
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:CBStr(p, @"name") message:@"Nhập mã PIN" delegate:self
                                      cancelButtonTitle:@"Huỷ" otherButtonTitles:@"Vào", nil];
    a.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
    [a show];
}

- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)index {
    if (index == a.cancelButtonIndex || !_pending) return;
    if ([CBPrefs checkPin:[a textFieldAtIndex:0].text profile:_pending]) {
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
