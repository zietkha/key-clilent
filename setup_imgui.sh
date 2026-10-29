#!/bin/bash
set -e

echo "=========================================================="
echo "    DOWLOAD VA CAI DAT DEAR IMGUI CHO DU AN IOS           "
echo "=========================================================="

mkdir -p imgui

echo "[1/3] Đang clone repo Dear ImGui (tag v1.90.5)..."
rm -rf imgui_tmp
git clone --depth 1 --branch v1.90.5 https://github.com/ocornut/imgui.git imgui_tmp

echo "[2/3] Sao chep cac file core va Metal backend vao thu muc imgui/..."
cp imgui_tmp/imconfig.h imgui/
cp imgui_tmp/imgui.h imgui/
cp imgui_tmp/imgui_internal.h imgui/
cp imgui_tmp/imstb_rectpack.h imgui/
cp imgui_tmp/imstb_textedit.h imgui/
cp imgui_tmp/imstb_truetype.h imgui/
cp imgui_tmp/imgui.cpp imgui/
cp imgui_tmp/imgui_draw.cpp imgui/
cp imgui_tmp/imgui_tables.cpp imgui/
cp imgui_tmp/imgui_widgets.cpp imgui/

# Backend Metal cho iOS
cp imgui_tmp/backends/imgui_impl_metal.h imgui/
cp imgui_tmp/backends/imgui_impl_metal.mm imgui/

echo "[3/3] Don dep thu muc tam..."
rm -rf imgui_tmp

echo "=========================================================="
echo "THANH CONG! Cac file ImGui da nam san sang tai ./imgui/"
ls -la imgui
echo "=========================================================="
