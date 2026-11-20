#!/usr/bin/env bash
# 步骤 2：节点 + 依赖 + 工作流
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

[ -f "$KIT/nodes.tar.gz" ] || { c_err "缺少 nodes.tar.gz"; exit 1; }

c_log "解压节点"
mkdir -p "$COMFY/custom_nodes"
tar -xzf "$KIT/nodes.tar.gz" -C "$COMFY"
c_ok "节点数: $(ls -1d "$COMFY"/custom_nodes/*/ 2>/dev/null | wc -l)"

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
