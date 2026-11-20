#!/usr/bin/env bash
# 步骤 0：环境自检（只读，不改任何东西）
set -uo pipefail

echo "===== 系统 ====="
. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"
uname -r
echo "CPU 核数: $(nproc)"
echo "内存: $(free -h | awk '/Mem:/{print $2}')"

echo
echo "===== 显卡 ====="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
  echo "!! 没有 nvidia-smi：可能没装驱动，或不是 GPU 机型"
fi

echo
echo "===== 磁盘 ====="
df -h / /root 2>/dev/null | awk 'NR==1 || /\/root|\/$/'
FREE=$(df -Pk /root | awk 'NR==2{print $4}')
echo "根分区可用: $((FREE/1024/1024)) GB"
if [ "$FREE" -lt 25000000 ]; then
  echo "!! 可用空间 < 24 GB，模型可能装不下"
fi

echo
echo "===== Python ====="
python3 -V 2>/dev/null || echo "!! 没有 python3（Ubuntu 22.04 应自带 3.10）"

echo
echo "===== 网络（各站点 10 秒测速）====="
for u in https://hf-mirror.com https://huggingface.co https://download.pytorch.org https://mirrors.aliyun.com https://codeload.github.com; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null)
  printf '%-32s %s\n' "$u" "${code:-超时}"
done

echo
echo "===== 实际下载速度（各 8 秒）====="
probe() {
  got=$(curl -s -o /dev/null -m 8 -r 0-40000000 -w '%{speed_download}' "$2" 2>/dev/null || echo 0)
  awk -v n="$1" -v b="${got:-0}" 'BEGIN{printf "%-14s %.2f MB/s\n", n, b/1000000}'
}
probe hf-mirror  https://hf-mirror.com/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors
probe aliyun-apt https://mirrors.aliyun.com/ubuntu/dists/jammy/main/binary-amd64/Packages.gz
echo "（>5 MB/s 说明入方向不限速；0.3-2.5 MB/s 是被带宽卡住；<0.1 MB/s 是网络有问题，跑 bash fix_env.sh doctor）"
