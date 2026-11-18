// CBLatency — chỉ có trong bản thử: đo độ trễ chạm và các lần luồng chính bị nghẽn, ghi nhật ký «[chạm] …» / «[nghẽn] …».
//  • chạm xuống / nhấc tay → app nhận được bao lâu (luồng chính bận thì sự kiện nằm chờ)
//  • chạm xuống → ô / nút sáng lên bao lâu (UIScrollView giữ chạm ~150 ms để đoán có phải cuộn)
//  • nhấc tay → màn mới bắt đầu mở / hiện xong, chuyển màn được bao nhiêu khung/s
//  • luồng chính bận liền > 100 ms: ngăn xếp lúc đang nghẽn (lấy bằng luồng canh)
#import <Foundation/Foundation.h>

@interface CBLatency : NSObject
/// Gọi một lần trên luồng chính lúc mở app (bản thử)
+ (void)start;
@end
