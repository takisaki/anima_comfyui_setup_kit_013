#!/usr/bin/env bash
# 步骤 5：自检（加载全部节点但不启动服务）
set -uo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
COMFY="${COMFY:-/root/ComfyUI}"
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
cd "$COMFY"

echo "===== 1. 模型清单 ====="
python "$KIT/check_models.py"

echo
echo "===== 2. 节点导入自检（有报错就是某个节点坏了）====="
timeout 300 python main.py --quick-test-for-ci 2>&1 | tail -n 40
echo "退出码: ${PIPESTATUS[0]}"

echo
echo "===== 3. 磁盘 ====="
df -h /root | tail -1
du -sh "$COMFY/models" 2>/dev/null
