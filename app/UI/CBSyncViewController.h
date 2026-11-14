#import <UIKit/UIKit.h>

/// Đồng bộ trong nhà (Cài đặt → Đồng bộ trong nhà): máy này + mã ghép, máy đã ghép, máy trong mạng, ghép bằng địa chỉ.
/// Mở màn thì cho máy khác ghép vào (mã 4 số); rời màn thì thôi. Giống SyncPage của bản Windows.
@interface CBSyncViewController : UITableViewController
/// Ghép với máy kia (mã 4 số đang hiện ở máy đó)
- (void)pairHost:(NSString *)host port:(NSInteger)port code:(NSString *)code;
@end
