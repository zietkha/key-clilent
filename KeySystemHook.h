#pragma once
#include <string>

// Trạng thái toàn cục
extern bool isKeyValid;
extern bool g_MenuVisible;

// Khởi tạo hệ thống key (load từ Keychain nếu có)
void InitKeySystem();

// Render giao diện xác thực Key bằng Dear ImGui (tự tắt khi key hợp lệ)
void DrawKeySystemMenu();
