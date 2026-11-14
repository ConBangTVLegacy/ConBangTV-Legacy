#import <Foundation/Foundation.h>

/// Ghi log ra NSLog (syslog của máy) và tệp ConBangLegacy-spike.log trong thư mục Documents — đọc qua SSH.
void CBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *CBLogPath(void);
/// Mã máy, vd "iPad2,5" (iPad mini 1), "iPhone5,2" (iPhone 5)
NSString *CBDeviceModel(void);
/// Bộ nhớ app đang chiếm (resident, MB)
double CBResidentMB(void);
