#import "MetalOverlay.h"
#import "KeySystemHook.h"
#include "imgui.h"
#include "imgui_impl_metal.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

static PassthroughWindow *g_OverlayWindow = nil;
static MetalOverlayView *g_ActiveMetalView = nil;
static id<MTLCommandQueue> g_CommandQueue = nil;
static ImGuiContext *g_KeyImGuiContext = nullptr;

// Danh sách các cửa sổ / view của Menu Hack trong IPA bị tạm ẩn khi chưa nhập key
static NSHashTable<UIWindow *> *g_HiddenModWindows = nil;
static NSHashTable<UIView *> *g_HiddenModViews = nil;

// Tìm cửa sổ chính (Main Game Window) của game gốc
static UIWindow *GetHostGameWindow() {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w != g_OverlayWindow && w.rootViewController && w.windowLevel == UIWindowLevelNormal) {
                        NSString *clsName = NSStringFromClass([w class]);
                        if (![clsName hasPrefix:@"UIText"] && ![clsName hasPrefix:@"UIRemote"] && ![clsName hasPrefix:@"_UI"]) {
                            return w;
                        }
                    }
                }
            }
        }
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w != g_OverlayWindow && w.rootViewController && w.windowLevel == UIWindowLevelNormal) {
            NSString *clsName = NSStringFromClass([w class]);
            if (![clsName hasPrefix:@"UIText"] && ![clsName hasPrefix:@"UIRemote"] && ![clsName hasPrefix:@"_UI"]) {
                return w;
            }
        }
    }
    return nil;
}

// Kiểm tra xem UIWindow có phải cửa sổ hệ thống (bàn phím iOS) hay không
static bool IsSystemKeyboardOrTextWindow(UIWindow *w) {
    if (!w) return true;
    NSString *cls = NSStringFromClass([w class]);
    if ([cls hasPrefix:@"UITextEffects"] ||
        [cls hasPrefix:@"UIRemoteKeyboard"] ||
        [cls hasPrefix:@"UIInputWindow"] ||
        [cls hasPrefix:@"_UI"] ||
        [cls hasPrefix:@"UISystemKeyboard"]) {
        return true;
    }
    return false;
}

// Ẩn Menu Hack của game khi chưa nhập Key (showModMenu = false)
// và Mở lại Menu Hack của game ngay khi nhập đúng Key (showModMenu = true)
static void SyncExternalModMenuVisibility(bool showModMenu) {
    if (!g_HiddenModWindows) {
        g_HiddenModWindows = [NSHashTable weakObjectsHashTable];
    }
    if (!g_HiddenModViews) {
        g_HiddenModViews = [NSHashTable weakObjectsHashTable];
    }

    if (showModMenu) {
        // Khi đã nhập đúng Key -> Khôi phục toàn bộ cửa sổ và nút/menu của dylib hack trong game
        for (UIWindow *w in g_HiddenModWindows) {
            if (w && w != g_OverlayWindow) {
                w.alpha = 1.0f;
                w.userInteractionEnabled = YES;
            }
        }
        [g_HiddenModWindows removeAllObjects];

        for (UIView *v in g_HiddenModViews) {
            if (v) {
                v.alpha = 1.0f;
                v.userInteractionEnabled = YES;
            }
        }
        [g_HiddenModViews removeAllObjects];
        return;
    }

    // Khi CHƯA nhập đúng Key -> Tạm ẩn mọi cửa sổ/view của Menu Hack khác trong IPA
    UIWindow *hostWin = GetHostGameWindow();

    NSMutableArray<UIWindow *> *allWindows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                [allWindows addObjectsFromArray:ws.windows];
            }
        }
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (![allWindows containsObject:w]) {
            [allWindows addObject:w];
        }
    }

    // 1. Ẩn các UIWindow phụ do dylib Menu Hack tạo ra
    for (UIWindow *w in allWindows) {
        if (w == g_OverlayWindow || w == hostWin || IsSystemKeyboardOrTextWindow(w)) {
            continue;
        }
        if (w.alpha > 0.01f || w.userInteractionEnabled) {
            [g_HiddenModWindows addObject:w];
            w.alpha = 0.0f;
            w.userInteractionEnabled = NO;
        }
    }

    // 2. Ẩn các subview (nút nổi / ImGui MTKView / menu view) được dylib Menu Hack gắn vào cửa sổ game chính
    if (hostWin) {
        UIView *rootView = hostWin.rootViewController ? hostWin.rootViewController.view : nil;
        for (UIView *sub in hostWin.subviews) {
            if (sub == rootView) continue;
            NSString *cls = NSStringFromClass([sub class]);
            if ([cls hasPrefix:@"UITransitionView"] || [cls hasPrefix:@"_UI"]) continue;
            if (sub.alpha > 0.01f || sub.userInteractionEnabled) {
                [g_HiddenModViews addObject:sub];
                sub.alpha = 0.0f;
                sub.userInteractionEnabled = NO;
            }
        }

        // Nếu dylib hack gắn subview trực tiếp vào rootView (ngoài view render đầu tiên của game)
        if (rootView && rootView.subviews.count > 1) {
            for (NSUInteger i = 1; i < rootView.subviews.count; i++) {
                UIView *sub = rootView.subviews[i];
                NSString *cls = NSStringFromClass([sub class]);
                if ([cls hasPrefix:@"_UI"]) continue;
                if (sub.alpha > 0.01f || sub.userInteractionEnabled) {
                    [g_HiddenModViews addObject:sub];
                    sub.alpha = 0.0f;
                    sub.userInteractionEnabled = NO;
                }
            }
        }
    }
}

