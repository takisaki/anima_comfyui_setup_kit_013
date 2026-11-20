#!/usr/bin/env bash
# 安装 CUDA 版 PyTorch，直到"能真正跑 CUDA 算子"为止
# 依次尝试多个版本，任何一个失败（装不上 / CUDA 不可用 / sm 不支持）就换下一个
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

[ -x "$COMFY/venv/bin/python" ] || { c_err "先建 venv"; exit 1; }
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export PIP_NO_CACHE_DIR=1

# PyPI 的 linux wheel 自带 CUDA：2.9=cu128，2.7=cu126；驱动 580 两者都支持
TORCH_VERS=("${TORCH_VERS:-2.9.1 2.8.0 2.7.1}")

pip_install_torch() {
  local ver="$1"
  pip_run --progress-bar on --timeout 30 --retries 2 "torch==$ver"
}

for T in ${TORCH_VERS[@]}; do
  c_log "尝试 torch $T（wheel 约 900 MB，依赖约 3.5 GB，有进度条）"
  if ! pip_install_torch "$T"; then
    c_warn "torch $T 下载/安装失败，换下一个版本"
    continue
  fi

  if ! cuda_smoke_test; then
    c_warn "torch $T 装上但跑不了 CUDA（可能是 sm_75 内核缺失或驱动不匹配）"
    python -m pip uninstall -y -q torch torchvision torchaudio >/dev/null 2>&1 || true
    continue
  fi

  c_log "补 torchvision / torchaudio（由 pip 匹配版本）"
  pip_run --progress-bar on --timeout 30 --retries 2 torchvision torchaudio \
    || c_warn "torchvision/torchaudio 失败，出图不受影响"

  c_ok "torch $(python -c 'import torch;print(torch.__version__)')"
  python -c "import torch;print('device:', torch.cuda.get_device_name(0), '| capability:', torch.cuda.get_device_capability(0))"
  exit 0
done

c_err "所有候选 torch 版本都不可用：${TORCH_VERS[*]}"
echo "   当前驱动版本: $(gpu_driver_major)（需要 >= 560）"
exit 1
