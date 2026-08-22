#!/bin/bash
# 📚 1-Click Launch: Max Context >262K Baseline Profile (~52.6 tok/s)
set -e

CONFIG="/etc/sglang/configs/sglang_262k_max_context.conf"
if [ ! -f "$CONFIG" ]; then
    CONFIG="$(dirname "${BASH_SOURCE[0]}")/../configs/sglang_262k_max_context.conf"
fi

echo "📚 Launching SGLang with Max Context 262K Baseline Profile..."
ARGS=$(grep -v '^#' "$CONFIG" | tr '\n' ' ')
exec sglang serve $ARGS "$@"
