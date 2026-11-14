#import <UIKit/UIKit.h>

/// Trình phát thử: AVPlayer + AVPlayerLayer, hiện trạng thái (kích thước hình, bitrate, đệm, khựng, RAM) và ghi log.
@interface PlayerViewController : UIViewController
- (instancetype)initWithURL:(NSURL *)url title:(NSString *)title;
/// Chế độ tự chạy: > 0 thì sau 40% thời gian này tự tua tới giữa phim, hết thời gian thì tự đóng (ghi tổng kết vào log)
@property (nonatomic) NSTimeInterval autoCloseAfter;
@end
