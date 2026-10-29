#pragma once
#import <Foundation/Foundation.h>

// =========================================================================
// CẤU HÌNH MẠNG & SERVER (ĐẶT TẠI MỘ NƠI DUY NHẤT)
// =========================================================================
// Thay đổi domain và endpoint của server tại đây
#define SERVER_BASE_URL         @"https://tqtdev.2bd.net"
#define ENDPOINT_CHECK_KEY      @"/get_key.php"
#define ENDPOINT_GET_CONFIG     @"/get_config.php"

// Secret Key cho HMAC-SHA256 chống giả mạo response (khớp với server PHP)
#define HMAC_SECRET_KEY         @"SecretKey_TQTDev_2026_Secure"

// =========================================================================
// THỜI GIAN & BẢO MẬT
// =========================================================================
#define COUNTDOWN_MAX_SECONDS   60      // Hạn thời gian nhập key (giây), quá hạn tự exit(0)
#define RECHECK_INTERVAL_SEC    300     // Định kỳ kiểm tra lại key với server (5 phút)
#define HTTP_TIMEOUT_SECONDS    10.0    // Timeout cho request HTTP (giây)

// =========================================================================
// KEYCHAIN IDENTIFIER
// =========================================================================
#define KEYCHAIN_SERVICE        @"com.tqtdev.keysystem"
#define KEYCHAIN_KEY_ACCOUNT    @"saved_license_key"
