#import "MetalOverlay.h"
#import "KeySystemHook.h"
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

static PassthroughWindow *g_OverlayWindow = nil;
static id<MTLCommandQueue> g_CommandQueue = nil;

// Kiểm tra xem tọa độ chạm có nằm trong bất kỳ cửa sổ ImGui nào không
static bool IsTouchInsideAnyImGuiWindow(CGPoint pt) {
    ImGuiContext* g = ImGui::GetCurrentContext();
    if (!g) return false;
    
    // Nếu menu đang hiển thị hoặc nút nổi đang bật
    for (int i = 0; i < g->Windows.Size; i++) {
        ImGuiWindow* window = g->Windows[i];
        if (!window->WasActive || window->Hidden) continue;
        
        if (pt.x >= window->Rect().Min.x && pt.x <= window->Rect().Max.x &&
            pt.y >= window->Rect().Min.y && pt.y <= window->Rect().Max.y) {
            return true;
        }
    }
    return false;
}

// =========================================================================
// PASSTHROUGH WINDOW: CHO PHÉP CHẠM XUYÊN QUA GAME KHI KHÔNG BẤM MENU
// =========================================================================
@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // Nếu điểm chạm rơi vào chính Window hoặc Root View của Overlay
    if (hitView == self || hitView == self.rootViewController.view) {
        if (!IsTouchInsideAnyImGuiWindow(point)) {
            // Điểm chạm nằm ngoài các cửa sổ ImGui -> Trả về nil để iOS truyền cảm ứng xuống app/game gốc bên dưới
            return nil;
        }
    }
    return hitView;
}

@end

// =========================================================================
// CONTROLLER: ĐỒNG BỘ HOÀN TOÀN HƯỚNG HIỂN THỊ VỚI GAME GỐC
// =========================================================================
@implementation MetalOverlayViewController

- (UIViewController *)hostAppRootViewController {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w != self.view.window && w.rootViewController && !w.hidden) {
                        return w.rootViewController;
                    }
                }
            }
        }
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w != self.view.window && w.rootViewController && !w.hidden) {
            return w.rootViewController;
        }
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
        ImGuiIO& io = ImGui::GetIO();
        CGFloat scale = [UIScreen mainScreen].scale;
        io.DisplaySize = ImVec2(size.width, size.height);
        io.DisplayFramebufferScale = ImVec2(scale, scale);
    }];
}
@end

// =========================================================================
// METAL VIEW RENDER IMGUI
// =========================================================================
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
    }
    return self;
}

- (void)handleTouch:(UITouch *)touch phase:(UITouchPhase)phase {
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
        ImGuiIO& io = ImGui::GetIO();
        CGFloat scale = [UIScreen mainScreen].scale;
        io.DisplaySize = ImVec2(view.bounds.size.width, view.bounds.size.height);
        io.DisplayFramebufferScale = ImVec2(scale, scale);

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

        // Vẽ Key System & Main Menu
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

    // Khởi tạo ImGui Context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
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

        g_OverlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
        g_OverlayWindow.backgroundColor = [UIColor clearColor];
        g_OverlayWindow.hidden = NO;

        MetalOverlayViewController *vc = [[MetalOverlayViewController alloc] init];
        g_OverlayWindow.rootViewController = vc;

        MetalOverlayView *metalView = [[MetalOverlayView alloc] initWithFrame:screenBounds device:device];
        metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view = metalView;

        // Chỉ hiển thị overlay mà KHÔNG cướp KeyWindow của game gốc (tránh làm lệch hướng màn hình)
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
