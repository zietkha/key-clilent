@echo off
echo ==========================================================
echo     DOWLOAD VA CAI DAT DEAR IMGUI CHO DU AN IOS (WINDOWS)
echo ==========================================================

if not exist imgui mkdir imgui

echo [1/3] Cloning ImGui v1.90.5...
if exist imgui_tmp rmdir /s /q imgui_tmp
git clone --depth 1 --branch v1.90.5 https://github.com/ocornut/imgui.git imgui_tmp

echo [2/3] Copying ImGui files to imgui\ ...
copy imgui_tmp\imconfig.h imgui\
copy imgui_tmp\imgui.h imgui\
copy imgui_tmp\imgui_internal.h imgui\
copy imgui_tmp\imstb_rectpack.h imgui\
copy imgui_tmp\imstb_textedit.h imgui\
copy imgui_tmp\imstb_truetype.h imgui\
copy imgui_tmp\imgui.cpp imgui\
copy imgui_tmp\imgui_draw.cpp imgui\
copy imgui_tmp\imgui_tables.cpp imgui\
copy imgui_tmp\imgui_widgets.cpp imgui\
copy imgui_tmp\backends\imgui_impl_metal.h imgui\
copy imgui_tmp\backends\imgui_impl_metal.mm imgui\

echo [3/3] Cleaning up...
rmdir /s /q imgui_tmp

echo ==========================================================
echo THANH CONG! Thu muc imgui\ da day du file san sang build!
echo ==========================================================
pause
