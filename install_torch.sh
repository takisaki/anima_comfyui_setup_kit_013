#!/usr/bin/env bash
# 安装 CUDA 版 PyTorch：直接走 PyPI 镜像（linux wheel 自带 CUDA 12.8）
# ComfyUI 本版要求 torch >= 2.7（comfy_kitchen 用了新版 infer_schema 语法）
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

[ -x "$COMFY/venv/bin/python" ] || { c_err "先建 venv"; exit 1; }
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export PIP_NO_CACHE_DIR=1

COMBOS=(
  "2.9.1 0.24.1 2.9.1"
  "2.8.0 0.23.0 2.8.0"
  "2.7.1 0.22.1 2.7.1"
)

for c in "${COMBOS[@]}"; do
  set -- $c
  T="$1"; TV="$2"; TA="$3"
  c_log "尝试 torch $T / torchvision $TV / torchaudio $TA"
  if pip_run -q "torch==$T" "torchvision==$TV" "torchaudio==$TA"; then
    if python -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
      c_ok "torch $(python -c 'import torch;print(torch.__version__)')，CUDA 可用"
      exit 0
    fi
    c_warn "torch $T 已装但 CUDA 不可用（驱动版本不够？当前 driver $(gpu_driver_major)）"
    exit 1
  fi
  c_warn "torch $T 装不上，换下一个版本组合"
done

c_err "所有 torch 版本都装不上"
exit 1
