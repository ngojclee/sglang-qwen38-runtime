#!/bin/bash
# ========================================================
# 🚀 1-Click Bootstrap Script for SGLang Qwen3.8
# Fast deployment for Vast.ai / RunPod with SGLang base image
# ========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_FILE="$REPO_DIR/patches/sglang_qwen38_working.patch"

echo "========================================================="
echo "🔍 1. Verifying SGLang Environment & Version Check"
echo "========================================================="

if ! command -v sglang &> /dev/null && ! python3 -c "import sglang" &> /dev/null; then
    echo "❌ Error: SGLang is not installed in the current environment."
    echo "👉 Please run on an instance with SGLang installed (e.g. lmsysorg/sglang:v0.5.16)."
    exit 1
fi

SGLANG_VERSION=$(python3 -c "import sglang; print(getattr(sglang, '__version__', 'unknown'))")
echo "📦 Detected SGLang Version: $SGLANG_VERSION"

if [[ "$SGLANG_VERSION" != "0.5.16"* && "$SGLANG_VERSION" != "0.5"* ]]; then
    echo "⚠️ Warning: Detected SGLang version ($SGLANG_VERSION) differs from baseline (0.5.16)."
    echo "👉 Checking patch compatibility..."
fi

echo "========================================================="
echo "🧩 2. Testing & Applying Qwen3.8 GDN & DFlash2 Patch"
echo "========================================================="

if [ ! -f "$PATCH_FILE" ]; then
    echo "❌ Error: Patch file $PATCH_FILE not found."
    exit 1
fi

# Locate SGLang source tree
SGLANG_SRC=""
if [ -d "/sgl-workspace/sglang" ]; then
    SGLANG_SRC="/sgl-workspace/sglang"
elif [ -d "$HOME/sglang" ]; then
    SGLANG_SRC="$HOME/sglang"
else
    SITE_PKG=$(python3 -c "import sglang, os; print(os.path.dirname(os.path.dirname(sglang.__file__)))")
    SGLANG_SRC="$SITE_PKG"
fi

echo "📂 SGLang source location: $SGLANG_SRC"

cd "$SGLANG_SRC"
if git apply --check "$PATCH_FILE" 2>/dev/null; then
    echo "✅ Patch dry-run passed with git apply!"
    git apply "$PATCH_FILE"
    echo "🎉 Successfully applied sglang_qwen38_working.patch!"
elif patch -p1 --dry-run < "$PATCH_FILE" 2>/dev/null; then
    echo "✅ Patch dry-run passed with patch -p1!"
    patch -p1 < "$PATCH_FILE"
    echo "🎉 Successfully applied sglang_qwen38_working.patch!"
elif patch -p4 --dry-run < "$PATCH_FILE" 2>/dev/null; then
    echo "✅ Patch dry-run passed with patch -p4!"
    patch -p4 < "$PATCH_FILE"
    echo "🎉 Successfully applied sglang_qwen38_working.patch!"
else
    echo "ℹ️ Patch might already be applied or files differ. Checking critical file..."
    if grep -q "unpack_from_int32" "$SGLANG_SRC/python/sglang/srt/models/qwen3_5.py" 2>/dev/null || grep -q "unpack_from_int32" "$SGLANG_SRC/sglang/srt/models/qwen3_5.py" 2>/dev/null; then
        echo "✅ Verified: unpack_from_int32 is already present in qwen3_5.py."
    else
        echo "❌ Error: Patch could not be applied automatically. Please check version compatibility."
        exit 1
    fi
fi

echo "========================================================="
echo "⚙️ 3. Deploying Configuration Profiles & Helper Scripts"
echo "========================================================="

mkdir -p /etc/sglang/configs
cp -r "$REPO_DIR/configs/"* /etc/sglang/configs/
cp "$REPO_DIR/configs/sglang_dflash2_fast.conf" /etc/sglang-args.conf

# Rebuild / verify SGLang editable install if git workspace
if [ -f "$SGLANG_SRC/pyproject.toml" ]; then
    echo "🔄 Reinstalling editable SGLang package..."
    pip install -e "$SGLANG_SRC/python" --no-deps || true
fi

echo "========================================================="
echo "✅ Bootstrap Complete! Ready to launch."
echo "👉 Start Fast Speculative (91.5 tok/s): bash $SCRIPT_DIR/start_dflash2.sh"
echo "👉 Start Max Context (262K):            bash $SCRIPT_DIR/start_262k.sh"
echo "👉 Verify Server:                       bash $SCRIPT_DIR/verify.sh"
echo "========================================================="
