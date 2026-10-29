#pragma once
#include <string>

// Trạng thái toàn cục
extern bool isKeyValid;
extern bool g_MenuVisible;

// Khởi tạo hệ thống key (load từ Keychain nếu có)
void InitKeySystem();

// Render giao diện Key System & Main Menu bằng Dear ImGui
void DrawKeySystemMenu();

// Hàm mẫu Menu chính (gọi sau khi xác thực key thành công)
void DrawMainModMenu();
