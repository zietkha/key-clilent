TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

# Tắt cydia substrate để dylib chạy độc lập trên máy chưa Jailbreak (Sideload / IPA Injection)
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
KeySystem_CFLAGS = -fobjc-arc -Iimgui
KeySystem_CCFLAGS = -std=c++17 -fobjc-arc -Iimgui
KeySystem_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-all::
	@echo "=========================================================="
	@echo "Build hoan tat! File dylib nam tai:"
	@echo "  .theos/obj/debug/KeySystem.dylib (neu build debug)"
	@echo "  hoac: .theos/obj/KeySystem.dylib (neu build FINALPACKAGE=1)"
	@echo "=========================================================="
