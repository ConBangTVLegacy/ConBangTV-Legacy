#import "CBNavController.h"
#import "CBTheme.h"

@implementation CBNavController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [CBTheme isPad] ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [CBTheme isPad] ? [UIApplication sharedApplication].statusBarOrientation : UIInterfaceOrientationPortrait;
}

@end
