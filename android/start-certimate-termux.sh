#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Certimate 启动脚本（Termux 环境，root 推荐）
#
# DNS 修复：安卓的 /etc/resolv.conf 通常指向 ::1 且只读，导致 Go 程序
# DNS 解析失败。本脚本用 iptables 把本机发往回环 53 的查询重定向到
# 公共 DNS（阿里 223.5.5.5 / 2400:3200::1），无需代理即可解析。
# 也可通过环境变量 PROXY 强制走代理（IP 形式）。
# ============================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="$HOME"

CERT_BIN="$SCRIPT_DIR/certimate"
DATA_DIR="$SCRIPT_DIR/pb_data"
LOG="$SCRIPT_DIR/certimate.log"
HTTP_ADDR="0.0.0.0:8090"

# 可选：填了就用代理（务必用 IP，别用域名），否则走 iptables 重定向
# PROXY="http://192.168.1.100:2080"

echo "[INFO] 脚本目录: $SCRIPT_DIR"

if [ ! -x "$CERT_BIN" ]; then
  echo "[ERR] 找不到可执行文件: $CERT_BIN"
  exit 1
fi

# 1. DNS 修复（root 时）
if [ "$(id -u)" = "0" ]; then
  # 放宽 SELinux，否则 iptables 可能被拦
  if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null && echo "[OK] SELinux -> Permissive"
  fi
  # IPv4: 回环 53 -> 阿里 DNS（先删后加，避免重复）
  iptables -t nat -D OUTPUT -p udp -d 127.0.0.1 --dport 53 -j DNAT --to-destination 223.5.5.5:53 2>/dev/null
  iptables -t nat -A OUTPUT -p udp -d 127.0.0.1 --dport 53 -j DNAT --to-destination 223.5.5.5:53 \
    && echo "[OK] IPv4 回环DNS -> 223.5.5.5:53" \
    || echo "[WARN] IPv4 iptables 失败（可改用 PROXY 代理）"
else
  echo "[WARN] 非 root，跳过 iptables。请设置 PROXY 环境变量走代理。"
fi

# 2. 启动（自带去重）
mkdir -p "$DATA_DIR"
if pgrep -f "certimate serve" >/dev/null 2>&1; then
  echo "[INFO] Certimate 已在运行，跳过启动"
else
  cd "$SCRIPT_DIR"
  if [ -n "$PROXY" ]; then
    HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" NO_PROXY="127.0.0.1,localhost" \
      setsid "$CERT_BIN" serve --http "$HTTP_ADDR" >"$LOG" 2>&1 < /dev/null &
  else
    setsid "$CERT_BIN" serve --http "$HTTP_ADDR" >"$LOG" 2>&1 < /dev/null &
  fi
  sleep 2
  if pgrep -f "certimate serve" >/dev/null 2>&1; then
    echo "[OK] Certimate 已启动"
    echo "     监听: $HTTP_ADDR   日志: $LOG"
    echo "     本地访问: http://127.0.0.1:8090"
    echo "     默认账号: admin@certimate.fun / 1234567890 （请尽快改密码）"
  else
    echo "[ERR] 启动失败，日志尾部："; tail -n 20 "$LOG" 2>/dev/null
  fi
fi
