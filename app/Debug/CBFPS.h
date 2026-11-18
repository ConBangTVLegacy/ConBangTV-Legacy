// CBFPS — chỉ có trong bản thử: cuộn đều một danh sách (như ngón tay kéo liên tục) và đo độ mượt.
#import <UIKit/UIKit.h>
#include <mach/mach.h>

@interface CBFPS : NSObject
/// Cuộn `sv` với `speed` điểm / giây trong `seconds` giây (chạm cuối thì quay đầu), rồi ghi nhật ký: số khung hình máy vẽ ra
/// thật (bộ đếm của render server — tính cả việc GPU vẽ ngoài màn hình), nhịp luồng chính, khung chậm nhất
+ (void)scroll:(UIScrollView *)sv speed:(CGFloat)speed seconds:(double)seconds horizontal:(BOOL)horizontal label:(NSString *)label;
/// profile: lấy mẫu ngăn xếp luồng chính trong lúc cuộn rồi ghi các hàm tốn thời gian nhất (gồm / đỉnh)
+ (void)scroll:(UIScrollView *)sv speed:(CGFloat)speed seconds:(double)seconds horizontal:(BOOL)horizontal profile:(BOOL)profile
         label:(NSString *)label;
@end

/// Bộ đếm khung hình render server đã vẽ (tăng dần; 0 nếu máy không có hàm đó)
uint32_t CBRenderFrames(void);
/// Chụp ngăn xếp của `thread` (tạm dừng nó trong lúc đi chuỗi khung r7): ghi tối đa `max` địa chỉ vào `out`, trả số đã ghi.
/// Không cấp phát / không khoá — gọi được cả khi luồng kia đang giữ khoá malloc / dyld. lo / hi = vùng ngăn xếp của luồng đó
int CBCaptureStack(thread_act_t thread, uintptr_t lo, uintptr_t hi, uintptr_t *out, int max);
/// Tên hàm chứa địa chỉ trả về `addr` (dladdr — bản thử giữ ký hiệu cục bộ); cache có thể nil
NSString *CBSymbol(uintptr_t addr, NSMutableDictionary *cache);
