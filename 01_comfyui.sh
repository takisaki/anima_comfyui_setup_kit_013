#!/usr/bin/env bash
# 步骤 1：系统依赖 + CUDA PyTorch + ComfyUI 本体
# 所有网络操作都通过 lib.sh：源不可用会自动换，不需要手动干预
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

has_nvidia_smi || c_warn "没有 nvidia-smi：依赖仍会装好，但无法用 GPU（先跑 setup_all.sh 它会处理驱动）"

c_log "1/5 系统依赖"
apt_install ca-certificates curl wget unzip tar aria2 rsync git \
  python3.10-venv python3-dev python3-pip \
  libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 ffmpeg build-essential pkg-config \
  || c_warn "部分系统包失败，继续（多为非必需）"

c_log "2/5 ComfyUI 本体"
fetch_comfyui() {
  local u
  for u in \
    "https://codeload.github.com/comfyanonymous/ComfyUI/zip/refs/heads/master" \
    "https://ghfast.top/https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/master.zip" \
    "https://gh-proxy.com/https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/master.zip" \
    "https://mirror.ghproxy.com/https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/master.zip"
  do
    rm -f /root/comfy.zip
    if dl /root/comfy.zip 0 "$u"; then
      rm -rf /root/ComfyUI-master
      if unzip -q -o /root/comfy.zip -d /root && [ -d /root/ComfyUI-master ]; then
        rm -rf "$COMFY"; mv /root/ComfyUI-master "$COMFY"; rm -f /root/comfy.zip
        return 0
      fi
    fi
  done
  return 1
}
# 判断已解压的 ComfyUI 是否完整（缺 comfy/ldm/models 就是残缺包）
comfy_ok() {
  [ -f "$COMFY/main.py" ] && [ -f "$COMFY/comfy/sd.py" ] && [ -d "$COMFY/comfy/ldm/models" ]
}

# 覆盖式解压：只补程序文件，已下载的 models/ 和 user/ 不会被删
extract_bundle() {
  [ -f "$KIT/comfyui.tar.gz" ] || return 1
  local tmp=/root/.comfy-src
  rm -rf "$tmp"; mkdir -p "$tmp"
  tar -xzf "$KIT/comfyui.tar.gz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
  [ -d "$tmp/ComfyUI" ] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$COMFY"
  cp -a "$tmp/ComfyUI/." "$COMFY/" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  return 0
}

if comfy_ok; then
  c_ok "ComfyUI 已就绪: $COMFY"
elif extract_bundle && comfy_ok; then
  c_ok "已用随包源码覆盖到 $COMFY（不依赖 GitHub；models/ 与 user/ 保留）"
elif fetch_comfyui && comfy_ok; then
  c_ok "ComfyUI 已解压到 $COMFY"
else
  c_err "ComfyUI 源码不可用：随包源码缺失且所有 GitHub 通道不通"
  echo "   解决：重新下载最新 cloud-kit.zip（内含完整源码）后重跑"
  exit 1
fi

c_log "3/5 Python venv"
[ -x "$COMFY/venv/bin/python" ] || python3 -m venv "$COMFY/venv"
# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export PIP_NO_CACHE_DIR=1
pip_selftest || exit 1
pip_run -q -U pip wheel setuptools || c_warn "pip 升级失败（不影响后续）"

c_log "4/5 PyTorch"
if cuda_smoke_test; then
  c_ok "已有可用 CUDA torch: $(python -c 'import torch;print(torch.__version__)')"
elif bash "$KIT/install_torch.sh"; then
  c_ok "torch 安装完成"
else
  c_warn "镜像 wheel 全失败，改从 PyPI 装（CUDA 版本由 PyPI 提供）"
  pip_run "torch==2.5.1" "torchvision==0.20.1" "torchaudio==2.5.1" || exit 1
fi

c_log "5/5 ComfyUI requirements"
cd "$COMFY" || exit 1
# 元包只有 11 KB，镜像常滞后一天；先单独装掉，避免拖累整批依赖
PIN="$(grep -oP 'comfyui-workflow-templates==\K[0-9.]+' requirements.txt 2>/dev/null | head -1)"
if [ -n "$PIN" ] && ! python -c "import comfyui_workflow_templates" 2>/dev/null; then
  if ! python -m pip install $PIP_FLAGS --no-deps --index-url "https://pypi.org/simple" \
        "comfyui-workflow-templates==$PIN" 2>/dev/null; then
    c_warn "拿不到 workflow-templates $PIN，从 requirements 移除（只影响内置模板库缩略图）"
    cp -n requirements.txt requirements.txt.bak 2>/dev/null || true
    sed -i '/^comfyui-workflow-templates/d' requirements.txt
  fi
fi
pip_run -r requirements.txt || exit 1

echo
python - <<'PY'
import torch, sys
print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
else:
    sys.exit("CUDA 不可用：检查 nvidia-smi")
PY
c_ok "步骤 1 完成"
