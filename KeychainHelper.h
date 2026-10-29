#pragma once
#import <Foundation/Foundation.h>

@interface KeychainHelper : NSObject

/// Lưu chuỗi key vào Keychain an toàn
+ (BOOL)saveKey:(NSString *)key;

/// Đọc key đã lưu trong Keychain (trả về nil nếu chưa lưu)
+ (NSString *)loadKey;

/// Xóa key khỏi Keychain (khi key hết hạn hoặc đăng xuất)
+ (BOOL)deleteKey;

@end
