#!/system/bin/sh
# ============================================================
# Certimate 启动脚本（MT 管理器 / 安卓 root 环境）— 代理版(本机真实IP)
#
# 用本机真实 IP（如 192.168.x.x）作为代理地址，绕过部分代理 App
# 对 loopback(127.0.0.1) 连接的拒绝。代理端口固定 2080。
# 注意：此方式要求代理 App 已开启「允许局域网连接」(绑定 0.0.0.0)。
# ============================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR=/data/1/0

CERT_BIN="$SCRIPT_DIR/certimate"
DATA_DIR="$SCRIPT_DIR/pb_data"
LOG="$SCRIPT_DIR/certimate.log"
HTTP_ADDR="0.0.0.0:8090"
PROXY_PORT="2080"

# 如需手动指定本机 IP，取消下一行注释并填写：
# LOCAL_IP_OVERRIDE="192.168.1.100"

get_local_ip() {
  if [ -n "$LOCAL_IP_OVERRIDE" ]; then echo "$LOCAL_IP_OVERRIDE"; return; fi
  # 优先取常见无线/有线接口
  for IF in wlan0 wlan1 eth0; do
    I=$(ip addr show "$IF" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    [ -n "$I" ] && { echo "$I"; return; }
  done
  # 兜底：第一个非回环 IPv4
  ip addr 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1
}

LOCAL_IP=$(get_local_ip)
[ -z "$LOCAL_IP" ] && LOCAL_IP="127.0.0.1"
PROXY="http://$LOCAL_IP:$PROXY_PORT"

echo "[INFO] 脚本目录: $SCRIPT_DIR"
echo "[INFO] 本机IP: $LOCAL_IP"
echo "[INFO] 代理地址: $PROXY"

# 1. 二进制检查
if [ ! -x "$CERT_BIN" ]; then
  echo "[ERR] 找不到可执行文件: $CERT_BIN"
  echo "      请确认 certimate 二进制已放到该目录并赋予执行权限(0755)"
  exit 1
fi

# 2. 启动 Certimate（自带去重，避免重复进程）
#    通过环境变量把流量导向本机代理；NO_PROXY 排除本机回环，
#    避免代理访问自身造成死循环。
mkdir -p "$DATA_DIR"
if pidof certimate >/dev/null 2>&1; then
  echo "[INFO] Certimate 已在运行，跳过启动"
else
  cd "$SCRIPT_DIR"
  HTTP_PROXY="$PROXY" \
  HTTPS_PROXY="$PROXY" \
  NO_PROXY="127.0.0.1,localhost" \
  setsid "$CERT_BIN" serve --http "$HTTP_ADDR" >"$LOG" 2>&1 < /dev/null &
  sleep 2
  if pidof certimate >/dev/null 2>&1; then
    echo "[OK] Certimate 已启动（流量走代理 $PROXY）"
    echo "     监听: $HTTP_ADDR"
    echo "     日志: $LOG"
    echo "     本地访问: http://127.0.0.1:8090"
    echo "     默认账号: admin@certimate.fun / 1234567890 （请尽快改密码）"
  else
    echo "[ERR] 启动失败，请查看日志: $LOG"
    echo "----- 日志尾部 -----"
    tail -n 20 "$LOG" 2>/dev/null
  fi
fi