void SetKeyOverlayActive(bool active) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (active) {
            // Chưa nhập đúng key: hiện bảng Key System và ẩn Menu Hack của game
            SyncExternalModMenuVisibility(false);
            if (g_OverlayWindow) {
                g_OverlayWindow.hidden = NO;
                g_OverlayWindow.userInteractionEnabled = YES;
            }
            if (g_ActiveMetalView) {
                g_ActiveMetalView.hidden = NO;
                g_ActiveMetalView.paused = NO;
                g_ActiveMetalView.userInteractionEnabled = YES;
            }
        } else {
            // Đã nhập đúng key: tắt hẳn bảng Key System và mở lại Menu Hack của game
            if (g_ActiveMetalView) {
                [g_ActiveMetalView resignFirstResponder];
                g_ActiveMetalView.paused = YES;
                g_ActiveMetalView.hidden = YES;
                g_ActiveMetalView.userInteractionEnabled = NO;
            }
            if (g_OverlayWindow) {
                g_OverlayWindow.hidden = YES;
                g_OverlayWindow.userInteractionEnabled = NO;
            }
            SyncExternalModMenuVisibility(true);
            NSLog(@"[KeySystem] Da tat pop-up Key System va mo khoa Menu Hack cua game!");
        }
    });
}

// =========================================================================
// PASSTHROUGH WINDOW: CHẶN CẢM ỨNG KHI CHƯA NHẬP KEY, XUYÊN THẤU KHI KEY ĐÚNG
// =========================================================================
@implementation PassthroughWindow

- (void)addSubview:(UIView *)view {
    // Nếu một dylib Menu Hack khác gọi [windows.lastObject addSubview:menuView] và trúng cửa sổ KeySystem,
    // tự động chuyển view đó sang cửa sổ chính của game để khi tắt pop-up key thì menu hack không bị mất!
    if (self.rootViewController && self.rootViewController.view &&
        view != self.rootViewController.view &&
        ![NSStringFromClass([view class]) hasPrefix:@"_UI"] &&
        ![NSStringFromClass([view class]) hasPrefix:@"UITransition"]) {
        UIWindow *hostWin = GetHostGameWindow();
        if (hostWin) {
            [hostWin addSubview:view];
            if (!isKeyValid) {
                if (!g_HiddenModViews) g_HiddenModViews = [NSHashTable weakObjectsHashTable];
                [g_HiddenModViews addObject:view];
                view.alpha = 0.0f;
                view.userInteractionEnabled = NO;
            }
            return;
        }
    }
    [super addSubview:view];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Khi đã xác thực key hợp lệ -> Truyền 100% cảm ứng xuống game và Menu Hack bên dưới
    if (isKeyValid) {
        return nil;
    }

    // Khi chưa nhập đúng key -> Chặn mọi thao tác chạm vào game và Menu Hack
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == nil) {
        return self.rootViewController.view;
    }
    return hitView;
}

