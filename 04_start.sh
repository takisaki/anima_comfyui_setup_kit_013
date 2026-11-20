#!/usr/bin/env bash
# 步骤 4：启动 ComfyUI
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
COMFY="${COMFY:-/root/ComfyUI}"
PORT="${PORT:-8188}"
LISTEN="${LISTEN:-127.0.0.1}"   # 想直接公网访问改成 0.0.0.0（务必配安全组/防火墙）
EXTRA="${EXTRA:-}"             # 例如 EXTRA="--medvram" 或 EXTRA="--force-fp16"

# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_HUB_DISABLE_TELEMETRY=1
cd "$COMFY"

cat <<EOF
============================================================
 ComfyUI  http://$LISTEN:$PORT
 本机浏览器访问：先在你自己的电脑上开一条隧道
   ssh -N -L $PORT:127.0.0.1:$PORT root@<服务器IP>
 然后打开 http://127.0.0.1:$PORT
 停止：Ctrl+C
============================================================
EOF

exec python main.py --listen "$LISTEN" --port "$PORT" --preview-method auto $EXTRA
