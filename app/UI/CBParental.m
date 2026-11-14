#import "CBParental.h"
#import "CBJSON.h"
#import "CBLog.h"
#import "CBPlayerViewController.h"
#import "CBPrefs.h"
#import "CBTheme.h"

@implementation CBAlert {
    void (^_done)(CBAlert *, NSInteger);
}

+ (CBAlert *)title:(NSString *)title message:(NSString *)message cancel:(NSString *)cancel others:(NSArray *)others
              done:(void (^)(CBAlert *, NSInteger))done {
    CBAlert *a = [[CBAlert alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:cancel otherButtonTitles:nil];
    for (NSString *o in others) [a addButtonWithTitle:o];
    a.delegate = a;
    a->_done = [done copy];
    return a;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
    void (^done)(CBAlert *, NSInteger) = _done;
    _done = nil;  // bỏ vòng giữ nhau (khối giữ hộp thoại)
    if (done) done(self, index);
}

+ (void)askPin:(NSString *)title message:(NSString *)message done:(void (^)(NSString *))done {
    CBAlert *a = [self title:title message:message cancel:@"Huỷ" others:@[@"OK"] done:^(CBAlert *alert, NSInteger index) {
        if (index == alert.cancelButtonIndex) {
            done(nil);
            return;
        }
        done([[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"");
    }];
    a.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
    [a show];
}

@end

static BOOL CBIsPin(NSString *s) {
    return s.length == 4 && [s rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

@implementation CBParental

+ (void)askNewParentPin:(void (^)(BOOL))done {
    [CBAlert askPin:@"Đặt mã PIN phụ huynh"
            message:@"4 chữ số. Nhớ kỹ — quên phải xoá dữ liệu app."
               done:^(NSString *pin) {
        if (!pin) {
            done(NO);
            return;
        }
        if (!CBIsPin(pin)) {
            [CBTheme toast:@"Mã PIN phụ huynh gồm 4 chữ số."];
            done(NO);
            return;
        }
        [CBAlert askPin:@"Nhập lại mã PIN phụ huynh" message:nil done:^(NSString *again) {
            if (!again) {
                done(NO);
                return;
            }
            if (![again isEqualToString:pin]) {
                [CBTheme toast:@"Hai lần nhập không khớp — chưa đặt mã."];
                done(NO);
                return;
            }
            [CBPrefs setParentPin:pin];
            CBLog(@"Đã đặt mã PIN phụ huynh");
            [CBTheme toast:@"Đã đặt mã PIN phụ huynh."];
            done(YES);
        }];
    }];
}

+ (void)checkParent:(NSString *)why done:(void (^)(BOOL))done {
    if (![CBPrefs hasParentPin]) {
        [self askNewParentPin:done];
        return;
    }
    [CBAlert askPin:@"Mã PIN phụ huynh" message:why done:^(NSString *pin) {
        if (!pin) {
            done(NO);
            return;
        }
        BOOL ok = [CBPrefs checkParentPin:pin];
        if (!ok) [CBTheme toast:@"Sai mã PIN phụ huynh."];
        done(ok);
    }];
}

+ (void)limitReached:(CBLimitBlock)block film:(NSString *)film episode:(NSString *)ep host:(UIViewController *)host {
    NSString *why = [[CBWatchLimit reason:block] stringByAppendingString:@"\nNgười lớn nhập mã PIN phụ huynh để cho xem thêm."];
    CBLog(@"Hết giờ xem: %@", [CBWatchLimit reason:block]);
    [[CBAlert title:@"Hết giờ xem" message:why cancel:@"Thoát" others:@[@"Cho xem thêm…"] done:^(CBAlert *a, NSInteger index) {
        if (index == a.cancelButtonIndex) return;
        [CBAlert askPin:@"Mã PIN phụ huynh" message:@"Nhập mã PIN phụ huynh (4 số) để cho xem thêm." done:^(NSString *pin) {
            if (!pin) {
                [self limitReached:block film:film episode:ep host:host];
                return;
            }
            if (![CBPrefs checkParentPin:pin]) {
                [CBTheme toast:@"Sai mã PIN phụ huynh."];
                [self limitReached:block film:film episode:ep host:host];
                return;
            }
            NSMutableArray *labels = [NSMutableArray array];
            for (NSNumber *m in [CBWatchLimit grantChoices]) {
                [labels addObject:[@"Thêm " stringByAppendingString:[CBWatchLimit dailyLabel:m.integerValue]]];
            }
            [labels addObject:@"Tới 6 giờ sáng"];
            NSString *who = [NSString stringWithFormat:@"Người xem: %@.", CBStr([CBPrefs currentProfile], @"name") ?: @"?"];
            [[CBAlert title:@"Cho xem thêm bao lâu?" message:who cancel:@"Huỷ" others:labels done:^(CBAlert *g, NSInteger gi) {
                if (gi == g.cancelButtonIndex) {
                    [self limitReached:block film:film episode:ep host:host];
                    return;
                }
                // Tra theo chữ trên nút: nút thêm bằng addButtonWithTitle thì firstOtherButtonIndex = -1 trên iOS 6
                NSInteger choice = (NSInteger)[labels indexOfObject:[g buttonTitleAtIndex:gi]];
                if (choice == NSNotFound) return;
                NSArray *grants = [CBWatchLimit grantChoices];
                if (choice < (NSInteger)grants.count) [CBWatchLimit grant:[grants[choice] integerValue]];
                else [CBWatchLimit grantUntilMorning];
                [CBTheme toast:@"Đã cho xem thêm."];
                if (film.length && host && !host.presentedViewController) {
                    CBPlayerViewController *p = [[CBPlayerViewController alloc] initWithFilm:film detail:nil episode:ep ?: @"" resume:YES];
                    [host presentViewController:p animated:YES completion:nil];
                }
            }] show];
        }];
    }] show];
}

@end
