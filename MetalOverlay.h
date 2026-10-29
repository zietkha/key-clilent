#pragma once
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

@interface PassthroughWindow : UIWindow
@end

@interface MetalOverlayViewController : UIViewController
@end

@interface MetalOverlayView : MTKView <UIKeyInput>
@end

// Hàm điều khiển hiển thị/ẩn bàn phím ảo iOS
void RequestKeyboard(bool show);
