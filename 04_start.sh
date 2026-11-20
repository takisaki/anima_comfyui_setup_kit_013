#!/usr/bin/env bash
# 启动 / 停止 ComfyUI
#   bash 04_start.sh              前台启动（Ctrl+C 停止；SSH 断开进程会一起退出）
#   bash 04_start.sh --daemon     后台常驻（systemd，断线不影响，服务器重启后自动拉起）
#   bash 04_start.sh --stop       停止后台服务（并取消开机自启）
#   bash 04_start.sh --status     查看状态
#   bash 04_start.sh --logs       跟踪日志（Ctrl+C 只退出日志，不影响服务）
#   bash 04_start.sh --restart    重启后台服务
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"
PORT="${PORT:-8188}"
LISTEN="${LISTEN:-127.0.0.1}"
EXTRA="${EXTRA:-}"
UNIT=comfyui.service

hf_env() {
  echo "export HF_ENDPOINT=${HF_ENDPOINT:-https://hf-mirror.com}"
  echo "export HF_HUB_DISABLE_TELEMETRY=1"
}

write_unit() {
  cat > "/etc/systemd/system/$UNIT" <<EOF
[Unit]
Description=ComfyUI ($PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$COMFY
Environment=HF_ENDPOINT=${HF_ENDPOINT:-https://hf-mirror.com}
Environment=HF_HUB_DISABLE_TELEMETRY=1
Environment=PYTHONUNBUFFERED=1
ExecStart=$COMFY/venv/bin/python main.py --listen $LISTEN --port $PORT --preview-method auto $EXTRA
Restart=on-failure
RestartSec=3
KillSignal=SIGINT
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

case "${1:-run}" in
  --daemon|daemon)
    command -v systemctl >/dev/null 2>&1 || { c_err "系统没有 systemd，改用 nohup 方案"; exit 1; }
    write_unit
    systemctl enable "$UNIT" >/dev/null 2>&1 || true
    systemctl restart "$UNIT"
    sleep 3
    if systemctl is-active --quiet "$UNIT"; then
      c_ok "ComfyUI 已在后台运行（开机自启）"
      echo "   状态:  bash $KIT/04_start.sh --status"
      echo "   日志:  bash $KIT/04_start.sh --logs"
      echo "   停止:  bash $KIT/04_start.sh --stop"
    else
      c_err "启动失败，日志如下："
      journalctl -u "$UNIT" --no-pager -n 30
      exit 1
    fi
    ;;
  --stop|stop)
    systemctl disable --now "$UNIT" >/dev/null 2>&1 || true
    c_ok "已停止 ComfyUI 并取消开机自启"
    ;;
  --restart|restart)
    systemctl restart "$UNIT" && c_ok "已重启"
    ;;
  --status|status)
    if systemctl list-unit-files 2>/dev/null | grep -q "^$UNIT"; then
      systemctl --no-pager status "$UNIT" | head -12
    else
      c_warn "后台服务尚未安装（先 bash 04_start.sh --daemon）"
    fi
    ;;
  --logs|logs)
    journalctl -u "$UNIT" -f
    ;;
  *)
    # shellcheck disable=SC1091
    source "$COMFY/venv/bin/activate"
    export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
    export HF_HUB_DISABLE_TELEMETRY=1
    cd "$COMFY" || exit 1
    cat <<EOF
============================================================
 ComfyUI  http://$LISTEN:$PORT
 这是前台模式：SSH 断开或被 Ctrl+C 都会结束进程。
 想让它常驻后台：bash $KIT/04_start.sh --daemon

 本机浏览器访问：先在你自己的电脑上开一条隧道（窗口别关）
   ssh -N -L $PORT:127.0.0.1:$PORT root@<服务器IP>            # SSH 是 22 端口
   ssh -N -p <SSH端口> -L $PORT:127.0.0.1:$PORT root@<服务器IP>  # 非 22 端口
 注意：ssh 的端口参数是小写 -p；大写 -P 是 scp 的，用错了会连到 22 端口导致密码错误
============================================================
EOF
    exec python main.py --listen "$LISTEN" --port "$PORT" --preview-method auto $EXTRA
    ;;
esac
