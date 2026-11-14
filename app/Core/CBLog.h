#import <Foundation/Foundation.h>

/// Nhật ký của app: NSLog (syslog) + tệp ConBangTV.log trong Documents (đọc qua SSH khi thử). Ghi kèm vào nhật ký của lõi.
void CBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *CBLogPath(void);
/// Thư mục Documents của app
NSString *CBDocumentsDir(void);
/// Mã máy, vd "iPad2,5" (iPad mini 1), "iPhone5,2" (iPhone 5)
NSString *CBDeviceModel(void);
/// Bộ nhớ app đang chiếm (resident, MB)
double CBResidentMB(void);
/// ms kể từ 1970
long long CBNowMs(void);
