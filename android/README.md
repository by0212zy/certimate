# Certimate 安卓运行指南

本目录提供在 **安卓（ARM64）设备**上运行 Certimate 的方式。Certimate 是 Go 编写的
自托管证书管理工具，官方预编译包为 `linux/arm64` / `android/arm64`，**均可在安卓上作为
普通 Linux 进程运行**（无需安卓 App / 无需 Docker）。

> ⚠️ 安卓不是长期运行服务器：系统会回收后台进程、重启后需手动拉起。
> 仅建议把手机/平板当作**临时或演示环境**；正式用途请部署到常开服务器 / NAS / 树莓派。

## 一、两种二进制（由 CI 自动打包）

仓库 `.github/workflows/android-build.yml` 在每次 push / tag 时自动产出两个产物：

| 产物 | 编译方式 | DNS 行为 | 适用场景 |
| :--- | :--- | :--- | :--- |
| `certimate-linux-arm64` | 纯 Go (`CGO=0`) | 走 `/etc/resolv.conf`（安卓上常为 `::1`，需下方脚本修复） | 兼容性最好、最稳定，**推荐** |
| `certimate-android-arm64` | `GOOS=android` + CGO + NDK | 走 bionic `getaddrinfo` → **安卓系统 DNS**，开箱即用 | 进阶，无需代理/iptables |

下载：仓库 **Releases** 页面（打 tag 时）或 Actions 运行的 **Artifacts**。

## 二、放置二进制（重要）

安卓的 `/sdcard` 是 FAT 格式，**不能 chmod +x、无法执行二进制**。请放到支持 Linux 权限的分区：

- 推荐：`/data/local/tmp/certimate/` 或 `/data/1/0/`（随你习惯）
- 用 MT 管理器把二进制复制进去 → 长按 → 属性 → 权限设为 **0755**

```
/data/local/tmp/certimate/
├── certimate            # 二进制, 0755
├── start-certimate-mt.sh
└── pb_data/             # 运行时自动生成的数据（证书/数据库）
```

## 三、MT 管理器（root）运行

使用本目录的 `start-certimate-mt.sh`：

1. 把 `start-certimate-mt.sh` 放到与二进制同一目录，权限 0755。
2. MT 管理器 → 终端，以 **root** 执行：
   ```sh
   sh /data/local/tmp/certimate/start-certimate-mt.sh
   ```
3. 浏览器打开 `http://127.0.0.1:8090`，默认账号 `admin@certimate.fun / 1234567890`。

该脚本通过**本机真实 IP（如 192.168.x.x）作为代理地址**绕过部分代理 App 对
`127.0.0.1` 的拒绝（代理端口固定 `2080`）。前提：代理 App 已开启
**「允许局域网连接」**。若需固定 IP，编辑脚本顶部 `LOCAL_IP_OVERRIDE`。

## 四、Termux 运行（root 推荐）

使用 `start-certimate-termux.sh`：

```sh
cd ~/certimate
bash start-certimate-termux.sh
```

脚本会（root 下）用 `iptables` 把本机回环 53 的 DNS 查询重定向到公共 DNS
（阿里 `223.5.5.5`），**无需代理**即可解析。也可在脚本顶部填 `PROXY` 走代理。

## 五、DNS 问题排查

安卓 DNS 由系统 `netd` 管理，Go 纯静态二进制默认只认 `/etc/resolv.conf`（常为 `::1`，
导致 `lookup ... on [::1]:53: connection refused`）。三种解决：

1. **用 `certimate-android-arm64` 版本**：CGO+NDK 编译，直接走系统 DNS，无需任何配置。
2. **用启动脚本**：`start-certimate-mt.sh`（代理）或 `start-certimate-termux.sh`（iptables 重定向）。
3. **手动设代理**：启动前 `export HTTP_PROXY=http://代理IP:端口`（**务必用 IP**），由代理解析域名。

## 六、证书申请建议

手机通常无公网 IP / 未开放 80/443，Let's Encrypt 的 **HTTP-01** 验证难以满足。
建议在 Certimate 工作流里使用 **DNS-01** 验证（填入 DNS 服务商 API 密钥），无需开放任何端口。

## 七、与上游同步

