TARGET := iphone:clang:latest:14.0
ARCHS := arm64

KeySystem_USE_SUBSTRATE = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KeySystem

KeySystem_FILES = \
	MetalOverlay.mm \
	KeySystemHook.mm \
	Network.mm \
	KeychainHelper.mm \
	imgui/imgui.cpp \
	imgui/imgui_draw.cpp \
	imgui/imgui_tables.cpp \
	imgui/imgui_widgets.cpp \
	imgui/imgui_impl_metal.mm

KeySystem_FRAMEWORKS = UIKit Metal MetalKit Foundation QuartzCore Security
KeySystem_CFLAGS = -fobjc-arc -fvisibility=hidden -Iimgui -I.
KeySystem_CCFLAGS = -std=c++17 -fobjc-arc -fvisibility=hidden -fvisibility-inlines-hidden -Iimgui -I.
KeySystem_OBJCCFLAGS = -std=c++17 -fobjc-arc -fvisibility=hidden -fvisibility-inlines-hidden -Iimgui -I.
KeySystem_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
