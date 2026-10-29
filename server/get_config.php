<?php
// get_config.php - Server API trả dữ liệu cấu hình & tính năng cho Menu sau khi key hợp lệ
// Đặt file này trên server https://tqtdev.2bd.net/get_config.php

header('Content-Type: application/json; charset=utf-8');
date_default_timezone_set('Asia/Ho_Chi_Minh');

$dbFile = __DIR__ . '/keys_db.json';
$keysDB = file_exists($dbFile) ? (json_decode(file_get_contents($dbFile), true) ?: []) : [];

$key  = trim($_GET['key'] ?? '');
$hwid = trim($_GET['hwid'] ?? '');

if (empty($key) || !isset($keysDB[$key])) {
    echo json_encode(['status' => 'error', 'message' => 'Key khong hop le']);
    exit;
}

$keyInfo = $keysDB[$key];
if (!empty($keyInfo['hwid']) && strcasecmp($keyInfo['hwid'], $hwid) !== 0) {
    echo json_encode(['status' => 'error', 'message' => 'HWID khong khop']);
    exit;
}

// Cấu hình tính năng động từ Server
$response = [
    'status'       => 'success',
    'version'      => '2.1.0-Release',
    'announcement' => 'Chuc mung ban da kich hoat thanh cong Menu VIP TQTDev! Chuc ban choi game vui ve.',
    'features'     => [
        'Aimbot Silent' => true,
        'ESP Box 2D'    => true,
        'ESP Bone'      => true,
        'No Recoil'     => true,
        'Speed Boost'   => false
    ]
];

echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
