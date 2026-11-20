#!/usr/bin/env bash
# 安装 CUDA 版 PyTorch（PyPI 的 linux wheel 自带 CUDA 12.8）
# ComfyUI 本版要求 torch >= 2.7（comfy_kitchen 用了新版 infer_schema 语法）
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

[ -x "$COMFY/venv/bin/python" ] || { c_err "先建 venv"; exit 1; }
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export PIP_NO_CACHE_DIR=1

# 只固定 torch 大版本；torchvision/torchaudio 交给 pip 选匹配版本，
# 否则镜像站少一个补丁版就会触发漫长的版本回溯（表现为“卡住”）
TORCH_VERS=("2.9.1" "2.8.0" "2.7.1")

for T in "${TORCH_VERS[@]}"; do
  c_log "安装 torch $T（约 900 MB，之后还有约 3.5 GB 依赖，进度条会动）"
  if ! pip_run --progress-bar on --timeout 30 --retries 2 "torch==$T"; then
    c_warn "torch $T 装不上，换下一个版本"
    continue
  fi
  c_log "补 torchvision / torchaudio（让 pip 自己匹配版本）"
  pip_run --progress-bar on --timeout 30 --retries 2 torchvision torchaudio \
    || c_warn "torchvision/torchaudio 失败，不影响出图"

  if python -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    c_ok "torch $(python -c 'import torch;print(torch.__version__)')，CUDA 可用"
    python -c "import torch;print('driver ok, device:', torch.cuda.get_device_name(0))"
    exit 0
  fi
  c_err "torch $T 装上了但 CUDA 不可用（当前驱动 $(gpu_driver_major)，需要 >= 560）"
  exit 1
done

c_err "所有 torch 版本都装不上"
exit 1
