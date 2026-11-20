#!/usr/bin/env bash
# 在服务器上下载部署包：GitHub 直连失败就自动换国内加速镜像
#   bash get_kit.sh            下载到 /root/cloud-kit.zip
#   DEST=/tmp/k.zip bash get_kit.sh
set -uo pipefail

REPO="takisaki/anima_comfyui_setup_kit_013"
DEST="${DEST:-/root/cloud-kit.zip}"
TAG="${TAG:-latest}"
URL="https://github.com/$REPO/releases/$TAG/download/cloud-kit.zip"
PROXIES=("" "https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/" "https://mirror.ghproxy.com/")

MIN_BYTES=60000000

echo "目标: $DEST"
for p in "${PROXIES[@]}"; do
  echo "==> ${p:-GitHub 直连}"
  rm -f "$DEST.part"
  if curl -fL -C - --connect-timeout 20 --speed-limit 1024 --speed-time 40 \
       --retry 2 -o "$DEST.part" "$p$URL"; then
    sz=$(stat -c %s "$DEST.part" 2>/dev/null || echo 0)
    if [ "$sz" -ge "$MIN_BYTES" ]; then
      mv "$DEST.part" "$DEST"
      awk -v b="$sz" 'BEGIN{printf "OK  %.1f MB  -> %s\n", b/1e6, ENVIRON["DEST"]}'
      echo
      echo "下一步:"
      echo "  rm -rf /root/kit"
      echo "  unzip -q $DEST -d /root/kit"
      echo "  cd /root/kit && bash setup_all.sh --yes"
      exit 0
    fi
    echo "    文件太小 ($sz 字节)，可能是错误页面，换下一个源"
  fi
done

echo
echo "所有源都失败了。在本机下载后上传："
echo "  Windows:  scp D:\\ComfyUI\\cloud-kit.zip root@<服务器IP>:/root/"
echo "  或浏览器打开 https://github.com/$REPO/releases"
exit 1
