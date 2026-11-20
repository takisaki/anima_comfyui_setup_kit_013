#!/usr/bin/env bash
# 环境急救：apt 换源 / 装显卡驱动 / 网络测速
# 用法:
#   bash fix_env.sh doctor   # 打印全部诊断信息（先跑这个）
#   bash fix_env.sh apt      # 换成阿里云源并 apt update
#   bash fix_env.sh gpu      # 安装 NVIDIA 驱动（装完必须 reboot）
#   bash fix_env.sh net      # 实测各站点下载速度
set -uo pipefail

MIRROR="${MIRROR:-https://mirrors.aliyun.com/ubuntu}"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")"
APT_OPTS="-o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=2"

mbps() { awk -v b="$1" 'BEGIN{printf "%.2f MB/s", b/1000000}'; }

doctor() {
  echo "===== 发行版 ====="; . /etc/os-release && echo "$PRETTY_NAME"
  echo; echo "===== PCI 设备（找 NVIDIA）====="
  (lspci 2>/dev/null || echo "没有 lspci") | grep -Ei 'nvidia|vga|3d|display' || echo "!! 没看到任何显示设备"
  echo; echo "===== nvidia-smi ====="
  nvidia-smi 2>&1 | head -12 || true
  echo; echo "===== 内核 / 头文件 ====="
  uname -r; ls -d /usr/src/linux-headers-"$(uname -r)" 2>/dev/null || echo "!! 没装本内核的头文件"
  echo; echo "===== apt 源 ====="
  grep -hv '^#' /etc/apt/sources.list 2>/dev/null | grep -v '^$' | head -8
  ls /etc/apt/sources.list.d/ 2>/dev/null
  echo; echo "===== DNS ====="
  cat /etc/resolv.conf 2>/dev/null | grep -v '^#'
  echo; echo "===== 连通性 ====="
  for u in https://hf-mirror.com https://mirrors.aliyun.com/ubuntu/dists/$CODENAME/Release https://download.pytorch.org/whl/cu121/torch/; do
    printf '%-62s %s\n' "$u" "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{time_total}s' "$u" 2>/dev/null)"
  done
  echo; echo "===== 下载实测（每项 8 秒）====="
  probe "hf-mirror.com   (Anima VAE)" "https://hf-mirror.com/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors"
  probe "aliyun apt     " "https://mirrors.aliyun.com/ubuntu/dists/$CODENAME/main/binary-amd64/Packages.gz"
  probe "pytorch cu121  " "https://download.pytorch.org/whl/cu121/torch-2.5.1%2Bcu121-cp310-cp310-linux_x86_64.whl"
}

probe() {
  local name="$1" url="$2"
  local got
  got=$(curl -s -o /dev/null -m 8 -r 0-40000000 -w '%{speed_download}' "$url" 2>/dev/null || echo 0)
  printf '%s  %s\n' "$name" "$(mbps "${got:-0}")"
}

do_apt() {
  # 统一走 lib.sh 的探测逻辑，不再写死镜像地址
  local d; d="$(cd "$(dirname "$0")" && pwd)"
  # shellcheck disable=SC1091
  source "$d/lib.sh"
  apt_prepare
}

do_gpu() {
  if ! lspci 2>/dev/null | grep -qiE 'nvidia|3d controller'; then
    echo "!! lspci 中没有 NVIDIA 设备。这台机器可能根本没挂显卡，"
    echo "   或者需要先在云平台控制台重新创建为 GPU 实例。"
    lspci 2>/dev/null | grep -Ei 'vga|3d|display' || echo "   (连显示设备都没有)"
    exit 1
  fi
  echo "==> 检测到 GPU:"
  lspci | grep -i nvidia

  export DEBIAN_FRONTEND=noninteractive
  echo "==> 安装 dkms + 本内核头文件（不装编译不过）"
  apt-get $APT_OPTS install -y --no-install-recommends dkms "linux-headers-$(uname -r)" || {
    echo "!! 头文件装失败。先跑: bash fix_env.sh apt"; exit 1; }

  for v in 535 550 570; do
    echo "==> 尝试 nvidia-driver-$v"
    if apt-get $APT_OPTS install -y --no-install-recommends "nvidia-driver-$v" "nvidia-utils-$v"; then
      echo "==> 驱动 $v 安装完成"
      DKMS_STATUS=1
      break
    fi
  done
  [ "${DKMS_STATUS:-0}" = "1" ] || { echo "!! 驱动安装失败"; exit 1; }

  echo
  echo "==> 检查内核模块"
  modinfo nvidia >/dev/null 2>&1 && echo "   modinfo nvidia OK" || echo "   !! modprobe 信息缺失"
  echo
  echo "=============================================="
  echo " 现在必须重启：  reboot"
  echo " 重启后重新 ssh 登录，运行:  nvidia-smi"
  echo "=============================================="
}

do_net() {
  probe "hf-mirror  " "https://hf-mirror.com/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors"
  probe "aliyun apt " "https://mirrors.aliyun.com/ubuntu/dists/$CODENAME/main/binary-amd64/Packages.gz"
  probe "pytorch    " "https://download.pytorch.org/whl/cu121/torch-2.5.1%2Bcu121-cp310-cp310-linux_x86_64.whl"
  echo "（<0.3 MB/s 就别下模型了，先解决带宽）"
}

case "${1:-doctor}" in
  doctor) doctor ;;
  apt) do_apt ;;
  gpu) do_gpu ;;
  net) do_net ;;
  *) echo "用法: bash fix_env.sh [doctor|apt|gpu|net]"; exit 1 ;;
esac
