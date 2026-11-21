#!/usr/bin/env bash
# 步骤 2：节点 + 依赖 + 工作流 + 节点补丁 + 预处理器权重
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"
HF_BASE="${HF_BASE:-https://hf-mirror.com}"

[ -f "$KIT/nodes.tar.gz" ] || { c_err "缺少 nodes.tar.gz"; exit 1; }

c_log "解压节点"
mkdir -p "$COMFY/custom_nodes"
tar -xzf "$KIT/nodes.tar.gz" -C "$COMFY"
c_ok "节点数: $(ls -1d "$COMFY"/custom_nodes/*/ 2>/dev/null | wc -l)"

PYBIN="python3"
[ -x "$COMFY/venv/bin/python" ] && PYBIN="$COMFY/venv/bin/python"
c_log "打补丁: Anima Ref Adapter（与 Anima LLLite 共存）"
if "$PYBIN" "$KIT/patches/apply_anima_ref_adapter_patch.py" "$COMFY"; then
  c_ok "补丁就绪"
else
  c_warn "补丁未应用：04 工作流同时用 LLLite + Ref Adapter 会报 KeyError: 'model_patch_data'"
fi

# DWPreprocessor（04 工作流）首次运行会自己下载权重；这里先下好，避免第一次出图卡住
aux_fetch() {
  local rel_dir="$1" name="$2" hf_path="$3" size="$4"
  local out="$COMFY/custom_nodes/comfyui_controlnet_aux/ckpts/$rel_dir/$name"
  if [ -f "$out" ] && [ "$(stat -c %s "$out" 2>/dev/null || echo 0)" -ge $((size - 2000)) ]; then
    c_ok "$name"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  c_log "下载 $name"
  if dl "$out" "$size" "$HF_BASE/$hf_path"; then
    c_ok "$name"
  else
    c_warn "$name 下载失败（首次跑 DWPreprocessor 时会自动重下）"
  fi
}
if [ -d "$COMFY/custom_nodes/comfyui_controlnet_aux" ]; then
  c_log "DWPose 预处理权重"
  aux_fetch "hr16/DWPose-TorchScript-BatchSize5" "dw-ll_ucoco_384_bs5.torchscript.pt" \
    "hr16/DWPose-TorchScript-BatchSize5/resolve/main/dw-ll_ucoco_384_bs5.torchscript.pt" 135059124
  aux_fetch "yzd-v/DWPose" "yolox_l.onnx" \
    "yzd-v/DWPose/resolve/main/yolox_l.onnx" 216746733
fi

c_log "安装工作流"
WF_DIR="$COMFY/user/default/workflows"
mkdir -p "$WF_DIR"
# 优先用 tar：tar 原样保存文件名字节，不受 unzip 的 locale 影响（中文名不会乱码）
if [ -f "$KIT/workflows.tar.gz" ]; then
  rm -f "$WF_DIR"/*.json 2>/dev/null || true
  tar -xzf "$KIT/workflows.tar.gz" -C "$WF_DIR"
elif [ -d "$KIT/workflows" ]; then
  cp -f "$KIT"/workflows/*.json "$WF_DIR/" 2>/dev/null || true
fi
c_ok "工作流: $(ls -1 "$WF_DIR"/*.json 2>/dev/null | wc -l) 个"

# shellcheck disable=SC1091
source "$COMFY/venv/bin/activate"
export PIP_NO_CACHE_DIR=1
pip_selftest || exit 1

FAILED=""
for d in "$COMFY"/custom_nodes/*/; do
  [ -f "$d/requirements.txt" ] || continue
  name=$(basename "$d")
  c_log "pip: $name"
  if pip_run -r "$d/requirements.txt"; then
    c_ok "$name"
  else
    c_warn "$name 依赖装不上"
    FAILED="$FAILED $name"
  fi
done

echo
if [ -n "$FAILED" ]; then
  c_warn "以下节点依赖未装全:$FAILED"
  echo "   逐个重试: cd $COMFY && source venv/bin/activate && pip install -r custom_nodes/<名字>/requirements.txt"
  exit 2
fi
c_ok "步骤 2 完成"
