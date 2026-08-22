#!/bin/bash
set -e

CONFIG_FILE="/etc/sglang/configs/sglang_dflash2_fast.conf"

while [[ $# -gt 0 ]]; do
  case $1 in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [ -f "$CONFIG_FILE" ]; then
    echo "========================================================="
    echo "🚀 Starting SGLang with profile: $CONFIG_FILE"
    echo "========================================================="
    ARGS=$(grep -v '^#' "$CONFIG_FILE" | tr '\n' ' ')
    exec sglang serve $ARGS "$@"
else
    echo "⚠️ Warning: Config file $CONFIG_FILE not found, starting with passed arguments: $@"
    exec sglang serve "$@"
fi
