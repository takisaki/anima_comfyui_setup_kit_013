#!/usr/bin/env bash
# 步骤 5：自检（不启动服务）
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
cd "$COMFY"

echo "===== 1. 显卡与 CUDA ====="
if has_nvidia_smi; then
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
else
  c_err "没有 nvidia-smi（驱动未就绪）"
fi
if cuda_smoke_test; then
  python -c "import torch;print('torch', torch.__version__, '| device', torch.cuda.get_device_name(0), '| capability', torch.cuda.get_device_capability(0))"
else
  c_err "CUDA 冒烟测试失败：torch 装上了但跑不了 GPU"
fi

echo
echo "===== 2. comfy_kitchen 导入 ====="
if python -c "import comfy_kitchen" 2>/dev/null; then c_ok "comfy_kitchen 可用"; else c_err "comfy_kitchen 导入失败（ComfyUI 会起不来）"; fi

echo
echo "===== 3. 模型清单 ====="
python "$KIT/check_models.py"

echo
echo "===== 4. 节点导入自检（有报错就是某个节点坏了）====="
timeout 300 python main.py --quick-test-for-ci 2>&1 | tail -n 40
echo "退出码: ${PIPESTATUS[0]}"

echo
echo "===== 5. 磁盘 ====="
df -h /root | tail -1
du -sh "$COMFY/models" 2>/dev/null
