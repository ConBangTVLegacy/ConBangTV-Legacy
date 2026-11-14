#import <UIKit/UIKit.h>

/// Miễn trừ trách nhiệm & quyền riêng tư. gate: lần đầu mở app — phải bấm «Đồng ý» mới vào app (như các bản khác).
@interface CBDisclaimerViewController : UIViewController
- (instancetype)initGate:(BOOL)gate;
@property (nonatomic, copy) void (^onAccept)(void);
@end
