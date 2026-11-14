#import "CBFetch.h"
#import "CBLog.h"
#import <Security/Security.h>

static NSString *const kUserAgent =
    @"Mozilla/5.0 (iPad; CPU OS 6_1_3 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10B329 Safari/8536.25";

@implementation CBFetch {
    NSURLConnection *_conn;
    NSMutableData *_data;
    NSHTTPURLResponse *_response;
    NSArray *_anchors;
    NSDate *_start;
    CBFetchDone _done;
}

+ (NSArray *)bundledAnchors {
    static NSArray *anchors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *name in @[@"isrg-root-x1", @"isrg-root-x2"]) {
            NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"der"];
            NSData *der = path ? [NSData dataWithContentsOfFile:path] : nil;
            SecCertificateRef cert = der ? SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der) : NULL;
            if (cert) {
                [list addObject:(__bridge_transfer id)cert];
            } else {
                CBLog(@"Không nạp được chứng chỉ gốc %@.der", name);
            }
        }
        anchors = [list copy];
    });
    return anchors;
}

+ (void)get:(NSString *)url anchors:(NSArray *)anchors done:(CBFetchDone)done {
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        done(nil, nil, [NSError errorWithDomain:@"CBFetch" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Địa chỉ không hợp lệ"}], 0);
        return;
    }
    CBFetch *f = [[CBFetch alloc] init];
    f->_anchors = anchors;
    f->_done = [done copy];
    f->_data = [NSMutableData data];
    f->_start = [NSDate date];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:20];
    [req setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
    // NSURLConnection giữ delegate tới khi xong; _conn tạo vòng giữ tạm, phá ở -finish:
    f->_conn = [[NSURLConnection alloc] initWithRequest:req delegate:f startImmediately:YES];
}

- (void)finish:(NSError *)error {
    NSTimeInterval secs = -[_start timeIntervalSinceNow];
    CBFetchDone done = _done;
    _done = nil;
    _conn = nil;
    if (done) done(error ? nil : _data, _response, error, secs);
}

#pragma mark - NSURLConnection

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (_anchors.count && [space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef trust = space.serverTrust;
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)_anchors);
        SecTrustResultType result = kSecTrustResultInvalid;
        OSStatus status = SecTrustEvaluate(trust, &result);
        CFIndex n = SecTrustGetCertificateCount(trust);
        NSMutableArray *chain = [NSMutableArray array];
        for (CFIndex i = 0; i < n; i++) {
            NSString *s = (__bridge_transfer NSString *)SecCertificateCopySubjectSummary(SecTrustGetCertificateAtIndex(trust, i));
            [chain addObject:s ?: @"?"];
        }
        CBLog(@"Tự kiểm chứng chỉ %@: status=%d result=%d chuỗi=[%@]", space.host, (int)status, (int)result,
              [chain componentsJoinedByString:@" ← "]);
        if (status == errSecSuccess && (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed)) {
            [challenge.sender useCredential:[NSURLCredential credentialForTrust:trust] forAuthenticationChallenge:challenge];
        } else {
            [challenge.sender cancelAuthenticationChallenge:challenge];
        }
        return;
    }
    [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _response = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    [_data setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self finish:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self finish:error];
}

@end
