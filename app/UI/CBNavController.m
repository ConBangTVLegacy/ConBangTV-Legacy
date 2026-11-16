#import "CBNavController.h"
#import "CBTheme.h"

@implementation CBNavController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [CBTheme isPad] ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

// iOS 5 hỏi hàm này (iOS 6 dùng supportedInterfaceOrientations): UINavigationController của iOS 5 hỏi màn trên cùng —
// các màn trong thanh điều hướng không tự khai báo chiều nên quyết ở đây, giống iOS 6
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return ([self supportedInterfaceOrientations] & (1u << o)) != 0;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [CBTheme isPad] ? [UIApplication sharedApplication].statusBarOrientation : UIInterfaceOrientationPortrait;
}

@end
