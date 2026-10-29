// KeySystemHook.mm
// Triển khai hệ thống xác thực Key ImGui hoàn chỉnh cho iOS (arm64/arm64e)

#include "KeySystemHook.h"
#include "Config.h"
#include "KeychainHelper.h"
#include "Network.h"
#include "MetalOverlay.h"
#include "imgui.h"

#include <iostream>
#include <string>
#include <thread>
#include <future>
#include <cstring>
#include <chrono>
#include <atomic>
#import <UIKit/UIKit.h>

// --- Trạng thái toàn cục ---
bool isKeyValid = false;
bool g_MenuVisible = true;

// --- Trạng thái tĩnh nội bộ ---
static char keyBuffer[128] = "";
static bool isChecking = false;
static std::string statusMessage = "";
static std::string cachedExpireDate = "";
static std::future<KeyValidationResult> httpFuture;

// Thời gian đếm ngược
static auto g_StartTime = std::chrono::steady_clock::now();
static int countdownTimer = COUNTDOWN_MAX_SECONDS;
static bool g_HasInitialized = false;

// Luồng kiểm tra định kỳ (5 phút)
static std::thread g_RecheckThread;
static std::atomic<bool> g_ShouldStopRecheck(false);

// =========================================================================
// HÀM BẮT ĐẦU XÁC THỰC KEY
// =========================================================================
static void TriggerKeyVerification(const std::string& keyStr) {
    if (keyStr.empty() || isChecking) return;
    
    isChecking = true;
    statusMessage = "Dang ket noi va xac thuc...";

    // Sao chép key sang std::string riêng trước khi gửi sang thread khác (tránh data race trên keyBuffer)
    std::string keyCopy = keyStr;
    httpFuture = std::async(std::launch::async, [keyCopy]() {
        NSString *nsKey = [NSString stringWithUTF8String:keyCopy.c_str()];
        return [NetworkService validateKey:nsKey];
    });
}

// =========================================================================
// LUỒNG KIỂM TRA LẠI ĐỊNH KỲ (RE-CHECK BACKGROUND THREAD)
// =========================================================================
static void StartPeriodicRecheckWorker() {
    g_RecheckThread = std::thread([]() {
        while (!g_ShouldStopRecheck.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(RECHECK_INTERVAL_SEC));
            if (g_ShouldStopRecheck.load()) break;

            if (isKeyValid && strlen(keyBuffer) > 0) {
                NSString *nsKey = [NSString stringWithUTF8String:keyBuffer];
                KeyValidationResult res = [NetworkService validateKey:nsKey];
                
                if (!res.success) {
                    NSLog(@"[KeySystem] Re-check that bai: %s. Khoa game va yeu cau nhap lai key!", res.message.c_str());
                    isKeyValid = false;
                    g_MenuVisible = true;
                    [KeychainHelper deleteKey];
                    memset(keyBuffer, 0, sizeof(keyBuffer));
                    statusMessage = "Key da het han hoac bi thu hoi! Vui long nhap lai.";
                    // Reset thời gian đếm ngược
                    g_StartTime = std::chrono::steady_clock::now();
                    SetKeyOverlayActive(true);
                } else {
                    cachedExpireDate = res.expireDate;
                    NSLog(@"[KeySystem] Re-check thanh cong. Han dung: %s", res.expireDate.c_str());
                }
            }
        }
    });
    g_RecheckThread.detach();
}

// =========================================================================
// KHỞI TẠO HỆ THỐNG KEY
// =========================================================================
void InitKeySystem() {
    if (g_HasInitialized) return;
    g_HasInitialized = true;

    g_StartTime = std::chrono::steady_clock::now();

    // 1. Tự động đọc key đã lưu từ Keychain
    NSString *savedKey = [KeychainHelper loadKey];
    if (savedKey && savedKey.length > 0) {
        strncpy(keyBuffer, [savedKey UTF8String], sizeof(keyBuffer) - 1);
        keyBuffer[sizeof(keyBuffer) - 1] = '\0';
        NSLog(@"[KeySystem] Tim thay key trong Keychain: %s. Bat dau xac thuc ngam...", keyBuffer);
        TriggerKeyVerification(keyBuffer);
    }

    // 2. Bắt đầu luồng kiểm tra định kỳ
    StartPeriodicRecheckWorker();
}

