#!/usr/bin/env bash
# 步骤 3：下载模型。hf-mirror 与 ModelScope 自动测速选源，单文件失败自动换源
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"
HF_BASE="${HF_BASE:-https://hf-mirror.com}"
MS_API="${MS_API:-https://www.modelscope.cn/api/v1/models}"
TIER="${TIER:-std}"
SOURCE="${SOURCE:-auto}"
MODE="install"

for a in "$@"; do
  case "$a" in
    --check) MODE="check" ;;
    --list)  MODE="list" ;;
    --tier=*) TIER="${a#--tier=}" ;;
    --help|-h)
      cat <<EOF
用法: [TIER=core|std|pro] [SOURCE=auto|hf|ms] bash 03_models.sh [--check|--list]
  core  5.8 GB   Anima 三件套 + 参考图适配器
  std  15.1 GB   + SD1.5 局部重绘 + ControlNet + IPAdapter + CLIP-Vision
  pro  19.3 GB   + anima-base
EOF
      exit 0 ;;
  esac
done

case "$TIER" in core) MAX=1 ;; std) MAX=2 ;; pro) MAX=3 ;;
  *) c_err "TIER 只能是 core/std/pro"; exit 1 ;; esac

ms_url() { printf '%s/%s/repo?Revision=master&FilePath=%s' "$MS_API" "$1" "$2"; }

probe_sources() {
  local s_ms s_hf
  c_log "探测模型源"
  s_ms="$(curl_speed "$(ms_url circlestone-labs/Anima split_files/vae/qwen_image_vae.safetensors)" 8)"
  s_hf="$(curl_speed "$HF_BASE/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors" 8)"
  printf '  %-12s %6.2f MB/s\n' ModelScope "$(awk -v s="$s_ms" 'BEGIN{print s/1000000}')"
  printf '  %-12s %6.2f MB/s\n' hf-mirror "$(awk -v s="$s_hf" 'BEGIN{print s/1000000}')"
  case "$SOURCE" in
    ms) SRC="ms" ;;
    hf) SRC="hf" ;;
    *) [ "$s_ms" -ge "$s_hf" ] && [ "$s_ms" -gt 0 ] && SRC="ms" || SRC="hf" ;;
  esac
  c_ok "使用 $SRC"
}

NEED=0
while IFS='|' read -r r1 d1 n1 h1 s1 m1 m2; do
  case "$r1" in ""|"#"*) continue ;; esac
  [ "$r1" -le "$MAX" ] 2>/dev/null && NEED=$((NEED + ${s1:-0}))
done < "$KIT/models.tsv"
FREE_GB="$(disk_free_gb /root 2>/dev/null)"
FREE_GB="${FREE_GB:-0}"
c_log "磁盘: 可用 ${FREE_GB}GB，本档模型需 $((NEED / 1000000000))GB"
if [ "$FREE_GB" -gt 0 ] && [ "$FREE_GB" -lt $((NEED / 1000000000 + 8)) ]; then
  c_warn "空间偏紧，注意余量"
fi

[ "$MODE" = "install" ] && { SRC=""; probe_sources; }
SRC="${SRC:-auto}"

TOTAL=0; GOT=0; MISS=0; FAIL=0; MANUAL=""
echo "分档 $TIER  源 $SRC"
echo "------------------------------------------------------------"
while IFS='|' read -r rank dest name hf size ms_repo ms_path; do
  case "$rank" in ""|"#"*) continue ;; esac
  [ "$rank" -le "$MAX" ] 2>/dev/null || continue
  size="${size:-0}"
  out="$COMFY/models/$dest/$name"
  alt="$COMFY/models/$dest/${name%.ckpt}.safetensors"
  TOTAL=$((TOTAL + size))

  if [ "$MODE" = "list" ]; then
    printf '%-16s %-48s %-10s %s\n' "$dest" "$name" "$(human "$size")" "${ms_repo:-仅HF}"
    continue
  fi
  if [ -f "$out" ] && { [ "$size" = "0" ] || [ "$(stat -c %s "$out")" -ge $((size - 2000)) ]; }; then
    c_ok "$dest/$name"; GOT=$((GOT + size)); continue
  fi
  [ -f "$alt" ] && { c_ok "$dest/$(basename "$alt")"; GOT=$((GOT + size)); continue; }

  if [ "$size" = "0" ]; then
    if [ "$MODE" = "check" ]; then c_warn "缺 $dest/$name（需手动上传）"; MISS=$((MISS+1));
    else MANUAL="$MANUAL
    $dest/$name"; fi
    continue
  fi
  if [ "$MODE" = "check" ]; then c_warn "缺 $dest/$name $(human "$size")"; MISS=$((MISS+1)); continue; fi

  URLS=()
  case "$SRC" in
    ms) [ -n "$ms_repo" ] && URLS+=("$(ms_url "$ms_repo" "$ms_path")")
        [ -n "$hf" ] && URLS+=("$HF_BASE/$hf") ;;
    *)  [ -n "$hf" ] && URLS+=("$HF_BASE/$hf")
        [ -n "$ms_repo" ] && URLS+=("$(ms_url "$ms_repo" "$ms_path")") ;;
  esac

  c_log "下载 $dest/$name  $(human "$size")"
  if dl "$out" "$size" "${URLS[@]}"; then
    GOT=$((GOT + size)); c_ok "$name"
  else
    FAIL=$((FAIL+1)); c_err "$name 全部源失败"
  fi
done < "$KIT/models.tsv"

[ "$MODE" = "list" ] && { echo "------------------------------------------------------------"; echo "合计 $(human "$TOTAL")"; exit 0; }
[ "$MODE" = "check" ] && { echo "------------------------------------------------------------"; echo "齐备 $(human "$GOT") / $(human "$TOTAL")，缺 $MISS"; exit $([ "$MISS" = "0" ] && echo 0 || echo 1); }

echo "------------------------------------------------------------"
echo "已就绪 $(human "$GOT") / $(human "$TOTAL")，失败 $FAIL"
if [ -n "$MANUAL" ]; then
  echo
  echo "需要从本机上传的文件:$MANUAL"
  echo "  scp 到 /root/upload/ 后执行:"
  echo "  cp /root/upload/*.safetensors $COMFY/models/loras/ 2>/dev/null"
  echo "  cp /root/upload/control_*.safetensors $COMFY/models/controlnet/ 2>/dev/null"
fi

CKPT="$COMFY/models/checkpoints/sd-v1-5-inpainting.ckpt"
ST="$COMFY/models/checkpoints/sd-v1-5-inpainting.safetensors"
if [ -f "$CKPT" ] && [ ! -f "$ST" ]; then
  c_log "转换 .ckpt -> .safetensors"
  if ( source "$COMFY/venv/bin/activate" && COMFY="$COMFY" python "$KIT/convert_ckpt.py" ); then
    [ "${KEEP_CKPT:-0}" = "1" ] || { rm -f "$CKPT"; c_ok "已删除 .ckpt"; }
  else
    c_warn "转换失败：在 04 工作流里把底模改选 sd-v1-5-inpainting.ckpt"
  fi
fi
df -h /root | tail -1
[ "$FAIL" = "0" ] && c_ok "步骤 3 完成" || exit 2
