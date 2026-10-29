<?php
// get_key.php - Server API kiểm tra Key và khóa HWID
// Đặt file này trên server https://tqtdev.2bd.net/get_key.php

header('Content-Type: application/json; charset=utf-8');
date_default_timezone_set('Asia/Ho_Chi_Minh');

// Khóa bí mật HMAC (phải giống hệt với HMAC_SECRET_KEY trong Config.h của dylib)
define('HMAC_SECRET_KEY', 'SecretKey_TQTDev_2026_Secure');

// File lưu trữ database key (đơn giản, dễ quản lý không cần MySQL)
$dbFile = __DIR__ . '/keys_db.json';

// Dữ liệu mẫu nếu file chưa tồn tại
if (!file_exists($dbFile)) {
    $initialData = [
        "VIP-TQT-2026-DEMO" => [
            "expire" => "2026-12-31 23:59:59",
            "hwid"   => "",      // Rỗng = chưa kích hoạt máy nào, kích hoạt lần đầu sẽ tự khóa
            "status" => "active",
            "note"   => "Key VIP 1 nam"
        ],
        "VIP-TQT-EXPIRED" => [
            "expire" => "2024-01-01 00:00:00",
            "hwid"   => "",
            "status" => "active",
            "note"   => "Key test het han"
        ],
        "VIP-TQT-LOCKED" => [
            "expire" => "2026-12-31 23:59:59",
            "hwid"   => "11111111-2222-3333-4444-555555555555",
            "status" => "active",
            "note"   => "Key da bi khoa cho may khac"
        ]
    ];
    file_put_contents($dbFile, json_encode($initialData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
}

$keysDB = json_decode(file_get_contents($dbFile), true) ?: [];

// Lấy tham số GET
$key  = trim($_GET['key'] ?? '');
$hwid = trim($_GET['hwid'] ?? '');

$timestamp = time();

function sendResponse($status, $message, $expire = '', $hwidVal = '') {
    global $timestamp;
    
    // Tính toán chữ ký HMAC-SHA256: status:expire:hwid:timestamp
    $canonical = "{$status}:{$expire}:{$hwidVal}:{$timestamp}";
    $signature = hash_hmac('sha256', $canonical, HMAC_SECRET_KEY);

    echo json_encode([
        'status'    => $status,
        'message'   => $message,
        'expire'    => $expire,
        'hwid'      => $hwidVal,
        'timestamp' => $timestamp,
        'signature' => $signature
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 1. Kiểm tra tham số đầu vào
if (empty($key)) {
    sendResponse('error', 'Vui lòng cung cấp key!');
}
if (empty($hwid)) {
    sendResponse('error', 'Thiếu thông tin HWID thiết bị!');
}

// 2. Kiểm tra key có tồn tại trong hệ thống không
if (!isset($keysDB[$key])) {
    sendResponse('error', 'Key không tồn tại trên hệ thống!');
}

$keyInfo = $keysDB[$key];

// 3. Kiểm tra trạng thái khóa thủ công của admin
if (($keyInfo['status'] ?? 'active') !== 'active') {
    sendResponse('error', 'Key đã bị admin vô hiệu hóa hoặc thu hồi!');
}

// 4. Kiểm tra hạn dùng
$expireTime = strtotime($keyInfo['expire']);
if ($expireTime === false || $timestamp > $expireTime) {
    sendResponse('error', 'Key đã hết hạn sử dụng (' . $keyInfo['expire'] . ')!', $keyInfo['expire']);
}

// 5. Kiểm tra và Khóa HWID
$boundHwid = trim($keyInfo['hwid'] ?? '');

if (empty($boundHwid)) {
    // Lần đầu kích hoạt -> Tự động gắn HWID máy này vào key
    $keysDB[$key]['hwid'] = $hwid;
    file_put_contents($dbFile, json_encode($keysDB, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    $boundHwid = $hwid;
} else {
    // Đã có HWID -> Kiểm tra có đúng máy đã kích hoạt không
    if (strcasecmp($boundHwid, $hwid) !== 0) {
        sendResponse('error', 'Key này đã bị khóa cho thiết bị khác! Không thể dùng trên máy này.');
    }
}

// 6. Trả về thành công kèm thông tin và chữ ký
sendResponse('success', 'Xác thực thành công!', $keyInfo['expire'], $boundHwid);