@end

// =========================================================================
// CONTROLLER: ĐỒNG BỘ HOÀN TOÀN HƯỚNG HIỂN THỊ VỚI GAME GỐC
// =========================================================================
@implementation MetalOverlayViewController

- (UIViewController *)hostAppRootViewController {
    UIWindow *hostWin = GetHostGameWindow();
    if (hostWin && hostWin.rootViewController) {
        return hostWin.rootViewController;
    }
    return nil;
}

- (BOOL)shouldAutorotate {
    UIViewController *host = [self hostAppRootViewController];
    if (host) return [host shouldAutorotate];
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *host = [self hostAppRootViewController];
    if (host) return [host supportedInterfaceOrientations];
    return UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIViewController *host = [self hostAppRootViewController];
    if (host) return [host preferredInterfaceOrientationForPresentation];
    return UIInterfaceOrientationUnknown;
}

- (BOOL)prefersStatusBarHidden {
    UIViewController *host = [self hostAppRootViewController];
    if (host) return [host prefersStatusBarHidden];
    return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (g_KeyImGuiContext) {
            ImGui::SetCurrentContext(g_KeyImGuiContext);
            ImGuiIO& io = ImGui::GetIO();
            CGFloat scale = [UIScreen mainScreen].scale;
            io.DisplaySize = ImVec2(size.width, size.height);
            io.DisplayFramebufferScale = ImVec2(scale, scale);
        }
    }];
}
@end

// =========================================================================
// METAL VIEW RENDER IMGUI & HỖ TRỢ BÀN PHÍM ẢO IOS (UIKeyInput)
// =========================================================================
void RequestKeyboard(bool show) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_ActiveMetalView) {
            if (show) [g_ActiveMetalView becomeFirstResponder];
            else [g_ActiveMetalView resignFirstResponder];
        }
    });
}

@interface MetalOverlayView () <MTKViewDelegate>
@end

@implementation MetalOverlayView

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.delegate = self;
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.framebufferOnly = YES;
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        self.contentScaleFactor = [UIScreen mainScreen].scale;
        self.multipleTouchEnabled = NO;
        self.userInteractionEnabled = YES;
        g_ActiveMetalView = self;
    }
    return self;
}

#pragma mark - UIKeyInput Protocol (Bàn phím ảo iOS)

- (BOOL)canBecomeFirstResponder {
    return !isKeyValid;
}

- (BOOL)hasText {
    return YES;
}

- (void)insertText:(NSString *)text {
    if (!g_KeyImGuiContext) return;
    ImGui::SetCurrentContext(g_KeyImGuiContext);
    ImGuiIO& io = ImGui::GetIO();
    if ([text isEqualToString:@"\n"]) {
        io.AddKeyEvent(ImGuiKey_Enter, true);
        io.AddKeyEvent(ImGuiKey_Enter, false);
        [self resignFirstResponder];
        return;
    }
    const char *utf8 = [text UTF8String];
    if (utf8) {
        io.AddInputCharactersUTF8(utf8);
    }
}

- (void)deleteBackward {
    if (!g_KeyImGuiContext) return;
    ImGui::SetCurrentContext(g_KeyImGuiContext);
    ImGuiIO& io = ImGui::GetIO();
    io.AddKeyEvent(ImGuiKey_Backspace, true);
    io.AddKeyEvent(ImGuiKey_Backspace, false);
}

- (UITextAutocorrectionType)autocorrectionType {
    return UITextAutocorrectionTypeNo;
}

- (UITextAutocapitalizationType)autocapitalizationType {
    return UITextAutocapitalizationTypeNone;
}

- (UIKeyboardType)keyboardType {
    return UIKeyboardTypeASCIICapable;
}

- (UIReturnKeyType)returnKeyType {
    return UIReturnKeyDone;
}

