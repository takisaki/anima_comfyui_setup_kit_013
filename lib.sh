#!/usr/bin/env bash
# lib.sh — 公共库
# 原则：脚本里不写死任何镜像地址。每次运行时就地探测，失败自动换下一个源，
#       结果缓存到 .state.env，下次重跑直接用（也会重新验证）。
#
# 用法: source "$(dirname "$0")/lib.sh"

set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
STATE="${STATE:-$KIT_DIR/.state.env}"
COMFY="${COMFY:-/root/ComfyUI}"
CODENAME="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"
[ -z "$CODENAME" ] && CODENAME="jammy"

c_log()  { printf '\033[36m==> %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m  OK   %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m  !!   %s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m  !!   %s\033[0m\n' "$*"; }

curl_code()  { curl -s -o /dev/null -L -m "${2:-8}" -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
curl_speed() {
  local s
  s="$(curl -s -o /dev/null -L -m "${2:-8}" -r 0-4000000 -w '%{speed_download}' "$1" 2>/dev/null || echo 0)"
  echo "${s%%.*}" | grep -E '^[0-9]+$' || echo 0
}

# ---------- 候选源 ----------
APT_CANDS=(
  "http://mirrors.aliyun.com/ubuntu"
  "https://mirrors.aliyun.com/ubuntu"
  "https://repo.huaweicloud.com/ubuntu"
  "https://mirrors.cloud.tencent.com/ubuntu"
  "https://mirrors.ustc.edu.cn/ubuntu"
  "http://archive.ubuntu.com/ubuntu"
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
)
PIP_CANDS=(
  "https://repo.huaweicloud.com/repository/pypi/simple"
  "http://mirrors.aliyun.com/pypi/simple"
  "https://mirrors.cloud.tencent.com/pypi/simple"
  "https://mirrors.ustc.edu.cn/pypi/simple"
  "https://pypi.tuna.tsinghua.edu.cn/simple"
  "https://pypi.org/simple"
)
TORCH_CANDS=(
  "http://mirrors.aliyun.com/pytorch-wheels/cu121"
  "https://mirrors.aliyun.com/pytorch-wheels/cu121"
  "https://mirror.sjtu.edu.cn/pytorch-wheels/cu121"
  "https://download.pytorch.org/whl/cu121"
)

# ---------- 状态缓存 ----------
save_state() {
  local k="$1" v="$2"
  touch "$STATE"
  sed -i "/^$k=/d" "$STATE" 2>/dev/null || true
  printf "%s='%s'\n" "$k" "$v" >> "$STATE"
}
load_state() { [ -f "$STATE" ] && . "$STATE" 2>/dev/null; return 0; }

# ---------- apt ----------
write_sources() {
  local m="$1"
  cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%s)" 2>/dev/null || true
  cat > /etc/apt/sources.list <<EOF
deb $m/ $CODENAME main restricted universe multiverse
deb $m/ $CODENAME-updates main restricted universe multiverse
deb $m/ $CODENAME-backports main restricted universe multiverse
deb $m/ $CODENAME-security main restricted universe multiverse
EOF
  chmod 644 /etc/apt/sources.list
}

APT_OPTS="-o Acquire::http::Timeout=25 -o Acquire::https::Timeout=25 -o Acquire::Retries=2"

