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

## 八、一键同步上游并发布安卓版

仓库根目录提供 `sync-android.sh`，把「同步上游 → 打安卓版 tag → 推送触发 CI」串成一步：

```sh
chmod +x sync-android.sh
./sync-android.sh
```

脚本会自动：拉取上游最新代码/标签 → 合并 `upstream/main` 并 push 到你的 fork（触发 CI 构建
`linux/arm64` + `android/arm64` 两个 Artifact）→ 基于上游最新版本号打 `vX.Y.Z-android` tag 并
push（触发 CI 把两个二进制上传到 GitHub **Release**，永久可下载）。

可用环境变量微调：`UPSTREAM`（默认 `upstream`）、`ORIGIN`（默认 `origin`）、`TAG_SUFFIX`（默认 `-android`）。

> 前置要求：本地已配置 `upstream` 指向官方 `certimate-go/certimate`、且 `origin` 指向你的 fork
> （首次使用见第七节）。脚本会先检查工作区是否干净，有未提交改动会中止。