#pragma mark - Touch Handling

- (void)handleTouch:(UITouch *)touch phase:(UITouchPhase)phase {
    if (!g_KeyImGuiContext || isKeyValid) return;
    ImGui::SetCurrentContext(g_KeyImGuiContext);
    CGPoint loc = [touch locationInView:self];
    ImGuiIO& io = ImGui::GetIO();
    
    io.AddMousePosEvent((float)loc.x, (float)loc.y);
    if (phase == UITouchPhaseBegan) {
        io.AddMouseButtonEvent(0, true);
    } else if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
        io.AddMouseButtonEvent(0, false);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] phase:UITouchPhaseBegan];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] phase:UITouchPhaseMoved];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] phase:UITouchPhaseEnded];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] phase:UITouchPhaseCancelled];
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        if (!g_KeyImGuiContext) return;

        // Nếu key đã hợp lệ -> Ngừng render overlay và mở khóa Menu Hack của game
        if (isKeyValid) {
            SetKeyOverlayActive(false);
            return;
        }

        // Trong lúc chưa nhập đúng key, liên tục giữ ẩn các Menu Hack khác trong IPA
        SyncExternalModMenuVisibility(false);

        ImGui::SetCurrentContext(g_KeyImGuiContext);
        ImGuiIO& io = ImGui::GetIO();
        CGFloat scale = [UIScreen mainScreen].scale;
        io.DisplaySize = ImVec2(view.bounds.size.width, view.bounds.size.height);
        io.DisplayFramebufferScale = ImVec2(scale, scale);

        // Tự động bật/tắt bàn phím ảo iOS theo trạng thái WantTextInput của ImGui
        static bool lastWantTextInput = false;
        if (io.WantTextInput != lastWantTextInput) {
            lastWantTextInput = io.WantTextInput;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (io.WantTextInput && !isKeyValid) {
                    if (![view isFirstResponder]) {
                        [view becomeFirstResponder];
                    }
                } else {
                    if ([view isFirstResponder]) {
                        [view resignFirstResponder];
                    }
                }
            });
        }

        // Tính toán DeltaTime
        static CFTimeInterval lastTime = 0.0;
        CFTimeInterval currentTime = CACurrentMediaTime();
        if (lastTime > 0.0) {
            io.DeltaTime = (float)(currentTime - lastTime);
        } else {
            io.DeltaTime = 1.0f / 60.0f;
        }
        lastTime = currentTime;

        MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
        if (!renderPassDescriptor) return;

        id<MTLCommandBuffer> commandBuffer = [g_CommandQueue commandBuffer];
        if (!commandBuffer) return;

        ImGui_ImplMetal_NewFrame(renderPassDescriptor);
        ImGui::NewFrame();

        // Vẽ bảng xác thực Key System
        DrawKeySystemMenu();

        ImGui::Render();

        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        if (renderEncoder) {
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);
            [renderEncoder endEncoding];
            [commandBuffer presentDrawable:view.currentDrawable];
        }
        [commandBuffer commit];
    }
}

@end