apt_prepare() {
  load_state
  if [ -n "${APT_MIRROR:-}" ]; then
    write_sources "$APT_MIRROR"
    apt-get $APT_OPTS update && { c_ok "apt 源: $APT_MIRROR (缓存)"; return 0; }
    c_warn "$APT_MIRROR 失效，重新探测"
  fi
  # 把可能冲突的第三方源挪走（只做一次）
  if ls /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
    mkdir -p /root/apt-list-d-backup
    mv /etc/apt/sources.list.d/*.list /root/apt-list-d-backup/ 2>/dev/null || true
  fi
  local m best="" bests=0 spd
  c_log "探测 apt 源"
  for m in "${APT_CANDS[@]}"; do
    code="$(curl_code "$m/dists/$CODENAME/InRelease" 6)"
    [ "$code" = "200" ] || { printf '  %-50s HTTP %s\n' "$m" "$code"; continue; }
    spd="$(curl_speed "$m/dists/$CODENAME/main/binary-amd64/Packages.gz" 6)"
    printf '  %-50s HTTP 200  %5.2f MB/s\n' "$m" "$(awk -v s="$spd" 'BEGIN{print s/1000000}')"
    [ "$spd" -gt "$bests" ] && { best="$m"; bests="$spd"; }
  done
  [ -n "$best" ] || { c_err "所有 apt 源都不可用"; return 1; }

  # 依次试（先最快的），失败就换下一个
  for m in "$best" "${APT_CANDS[@]}"; do
    write_sources "$m"
    if apt-get $APT_OPTS update; then
      save_state APT_MIRROR "$m"
      c_ok "apt 源: $m"
      return 0
    fi
    c_warn "$m 更新失败，换下一个"
  done
  c_err "apt 源全部失败"
  return 1
}

apt_install() {
  apt_prepare || return 1
  dpkg_wait
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get $APT_OPTS \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    install -y --no-install-recommends "$@"
}

# ---------- pip ----------
PIP_FLAGS="--timeout 60 --retries 3 --disable-pip-version-check --no-cache-dir"

pip_indexes() {
  load_state
  local out=()
  [ -n "${PIP_INDEX:-}" ] && out+=("$PIP_INDEX")
  out+=("${PIP_CANDS[@]}")
  printf '%s\n' "${out[@]}" | awk '!seen[$0]++'
}

# 把选中的源写进 /etc/pip.conf：之后任何 pip 调用（包括节点自己调 pip）都继承
write_pip_conf() {
  local idx="$1" host
  [ -n "$idx" ] || return 0
  host="$(echo "$idx" | sed -E 's#^https?://([^/]+)/.*#\1#')"
  cat > /etc/pip.conf <<EOF
[global]
index-url = $idx
trusted-host = $host
timeout = 60
retries = 3
EOF
}

# pip_run <pip 参数...>：按候选顺序尝试，第一个成功的记住
pip_run() {
  local idx
  while read -r idx; do
    [ -n "$idx" ] || continue
    if python -m pip install $PIP_FLAGS --index-url "$idx" "$@"; then
      save_state PIP_INDEX "$idx"
      write_pip_conf "$idx"
      return 0
    fi
    c_warn "源 $idx 失败，换下一个"
  done < <(pip_indexes)
  return 1
}

pip_selftest() {
  local idx
  while read -r idx; do
    [ -n "$idx" ] || continue
    if python -m pip download $PIP_FLAGS --no-deps -q -d /tmp/.pipt "$idx" 2>/dev/null; then :; fi
    if python -m pip download $PIP_FLAGS --no-deps -q -d /tmp/.pipt --index-url "$idx" six >/dev/null 2>&1; then
      rm -rf /tmp/.pipt
      save_state PIP_INDEX "$idx"
      write_pip_conf "$idx"
      c_ok "pip 源: $idx"
      return 0
    fi
  done < <(pip_indexes)
  rm -rf /tmp/.pipt
  c_err "pip 源全部不可用"
  return 1
}

# ---------- 文件下载 ----------
# dl <输出路径> <期望字节数|0=不校验> <url...>
dl() {
  local out="$1" want="$2"; shift 2
  local url dir name have
  dir="$(dirname "$out")"; name="$(basename "$out")"
  mkdir -p "$dir"
  if [ -f "$out" ] && [ "$want" != "0" ]; then
    have="$(stat -c %s "$out" 2>/dev/null || echo 0)"
    [ "$have" -ge $((want - 2000)) ] && { c_ok "$name 已完整"; return 0; }
  fi
  # 只有大文件（>=100MB，即模型）才用 aria2 多线程；
  # 小文件走 curl 单连接 —— GitHub/codeload 不支持 Range，多线程会被拒
  local mode="curl"
  [ "${want:-0}" -ge 100000000 ] 2>/dev/null && mode="aria2"
  for url in "$@"; do
    [ -n "$url" ] || continue
    printf '    %s\n' "$(echo "$url" | cut -c1-118)"
    if [ "$mode" = "aria2" ] && command -v aria2c >/dev/null 2>&1; then
      aria2c -x 4 -s 4 -k 1M -c --auto-file-renaming=false --allow-overwrite=true \
        --console-log-level=warn --summary-interval=5 --show-console-readout=true \
        --lowest-speed-limit=10K --max-tries=3 \
        -d "$dir" -o "$name" "$url" && \
      { [ "$want" = "0" ] || [ "$(stat -c %s "$out" 2>/dev/null || echo 0)" -ge $((want - 2000)) ]; } && return 0
    else
      curl -fL -C - --retry 3 --retry-delay 5 --connect-timeout 25 \
        --speed-limit 1024 --speed-time 45 -o "$out" "$url" && \
      { [ "$want" = "0" ] || [ "$(stat -c %s "$out" 2>/dev/null || echo 0)" -ge $((want - 2000)) ]; } && return 0
    fi
    [ -f "$out" ] && [ "$(stat -c %s "$out" 2>/dev/null || echo 0)" -gt 100000 ] || rm -f "$out"
  done
  return 1
}

human() { awk -v b="${1:-0}" 'BEGIN{ if (b>=1000000000) printf "%.2f GB", b/1e9; else if (b>0) printf "%.0f MB", b/1e6; else printf "-"; }';
}

# ---------- 系统状态 ----------
dpkg_wait() {
  local i=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
        /var/cache/apt/archives/lock >/dev/null 2>&1; do
    i=$((i+1)); [ "$i" -gt 60 ] && { c_warn "dpkg 锁等待超时"; break; }
    sleep 2
  done
}

gpu_present()     { lspci 2>/dev/null | grep -qiE 'nvidia|3d controller'; }
has_nvidia_smi()  { command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; }
disk_free_gb()    { df -Pk "${1:-/}" | awk 'NR==2{printf "%d", $4/1048576}'; }

# 驱动主版本号（取不到返回 0）
gpu_driver_major() {
  local v
  v="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)"
  echo "${v:-0}"
}

# 返回 0=已就绪 3=刚装完需重启 1=失败
# 要求 >= 560：PyTorch 2.7+ 的 CUDA 12.6/12.8 wheel 需要新驱动
ensure_gpu_driver() {
  local need=560 major
  if has_nvidia_smi; then
    major="$(gpu_driver_major)"
    if [ "${major:-0}" -ge "$need" ]; then
      c_ok "驱动就绪: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1) / driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
      return 0
    fi
    c_warn "驱动 $major 太旧（PyTorch cu128 需要 >= $need），先升级"
  fi
  gpu_present || { c_err "lspci 里没有 NVIDIA 设备，这台机器不是 GPU 实例"; return 1; }

  c_log "安装 NVIDIA 驱动（约 2-5 分钟）"
  dpkg_wait
  apt_install dkms build-essential "linux-headers-$(uname -r)" || c_warn "部分构建依赖失败，继续尝试"

  local v
  for v in 580 570 590; do
    dpkg_wait
    c_log "尝试 nvidia-driver-$v"
    if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
       apt-get $APT_OPTS -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
       install -y --no-install-recommends "nvidia-driver-$v" "nvidia-utils-$v"; then
      c_ok "已安装 nvidia-driver-$v，需要重启加载内核模块"
      return 3
    fi
    c_warn "nvidia-driver-$v 不可用，换下一个版本"
  done
  c_err "驱动安装失败"
  return 1
}

# ---------- 重启后自动续跑 ----------
RESUME_UNIT="/etc/systemd/system/comfy-kit-resume.service"

install_resume_unit() {
  local self="$KIT_DIR/setup_all.sh"
  cat > "$RESUME_UNIT" <<EOF
[Unit]
Description=ComfyUI kit: resume setup after reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
TimeoutStartSec=0
ExecStart=/bin/bash $self --yes --resumed
StandardOutput=append:/root/kit/setup.log
StandardError=append:/root/kit/setup.log

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable comfy-kit-resume.service 2>/dev/null && c_ok "已注册开机续跑服务"
}

remove_resume_unit() {
  systemctl disable comfy-kit-resume.service 2>/dev/null || true
  rm -f "$RESUME_UNIT"
  systemctl daemon-reload 2>/dev/null || true
}
