#pragma once
#import <Foundation/Foundation.h>
#include <string>
#include <map>

// Kết quả xác thực key từ server
struct KeyValidationResult {
    bool success = false;
    std::string message = "";
    std::string expireDate = "";
    std::string hwid = "";
    long timestamp = 0;
};

// Cấu hình dữ liệu tải từ server sau khi key hợp lệ
struct ServerConfig {
    bool loaded = false;
    std::string version = "1.0.0";
    std::string announcement = "";
    std::map<std::string, bool> featureToggles;
};

// Hàm gửi HTTP GET đồng bộ qua NSURLSession + semaphore (timeout 10s)
std::string HttpGetRequest(const std::string& urlString);

@interface NetworkService : NSObject

/// Lấy HWID thiết bị (identifierForVendor)
+ (NSString *)getDeviceHWID;

/// URL-encode chuỗi tham số
+ (NSString *)urlEncode:(NSString *)string;

/// Tính toán chữ ký HMAC-SHA256
+ (NSString *)computeHMACSHA256:(NSString *)data key:(NSString *)key;

/// Gửi request kiểm tra key tới server và parse JSON
+ (KeyValidationResult)validateKey:(NSString *)key;

/// Tải cấu hình tính năng/thông báo từ server
+ (ServerConfig)fetchServerConfig:(NSString *)key;

@end