// =========================================================================
// THIẾT LẬP GIAO DIỆN IMGUI TỐI ƯU CHO MOBILE
// =========================================================================
static void SetupImGuiStyle() {
    ImGuiStyle& style = ImGui::GetStyle();
    
    style.WindowRounding    = 8.0f;
    style.FrameRounding     = 5.0f;
    style.PopupRounding     = 6.0f;
    style.ScrollbarRounding = 9.0f;
    style.GrabRounding      = 5.0f;
    style.TabRounding       = 4.0f;
    style.WindowBorderSize  = 1.0f;
    style.FrameBorderSize   = 0.0f;
    
    // Tăng kích thước vùng chạm cho màn hình cảm ứng
    style.TouchExtraPadding = ImVec2(4.0f, 4.0f);
    style.ItemSpacing       = ImVec2(8.0f, 8.0f);
    style.FramePadding      = ImVec2(8.0f, 6.0f);

    ImVec4* colors = style.Colors;
    colors[ImGuiCol_Text]                  = ImVec4(1.00f, 1.00f, 1.00f, 1.00f);
    colors[ImGuiCol_WindowBg]              = ImVec4(0.08f, 0.09f, 0.12f, 0.94f);
    colors[ImGuiCol_Border]                = ImVec4(0.25f, 0.28f, 0.35f, 0.60f);
    colors[ImGuiCol_TitleBg]               = ImVec4(0.12f, 0.14f, 0.18f, 1.00f);
    colors[ImGuiCol_TitleBgActive]         = ImVec4(0.18f, 0.22f, 0.30f, 1.00f);
    colors[ImGuiCol_Button]                = ImVec4(0.20f, 0.35f, 0.60f, 1.00f);
    colors[ImGuiCol_ButtonHovered]         = ImVec4(0.28f, 0.45f, 0.75f, 1.00f);
    colors[ImGuiCol_ButtonActive]          = ImVec4(0.15f, 0.28f, 0.50f, 1.00f);
    colors[ImGuiCol_FrameBg]               = ImVec4(0.15f, 0.17f, 0.22f, 1.00f);
    colors[ImGuiCol_FrameBgHovered]        = ImVec4(0.22f, 0.25f, 0.32f, 1.00f);
    colors[ImGuiCol_FrameBgActive]         = ImVec4(0.28f, 0.32f, 0.40f, 1.00f);
    colors[ImGuiCol_CheckMark]             = ImVec4(0.25f, 0.85f, 0.45f, 1.00f);
}

// =========================================================================
// KHỞI TẠO OVERLAY VÀ HOOK VÀO APP
// =========================================================================
static void InitializeOverlay() {
    NSLog(@"[KeySystem] Khoi tao ImGui Metal Overlay...");

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[KeySystem] LOI: Thiet bi khong ho tro Metal!");
        return;
    }

    g_CommandQueue = [device newCommandQueue];

    // Khởi tạo ImGui Context cô lập riêng cho KeySystem
    IMGUI_CHECKVERSION();
    g_KeyImGuiContext = ImGui::CreateContext();
    ImGui::SetCurrentContext(g_KeyImGuiContext);
    ImGuiIO& io = ImGui::GetIO();
    (void)io;
    io.IniFilename = NULL; // Không lưu cấu hình ra file

    SetupImGuiStyle();

    // Khởi tạo ImGui Metal Backend
    ImGui_ImplMetal_Init(device);

    // Khởi tạo hệ thống Key
    InitKeySystem();

    // Tạo UIWindow trên main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        
        // Hỗ trợ iOS 13+ UIWindowScene
        UIWindowScene *activeScene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive &&
                    [scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }

        if (activeScene) {
            g_OverlayWindow = [[PassthroughWindow alloc] initWithWindowScene:activeScene];
        } else {
            g_OverlayWindow = [[PassthroughWindow alloc] initWithFrame:screenBounds];
        }

        g_OverlayWindow.windowLevel = UIWindowLevelStatusBar - 1.0;
        g_OverlayWindow.backgroundColor = [UIColor clearColor];
        g_OverlayWindow.hidden = NO;

        MetalOverlayViewController *vc = [[MetalOverlayViewController alloc] init];
        g_OverlayWindow.rootViewController = vc;

        MetalOverlayView *metalView = [[MetalOverlayView alloc] initWithFrame:screenBounds device:device];
        metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view = metalView;

        // Tạm ẩn Menu Hack của game cho tới khi nhập đúng Key
        SyncExternalModMenuVisibility(false);

        // Chỉ hiển thị overlay mà KHÔNG cướp KeyWindow của game gốc
        [g_OverlayWindow setHidden:NO];
        NSLog(@"[KeySystem] Metal Overlay da khoi tao thanh cong tren UIWindow!");
    });
}

// =========================================================================
// CONSTRUCTOR HOOK (TU DONG CHAY KHI DYLIB DUOC LOAD)
// =========================================================================
__attribute__((constructor))
static void DylibEntrypoint() {
    NSLog(@"[KeySystem] Dylib da inject vao process! Delay 2.5s cho app san sang...");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InitializeOverlay();
    });
}
