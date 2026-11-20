#!/usr/bin/env bash
# 从本地 ComfyUI 生成可上传的发布包（Linux/macOS/WSL/Git Bash）
#   ./scripts/build_pack.sh /path/to/ComfyUI [输出目录]
set -euo pipefail
COMFY="${1:?用法: build_pack.sh <ComfyUI 路径> [输出目录]}"
OUT="${2:-dist}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$HERE/scripts/build_pack.py" --comfy "$COMFY" --out "$OUT"
