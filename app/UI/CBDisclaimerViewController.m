#import "CBDisclaimerViewController.h"
#import "CBDisclaimer.h"
#import "CBLog.h"
#import "CBPrefs.h"
#import "CBTheme.h"

@implementation CBDisclaimerViewController {
    BOOL _gate;
    UIScrollView *_scroll;
    UILabel *_text;
    UIButton *_accept;
}

- (instancetype)initGate:(BOOL)gate {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _gate = gate;
        self.title = @"Miễn trừ trách nhiệm";
    }
    return self;
}

// Màn trình bày lúc mở app (cổng «Đồng ý»): iPhone dọc như các màn khác
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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [CBTheme bg];
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_scroll];
    _text = [[UILabel alloc] init];
    _text.backgroundColor = [UIColor clearColor];
    _text.textColor = [CBTheme text];
    _text.numberOfLines = 0;
    _text.font = [CBTheme font:15];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Côn Bằng TV Legacy — %@\n", CBDisclaimerTitle];
    [s appendString:_gate ? @"Đọc hết rồi chọn «Đồng ý» để vào app.\n\n"
                          : [NSString stringWithFormat:@"Bản %ld – %@\n\n", (long)CBDisclaimerVersion, CBDisclaimerDate]];
    for (NSArray *sec in CBDisclaimerSections()) [s appendFormat:@"%@\n%@\n\n", sec[0], sec[1]];
    [s appendFormat:@"%@ (bản %ld – %@)", CBDisclaimerConsent, (long)CBDisclaimerVersion, CBDisclaimerDate];
    _text.text = s;
    [_scroll addSubview:_text];
    if (_gate) {
        _accept = [CBTheme button:@"Đồng ý" primary:YES];
        [_accept addTarget:self action:@selector(accept) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:_accept];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = MIN(self.view.bounds.size.width, 700);
    CGFloat x = (self.view.bounds.size.width - w) / 2 + 16;
    CGFloat top = _gate ? 30 : 12;
    CGFloat h = [CBTheme heightOf:_text.text font:_text.font width:w - 32];
    _text.frame = CGRectMake(x, top, w - 32, h);
    CGFloat y = CGRectGetMaxY(_text.frame) + 20;
    if (_accept) {
        _accept.frame = CGRectMake(x, y, w - 32, 48);
        y += 68;
    }
    _scroll.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

- (void)accept {
    [CBPrefs setDisclaimerVersion:CBDisclaimerVersion];
    CBLog(@"Đồng ý miễn trừ trách nhiệm bản %ld", (long)CBDisclaimerVersion);
    void (^done)(void) = self.onAccept;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (done) done();
    }];
}

@end
