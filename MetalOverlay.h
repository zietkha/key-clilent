#pragma once
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

// Đổi tên các class Objective-C để tránh xung đột với dylib Menu Hack của game
#define PassthroughWindow          TQTKeyPassthroughWindow
#define MetalOverlayViewController TQTKeyMetalOverlayViewController
#define MetalOverlayView           TQTKeyMetalOverlayView

@interface PassthroughWindow : UIWindow
@end

@interface MetalOverlayViewController : UIViewController
@end

@interface MetalOverlayView : MTKView <UIKeyInput>
@end

// Hàm điều khiển hiển thị/ẩn bàn phím ảo iOS
void RequestKeyboard(bool show);

// Bật/tắt pop-up Key System và đồng thời ẩn/mở khóa Menu Hack của game
void SetKeyOverlayActive(bool active);
