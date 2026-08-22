#!/bin/bash
# 🚀 1-Click Launch: DFLASH2 Speculative Mode (~91.5 tok/s)
set -e

CONFIG="/etc/sglang/configs/sglang_dflash2_fast.conf"
if [ ! -f "$CONFIG" ]; then
    CONFIG="$(dirname "${BASH_SOURCE[0]}")/../configs/sglang_dflash2_fast.conf"
fi

echo "🏎️ Launching SGLang with DFLASH2 Fast Speculative Profile..."
ARGS=$(grep -v '^#' "$CONFIG" | tr '\n' ' ')
exec sglang serve $ARGS "$@"
