#!/usr/bin/env bash
# 裸机一键部署：驱动 -> ComfyUI -> 节点 -> 模型
#   bash setup_all.sh            先体检再确认
#   bash setup_all.sh --yes      全自动（首次装驱动会自动重启并续跑）
#   bash setup_all.sh --yes --no-reboot   不自动重启，只提示
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$KIT"/*.sh 2>/dev/null || true
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"

YES=0; AUTO_REBOOT=1; RESUMED=0
for a in "$@"; do
  case "$a" in
    --yes|-y)   YES=1 ;;
    --no-reboot) AUTO_REBOOT=0 ;;
    --resumed)  RESUMED=1; YES=1 ;;
  esac
done
[ "$RESUMED" = "1" ] && AUTO_REBOOT=0

if [ "$RESUMED" = "0" ] && [ "$YES" = "0" ]; then
  bash "$KIT/00_preflight.sh" || true
  echo
  read -r -p "继续安装？[y/N] " ans
  case "$ans" in y|Y) ;; *) echo "已取消"; exit 0 ;; esac
fi

echo "==============================================="
echo " ComfyUI 云端部署   $(date '+%F %T')"
echo "==============================================="

# ---------- 阶段 0：显卡驱动 ----------
if ! has_nvidia_smi; then
  ensure_gpu_driver
  rc=$?
  if [ "$rc" = "3" ]; then
    if [ "$RESUMED" = "1" ]; then
      c_err "重启后 nvidia-smi 仍不可用，驱动没有生效"
      echo "   排查: dmesg | grep -i nvidia ；dkms status"
      exit 1
    fi
    install_resume_unit
    echo
    echo "==============================================="
    echo " 驱动已装好，必须重启才能加载内核模块"
    echo " 重启后会自动继续安装（已注册开机续跑服务）"
    echo " 日志: /root/kit/setup.log"
    echo "==============================================="
    if [ "$AUTO_REBOOT" = "1" ]; then
      echo " 15 秒后自动重启，Ctrl+C 可取消"
      sleep 15
      sync
      reboot
    else
      echo " 手动执行: reboot"
    fi
    exit 0
  elif [ "$rc" != "0" ]; then
    c_err "驱动安装失败，终止"
    exit 1
  fi
fi

# ---------- 阶段 1-3 ----------
run_step() {
  local s="$1" rc
  for attempt in 1 2; do
    c_log "运行 $s（第 $attempt 次）"
    bash "$KIT/$s"
    rc=$?
    [ "$rc" = "0" ] && return 0
    if [ "$rc" = "2" ]; then
      c_warn "$s 有子项失败（继续，稍后可重跑该步）"
      return 0
    fi
    c_warn "$s 失败（rc=$rc），清除源缓存重试"
    rm -f "$KIT/.state.env"
  done
  return 1
}

run_step 01_comfyui.sh || { c_err "步骤 1 失败"; exit 1; }
run_step 02_nodes.sh   || { c_err "步骤 2 失败"; exit 1; }
run_step 03_models.sh  || { c_err "步骤 3 失败"; exit 1; }

remove_resume_unit
echo
echo "==============================================="
c_ok "部署完成"
echo " 启动: bash $KIT/04_start.sh"
echo " 本机: ssh -N -L 8188:127.0.0.1:8188 root@<IP>"
echo "==============================================="