本仓库基于官方 [certimate-go/certimate](https://github.com/certimate-go/certimate)。
已配置 `upstream` remote，可随时拉取官方更新：

```sh
git fetch upstream
git merge upstream/main        # 把官方新功能合并进来
git push origin main          # 推到你的仓库
```

或在 GitHub 网页用 `gh` 同步：

```sh
gh repo sync by0212zy/certimate --source certimate-go/certimate
```

> 若官方修改了 `go.mod` / 构建方式，重新触发 Actions 即可重新打包安卓版。

## 八、Let's Encrypt 在中国大陆：IPv4 被阻断，强制走 IPv6

**现象**：浏览器 / VPN 客户端能打开 `acme-v02.api.letsencrypt.org`，但 certimate 报
`TLS handshake timeout` 或 `read ... -> 172.65.32.248:443: connection reset by peer`。

**原因**：Let's Encrypt 主机走 Cloudflare，其 **IPv4 路径在中国大陆常被阻断**，
而设备自带的 **IPv6 路径是通的**（`curl -v https://acme-v02.api.letsencrypt.org/directory`
走 IPv6 能返回 `HTTP/2 200`）。Go 的「Happy Eyeballs」会先尝试 IPv4，而 IPv4 在
TLS 阶段才被 RST，Go 误以为「已连接」便返回了 IPv4 连接，**IPv6 没机会被使用**。

> 同一网络下 `acme.litessl.com`（LiteSSL / freessl.cn，国内直连）是通的，但它强制要求
> EAB 绑定（详见第 X 节）。若不想配 EAB，用下面的「强制 IPv6」方案即可继续用 Let's Encrypt。

### 方案 A（推荐，两种二进制都适用）：本地 IPv6 代理 + `HTTPS_PROXY`

lego v5 的 `http.Client` 设置了 `Proxy: http.ProxyFromEnvironment`，会读取 `HTTPS_PROXY`。
本目录的 `ipv6-proxy.py`（**纯 Python 标准库，无需 pip 安装**）收到请求后**优先用 IPv6
解析并拨号**目标主机，再双向转发。所有 ACME 流量（目录 / newAccount / newOrder / OCSP / AIA）
都从设备 IPv6 出口出去，绕过被墙的 IPv4。

```sh
# 1) 启动代理（监听 127.0.0.1:8899）
nohup python3 ipv6-proxy.py 8899 >/dev/null 2>&1 &

# 2) 让 certimate 走该代理启动（lego 自动读取 HTTPS_PROXY）
HTTPS_PROXY=http://127.0.0.1:8899 ./certimate serve --http 0.0.0.0:8090
```

验证代理是否生效：启动后看 certimate 日志里的 ACME 报错是否消失；或另开终端
`curl -x http://127.0.0.1:8899 https://acme-v02.api.letsencrypt.org/directory` 应返回 JSON。

### 方案 B（快速，仅适用于 `certimate-linux-arm64` 即 CGO=0 版）：`/etc/hosts` 钉死 IPv6

纯 Go 解析器会读 `/etc/hosts`（Termux 的 `/etc/hosts` 无需 root 即可改）：

```sh
echo "2606:4700:60:0:f53d:5624:85c7:3a2c acme-v02.api.letsencrypt.org" >> $PREFIX/etc/hosts
```

> ⚠️ `certimate-android-arm64`（CGO+NDK 版）走安卓系统解析器，**不读 /etc/hosts**，
> 方案 B 对它无效；方案 A 两种二进制都适用。
> 若申请时还报其它 `*.lencr.org` / `*.letsencrypt.org` 域名解析/连接失败，把对应主机也
> 用 `curl -v` 取到的 IPv6 追加进 `/etc/hosts` 即可（或改用方案 A，一劳永逸）。

### LiteSSL / freessl.cn 的 EAB（如果想用国内 CA 而非 Let's Encrypt）

LiteSSL（`acme.litessl.com`）是 TrustAsia 旗下国内直连 CA，**强制要求 EAB 绑定**：
1. 打开 https://freessl.cn 注册登录 → 证书自动化 → ACME 账户管理 → 新增凭证，
   拿到 **Key ID** 与 **HMAC Key**。
2. certimate：「设置 → 证书颁发机构 → 编辑 LiteSSL」，填入 **EAB Key ID / EAB HMAC Key** → 保存。
3. 重新申请证书。
