#import <Foundation/Foundation.h>

// Miễn trừ trách nhiệm & quyền riêng tư — nội dung sinh từ linux/core/src/disclaimer.rs của repo chính (CBDisclaimerText.m)
extern const NSInteger CBDisclaimerVersion;
extern NSString *const CBDisclaimerTitle;
extern NSString *const CBDisclaimerDate;
extern NSString *const CBDisclaimerConsent;
/// @[@[tiêu đề, nội dung], …]
NSArray *CBDisclaimerSections(void);
