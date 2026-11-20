#!/usr/bin/env bash
# 启动 / 停止 / 查看 ComfyUI
#   bash 04_start.sh              前台启动（默认：连接一断，进程随之退出）
#   bash 04_start.sh --stop       停止所有实例（systemd 的和前台残留的都算）
#   bash 04_start.sh --status     谁占着端口、内存多少
#   bash 04_start.sh --daemon     后台常驻（systemd，断线不影响，开机自启）
#   bash 04_start.sh --logs       跟踪 systemd 日志
#   bash 04_start.sh --restart    重启后台服务
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
source "$KIT/lib.sh"
COMFY="${COMFY:-/root/ComfyUI}"
PORT="${PORT:-8188}"
LISTEN="${LISTEN:-127.0.0.1}"
EXTRA="${EXTRA:-}"
UNIT=comfyui.service

# 找到占用端口的进程 + 命令行匹配的进程（前台起的不会被漏掉）
find_pids() {
  {
    ss -ltnp 2>/dev/null | grep -E ":$PORT[[:space:]]" | grep -o 'pid=[0-9]*' | cut -d= -f2
    pgrep -f "main.py --listen" 2>/dev/null
  } | grep -E '^[0-9]+$' | sort -u
}

do_stop() {
  local pids
  pids="$(find_pids || true)"
  if [ -z "$pids" ]; then
    c_warn "没有正在运行的 ComfyUI（端口 $PORT 空闲）"
  else
    echo "找到进程: $(echo $pids | tr '\n' ' ')"
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
    for i in 1 2 3 4 5 6 7 8; do
      sleep 1
      pids="$(find_pids || true)"
      [ -z "$pids" ] && break
    done
    if [ -n "$pids" ]; then
      echo "仍未退出，强制结束: $(echo $pids | tr '\n' ' ')"
      # shellcheck disable=SC2086
      kill -KILL $pids 2>/dev/null || true
    fi
    c_ok "已停止"
  fi
  systemctl disable --now "$UNIT" >/dev/null 2>&1 && c_ok "已关闭 systemd 服务与开机自启" || true
}

do_status() {
  echo "== 端口 $PORT =="
  ss -ltnp 2>/dev/null | grep -E ":$PORT[[:space:]]" || echo "   无人监听"
  echo "== 进程 =="
  local pids; pids="$(find_pids || true)"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    ps -o pid,ppid,etime,rss,cmd -p $pids 2>/dev/null | head -5
    echo "== 线程数 =="
    # shellcheck disable=SC2086
    ps -o nlwp= -p $(echo $pids | head -1) 2>/dev/null | awk '{print "   " $1 " 个线程"}'
  else
    echo "   没有 ComfyUI 进程"
  fi
  echo "== systemd =="
  systemctl is-active "$UNIT" 2>/dev/null || echo "   未使用 systemd（前台模式）"
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
  --stop|stop)     do_stop ;;
  --status|status) do_status ;;
  --daemon|daemon)
    command -v systemctl >/dev/null 2>&1 || { c_err "没有 systemd"; exit 1; }
    write_unit
    systemctl enable "$UNIT" >/dev/null 2>&1 || true
    systemctl restart "$UNIT"
    sleep 3
    if systemctl is-active --quiet "$UNIT"; then
      c_ok "后台运行中（开机自启）"
      echo "   停止: bash $KIT/04_start.sh --stop"
    else
      c_err "启动失败:"; journalctl -u "$UNIT" --no-pager -n 30; exit 1
    fi
    ;;
  --restart|restart) systemctl restart "$UNIT" && c_ok "已重启" ;;
  --logs|logs)       journalctl -u "$UNIT" -f ;;
  *)
    # shellcheck disable=SC1091
    source "$COMFY/venv/bin/activate"
    export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
    export HF_HUB_DISABLE_TELEMETRY=1
    cd "$COMFY" || exit 1
    cat <<EOF
============================================================
 ComfyUI  http://$LISTEN:$PORT
 进程: $COMFY/venv/bin/python main.py  (pid 记下来: $$ 之后 exec)
 前台模式：连接一断，进程随即退出（默认行为）。
 停止: 在任意终端执行  bash $KIT/04_start.sh --stop
 查看: bash $KIT/04_start.sh --status

 本机访问：先开隧道（窗口别关）
   ssh -N -p <SSH端口> -L $PORT:127.0.0.1:$PORT root@<服务器IP>
   注意 ssh 端口是小写 -p（大写 -P 是 scp 的）
============================================================
EOF
    exec python main.py --listen "$LISTEN" --port "$PORT" --preview-method auto $EXTRA
    ;;
esac
