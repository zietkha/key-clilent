#import "KeychainHelper.h"
#import "Config.h"
#import <Security/Security.h>

@implementation KeychainHelper

+ (NSMutableDictionary *)baseQuery {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: KEYCHAIN_KEY_ACCOUNT
    } mutableCopy];
}

+ (BOOL)saveKey:(NSString *)key {
    if (!key || key.length == 0) return NO;
    
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *query = [self baseQuery];
    
    // Kiểm tra xem key đã tồn tại chưa
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    if (status == errSecSuccess) {
        // Đã có -> Cập nhật
        NSDictionary *attributesToUpdate = @{
            (__bridge id)kSecValueData: data
        };
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributesToUpdate);
    } else {
        // Chưa có -> Thêm mới
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    
    return (status == errSecSuccess);
}

+ (NSString *)loadKey {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    
    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    return nil;
}

+ (BOOL)deleteKey {
    NSMutableDictionary *query = [self baseQuery];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return (status == errSecSuccess || status == errSecItemNotFound);
}

@end
