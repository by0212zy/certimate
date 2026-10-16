#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ipv6-proxy.py —— 本地 IPv6 优先的 HTTP(S) 正向代理（纯标准库，无需 pip 安装）

用途：
    在「IPv4 到 Let's Encrypt / Cloudflare 被阻断，但 IPv6 可用」的网络环境下，
    让 certimate (底层 lego) 的所有 ACME 流量通过本机 IPv6 出口，
    从而成功连接 acme-v02.api.letsencrypt.org 等 ACME 服务器。

原理：
    lego v5 的 http.Client 设置了 `Proxy: http.ProxyFromEnvironment`，
    会读取 HTTPS_PROXY 环境变量。
    本代理收到 CONNECT 请求后，优先用 IPv6 解析并拨号目标主机，再双向转发。

用法：
    python3 ipv6-proxy.py [port]        # 默认监听 127.0.0.1:8899
后台运行：
    nohup python3 ipv6-proxy.py 8899 >/dev/null 2>&1 &
随后启动 certimate（lego 会自动走 HTTPS_PROXY）：
    HTTPS_PROXY=http://127.0.0.1:8899 ./certimate serve --http 0.0.0.0:8090

仅依赖 Python 标准库（socket / threading / urllib）。
"""
import socket
import sys
import threading

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899


def resolve(host, port):
    """优先返回 IPv6 地址；无 IPv6 时回退 IPv4。"""
    try:
        addrs = socket.getaddrinfo(host, port, socket.AF_INET6, socket.SOCK_STREAM)
        return addrs[0][4], True
    except Exception:
        addrs = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        return addrs[0][4], False


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                s.close()
            except Exception:
                pass


def handle(client):
    try:
        head = client.recv(65536)
        if not head:
            return
        first_line = head.split(b"\r\n", 1)[0].decode(errors="ignore")
        parts = first_line.split()
        if len(parts) < 2:
            return
        method, target = parts[0].upper(), parts[1]

        if method == "CONNECT":
            # target 形如 host:port
            if ":" in target:
                host, port = target.rsplit(":", 1)
            else:
                host, port = target, "443"
            host = host.strip("[]")
            port = int(port)
            addr, _is_v6 = resolve(host, port)
            remote = socket.create_connection(addr, timeout=30)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            threading.Thread(target=pipe, args=(client, remote), daemon=True).start()
            threading.Thread(target=pipe, args=(remote, client), daemon=True).start()
        else:
            # 普通 HTTP 正向代理（ACME 基本用不到，做最小支持）
            if "://" in target:
                from urllib.parse import urlparse
                u = urlparse(target)
                host = u.hostname
                port = u.port or 80
            elif ":" in target:
                host, port = target.rsplit(":", 1)
                port = int(port)
            else:
                host, port = target, 80
            addr, _is_v6 = resolve(host, int(port))
            remote = socket.create_connection(addr, timeout=30)
            remote.sendall(head)
            threading.Thread(target=pipe, args=(client, remote), daemon=True).start()
            threading.Thread(target=pipe, args=(remote, client), daemon=True).start()
    except Exception:
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        except Exception:
            pass
        try:
            client.close()
        except Exception:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(128)
    print(f"[ipv6-proxy] listening on {LISTEN_HOST}:{LISTEN_PORT} (IPv6 preferred)")
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