// =========================================================================
// GIAO DIỆN NHẬP KEY (TỰ ĐỘNG TẮT POP-UP KHI KEY ĐÚNG ĐỂ VÀO THẲNG GAME)
// =========================================================================
void DrawKeySystemMenu() {
    // 1. Nếu key đã hợp lệ -> Tắt hẳn pop-up, không vẽ bất kỳ menu hay nút nổi nào
    if (isKeyValid) {
        return;
    }

    // 2. Cập nhật Countdown Timer thật theo thời gian steady_clock
    auto now = std::chrono::steady_clock::now();
    int elapsed = (int)std::chrono::duration_cast<std::chrono::seconds>(now - g_StartTime).count();
    countdownTimer = COUNTDOWN_MAX_SECONDS - elapsed;

    // Thoát ứng dụng nếu hết thời gian mà chưa kích hoạt
    if (countdownTimer <= 0) {
        NSLog(@"[KeySystem] Het han %d giay nhap key. Thoat ung dung!", COUNTDOWN_MAX_SECONDS);
        exit(0);
    }

    // 3. Xử lý kết quả request kiểm tra key nếu đang check
    if (isChecking && httpFuture.valid() &&
        httpFuture.wait_for(std::chrono::milliseconds(0)) == std::future_status::ready) {
        KeyValidationResult res = httpFuture.get();
        isChecking = false;

        if (res.success) {
            isKeyValid = true;
            g_MenuVisible = false;
            statusMessage = res.message;
            cachedExpireDate = res.expireDate;
            RequestKeyboard(false);
            
            // Lưu key hợp lệ vào Keychain cho lần khởi động sau
            NSString *nsKey = [NSString stringWithUTF8String:keyBuffer];
            [KeychainHelper saveKey:nsKey];
            SetKeyOverlayActive(false);
            NSLog(@"[KeySystem] Xac thuc thanh cong! Da luu vao Keychain, dong pop-up va mo Menu Hack.");
            return;
        } else {
            isKeyValid = false;
            g_MenuVisible = true;
            statusMessage = res.message.empty() ? "Key sai hoac khong hop le! Vui long nhap lai." : res.message;
            [KeychainHelper deleteKey];
            memset(keyBuffer, 0, sizeof(keyBuffer));
            NSLog(@"[KeySystem] Xac thuc that bai: %s", statusMessage.c_str());
        }
    }

    // Vẽ lớp nền mờ che toàn màn hình khi chưa nhập đúng key
    ImVec2 displaySize = ImGui::GetIO().DisplaySize;
    ImGui::GetBackgroundDrawList()->AddRectFilled(
        ImVec2(0.0f, 0.0f),
        displaySize,
        IM_COL32(0, 0, 0, 150)
    );

    // 4. Vẽ cửa sổ ImGui Nhập Key
    ImVec2 center = ImVec2(ImGui::GetIO().DisplaySize.x * 0.5f, ImGui::GetIO().DisplaySize.y * 0.5f);
    // Khi đang mở bàn phím, nâng cửa sổ lên cao để bàn phím không che ô nhập key
    if (ImGui::GetIO().WantTextInput) {
        ImGui::SetNextWindowPos(ImVec2(center.x, 25), ImGuiCond_Always, ImVec2(0.5f, 0.0f));
    } else {
        ImGui::SetNextWindowPos(center, ImGuiCond_FirstUseEver, ImVec2(0.5f, 0.5f));
    }
    ImGui::SetNextWindowSize(ImVec2(340, 310), ImGuiCond_FirstUseEver);
    ImGui::Begin("XAC THUC BAN QUYEN", nullptr,
                 ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse);

    ImGui::TextColored(ImVec4(1.0f, 0.4f, 0.4f, 1.0f),
                       "App se tu thoat sau: %d giay", countdownTimer);
    ImGui::Separator();
    ImGui::Spacing();

    // Hiển thị HWID và nút Copy HWID
    NSString *hwidStr = [NetworkService getDeviceHWID];
    ImGui::Text("HWID Thiet bi:");
    ImGui::TextDisabled("%s", [hwidStr UTF8String]);
    if (ImGui::Button("Sao chep HWID", ImVec2(130, 26))) {
        [UIPasteboard generalPasteboard].string = hwidStr;
        statusMessage = "Da sao chep HWID vao Clipboard!";
    }

    ImGui::Spacing();
    ImGui::Text("Nhap Ma Key:");
    if (ImGui::InputText("##key", keyBuffer, IM_ARRAYSIZE(keyBuffer))) {
        // Text updated
    }
    if (ImGui::IsItemClicked()) {
        RequestKeyboard(true);
    }

    ImGui::Spacing();

    // Nút Dán Key từ Clipboard
    if (ImGui::Button("Dan Key", ImVec2(75, 28))) {
        NSString *clip = [UIPasteboard generalPasteboard].string;
        if (clip && clip.length > 0) {
            strncpy(keyBuffer, [clip UTF8String], sizeof(keyBuffer) - 1);
            keyBuffer[sizeof(keyBuffer) - 1] = '\0';
        }
    }

    // Nút mở Bàn Phím iOS
    ImGui::SameLine();
    if (ImGui::Button("Ban Phim", ImVec2(80, 28))) {
        RequestKeyboard(true);
    }

    // Nút đóng bàn phím nếu đang mở
    if (ImGui::GetIO().WantTextInput) {
        ImGui::SameLine();
        if (ImGui::Button("Dong [X]", ImVec2(70, 28))) {
            RequestKeyboard(false);
        }
    }

    ImGui::Spacing();

    // Nút Kích Hoạt Key
    if (!isChecking) {
        if (ImGui::Button("KICH HOAT KEY", ImVec2(-1, 40))) {
            if (strlen(keyBuffer) > 0) {
                TriggerKeyVerification(keyBuffer);
            } else {
                statusMessage = "Vui long nhap Key!";
            }
        }
    } else {
        ImGui::BeginDisabled();
        ImGui::Button("DANG XAC THUC VOI SERVER...", ImVec2(-1, 40));
        ImGui::EndDisabled();
    }

    // Hiển thị thông báo trạng thái
    if (!statusMessage.empty()) {
        ImGui::Spacing();
        ImVec4 color = isKeyValid ? ImVec4(0.2f, 1.0f, 0.4f, 1.0f) : ImVec4(1.0f, 0.3f, 0.3f, 1.0f);
        ImGui::TextColored(color, "%s", statusMessage.c_str());
    }

    ImGui::End();
}
