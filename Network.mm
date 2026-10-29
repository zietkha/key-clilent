#import "Network.h"
#import "Config.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonHMAC.h>

std::string HttpGetRequest(const std::string& urlString) {
    @autoreleasepool {
        NSString *nsUrlStr = [NSString stringWithUTF8String:urlString.c_str()];
        NSURL *url = [NSURL URLWithString:nsUrlStr];
        if (!url) {
            NSLog(@"[KeySystem] URL khong hop le: %@", nsUrlStr);
            return "";
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                           timeoutInterval:HTTP_TIMEOUT_SECONDS];
        [request setHTTPMethod:@"GET"];
        [request setValue:@"iOS-KeySystem-Client/1.0" forHTTPHeaderField:@"User-Agent"];

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block std::string responseString = "";

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
        config.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && data && [(NSHTTPURLResponse *)response statusCode] == 200) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (str) {
                    responseString = [str UTF8String];
                }
            } else {
                NSLog(@"[KeySystem] HTTP Request loi: %@ (Code: %ld)",
                      error ? error.localizedDescription : @"Unknown",
                      (long)[(NSHTTPURLResponse *)response statusCode]);
            }
            dispatch_semaphore_signal(semaphore);
        }];

        [task resume];
        
        // Timeout chờ semaphore tối đa (HTTP_TIMEOUT_SECONDS + 1s)
        dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((HTTP_TIMEOUT_SECONDS + 1.0) * NSEC_PER_SEC));
        if (dispatch_semaphore_wait(semaphore, timeoutTime) != 0) {
            [task cancel];
            NSLog(@"[KeySystem] HTTP Request da bi timeout!");
        }
        
        [session finishTasksAndInvalidate];
        return responseString;
    }
}

@implementation NetworkService

+ (NSString *)getDeviceHWID {
    NSString *hwid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (!hwid || hwid.length == 0) {
        hwid = @"00000000-0000-0000-0000-000000000000";
    }
    return hwid;
}

+ (NSString *)urlEncode:(NSString *)string {
    if (!string) return @"";
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet URLQueryAllowedCharacterSet].mutableCopy;
    [allowed removeCharactersInString:@"!*'();:@&=+$,/?%#[]"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

+ (NSString *)computeHMACSHA256:(NSString *)data key:(NSString *)key {
    const char *cKey  = [key cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cData = [data cStringUsingEncoding:NSUTF8StringEncoding];
    if (!cKey || !cData) return @"";
    
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", cHMAC[i]];
    }
    return [result lowercaseString];
}

+ (KeyValidationResult)validateKey:(NSString *)key {
    KeyValidationResult res;
    if (!key || key.length == 0) {
        res.success = false;
        res.message = "Vui long nhap Key!";
        return res;
    }

    NSString *hwid = [self getDeviceHWID];
    NSString *encodedKey = [self urlEncode:key];
    NSString *encodedHwid = [self urlEncode:hwid];

    NSString *fullUrl = [NSString stringWithFormat:@"%@%@?key=%@&hwid=%@",
                         SERVER_BASE_URL, ENDPOINT_CHECK_KEY, encodedKey, encodedHwid];

    std::string rawJson = HttpGetRequest([fullUrl UTF8String]);
    if (rawJson.empty()) {
        res.success = false;
        res.message = "Loi ket noi server hoac timeout!";
        return res;
    }

    NSData *jsonData = [NSData dataWithBytes:rawJson.data() length:rawJson.size()];
    NSError *jsonError = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

    if (jsonError || ![dict isKindOfClass:[NSDictionary class]]) {
        res.success = false;
        res.message = "Du lieu server tra ve khong hop le!";
        return res;
    }

    NSString *status = dict[@"status"];
    NSString *serverMsg = dict[@"message"] ?: @"";
    NSString *expire = dict[@"expire"] ?: @"";
    NSString *serverHwid = dict[@"hwid"] ?: @"";
    NSNumber *timestamp = dict[@"timestamp"] ?: @0;
    NSString *signature = dict[@"signature"] ?: @"";

    if (![status isEqualToString:@"success"]) {
        res.success = false;
        res.message = serverMsg.length > 0 ? [serverMsg UTF8String] : "Key khong hop le hoac bi khoa!";
        return res;
    }

    // 1. Kiểm tra HWID (nếu server trả về hwid)
    if (serverHwid.length > 0 && ![serverHwid isEqualToString:hwid]) {
        res.success = false;
        res.message = "Key da bi khoa cho thiet bi khac!";
        return res;
    }

    // 2. Kiểm tra hạn dùng
    if (expire.length > 0) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [df setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:7 * 3600]]; // GMT+7
        NSDate *expireDate = [df dateFromString:expire];
        if (expireDate && [[NSDate date] compare:expireDate] == NSOrderedDescending) {
            res.success = false;
            res.message = "Key da het han su dung!";
            return res;
        }
    }

    // 3. Kiểm tra chữ ký HMAC (nếu server cung cấp chữ ký)
    if (signature.length > 0) {
        NSString *canonical = [NSString stringWithFormat:@"%@:%@:%@:%lld",
                               status, expire, serverHwid, [timestamp longLongValue]];
        NSString *expectedSign = [self computeHMACSHA256:canonical key:HMAC_SECRET_KEY];
        if (![signature.lowercaseString isEqualToString:expectedSign.lowercaseString]) {
            res.success = false;
            res.message = "Chu ky bao mat server khong khop!";
            return res;
        }
    }

    res.success = true;
    res.message = serverMsg.length > 0 ? [serverMsg UTF8String] : "Xac thuc thanh cong!";
    res.expireDate = [expire UTF8String];
    res.hwid = [serverHwid UTF8String];
    res.timestamp = [timestamp longValue];
    return res;
}

+ (ServerConfig)fetchServerConfig:(NSString *)key {
    ServerConfig cfg;
    NSString *hwid = [self getDeviceHWID];
    NSString *encodedKey = [self urlEncode:key];
    NSString *encodedHwid = [self urlEncode:hwid];

    NSString *fullUrl = [NSString stringWithFormat:@"%@%@?key=%@&hwid=%@",
                         SERVER_BASE_URL, ENDPOINT_GET_CONFIG, encodedKey, encodedHwid];

    std::string rawJson = HttpGetRequest([fullUrl UTF8String]);
    if (rawJson.empty()) return cfg;

    NSData *jsonData = [NSData dataWithBytes:rawJson.data() length:rawJson.size()];
    NSError *err = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&err];

    if (!err && [dict isKindOfClass:[NSDictionary class]]) {
        cfg.loaded = true;
        if (dict[@"version"]) cfg.version = [dict[@"version"] UTF8String];
        if (dict[@"announcement"]) cfg.announcement = [dict[@"announcement"] UTF8String];

        NSDictionary *features = dict[@"features"];
        if ([features isKindOfClass:[NSDictionary class]]) {
            for (NSString *fKey in features) {
                cfg.featureToggles[[fKey UTF8String]] = [features[fKey] boolValue];
            }
        }
    }
    return cfg;
}

@end
