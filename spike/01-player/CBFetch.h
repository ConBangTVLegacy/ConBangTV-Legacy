#import <Foundation/Foundation.h>

typedef void (^CBFetchDone)(NSData *data, NSHTTPURLResponse *response, NSError *error, NSTimeInterval seconds);

/// Tải một địa chỉ bằng NSURLConnection (iOS 6 không có NSURLSession).
/// anchors = nil: kiểm chứng chỉ bằng kho gốc của iOS 6. anchors = mảng SecCertificateRef: CHỈ tin các gốc này
/// (thử xem iOS 6 có kiểm nổi chuỗi Let's Encrypt — ECDSA P-384 — khi được đưa gốc ISRG không).
@interface CBFetch : NSObject <NSURLConnectionDataDelegate>
+ (void)get:(NSString *)url anchors:(NSArray *)anchors done:(CBFetchDone)done;
/// Gốc ISRG Root X1 + X2 đóng kèm trong app (Resources/*.der)
+ (NSArray *)bundledAnchors;
@end
