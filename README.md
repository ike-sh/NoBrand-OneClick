# NoBrand-OneClick

[![Latest Release](https://img.shields.io/github/v/release/ike-sh/NoBrand-OneClick?display_name=tag)](https://github.com/ike-sh/NoBrand-OneClick/releases/latest)
[![License](https://img.shields.io/github/license/ike-sh/NoBrand-OneClick)](LICENSE)

NoBrand-OneClick 是一个面向 Linux 服务器的多协议代理、隧道与网络入口管理工具。它通过统一的 `nobrand` 管理界面部署和维护 Mieru、Snell、Hysteria2、TUIC、VLESS 与 SSH Tunnel，并提供 Multi-Ingress、Strict Ingress、Port Forward、备份与恢复等能力。

当前稳定版本：[v3.2.0](https://github.com/ike-sh/NoBrand-OneClick/releases/tag/v3.2.0)

正式管理命令：`nobrand`；短别名：`nb`

## 功能概览

- 使用单一 `nobrand` / `nb` 命令管理全部协议、节点和网络功能，并同时提供交互菜单与非交互 CLI。
- 通过 Multi-Ingress 的 Public、Mapped Ingress Profile 表达单网卡、多网卡及映射入口。
- 支持 `permissive` 与 `strict` 两种 Ingress Enforcement，以及 `derived-tail`、`custom-range`、`manual-only` 三种端口策略。
- 分离 Actual Listener 与 Display Endpoint：客户端展示地址可以独立于服务端真实监听地址。
- 提供多用户或多实例管理、客户端配置导出、统一节点视图、状态检查与 Doctor。
- 通过 nftables 或 Realm 管理 TCP、UDP、BOTH 端口转发，并支持规则导入、导出与后端切换。
- 配置和生命周期变更采用事务式流程；验证失败时尽可能恢复原有配置、状态与运行服务。
- 统一备份、恢复和卸载覆盖 NoBrand 管理的协议、入口、转发规则与凭据。

## 支持的协议

| 协议 | 传输 | 服务端实现 | 客户端 / 导出 | 说明 |
|---|---|---|---|---|
| Mieru | TCP / UDP / BOTH | 官方 Mita runtime | `mierus://`、官方 Mieru client JSON、Mihomo YAML | 多用户、独立实例、配额、到期、限速与 Profile |
| Snell v5 | TCP；可选同端口 UDP 暴露 | Surge `snell-server` | Surge、Mihomo、sing-box（默认 QUIC 关闭路径） | 默认版本；QUIC 公网暴露默认关闭 |
| Snell v4 | TCP | Surge `snell-server` | Surge、Mihomo、sing-box | 兼容版本 |
| Hysteria2 | UDP / TLS / h3 / Salamander | Xray-core | `hysteria2://`、Mihomo、sing-box | 使用独立证书和认证信息 |
| TUIC v5 | UDP / QUIC / TLS / h3 | NoBrand 管理的官方 sing-box | Mihomo YAML、sing-box JSON | 每用户独立 UUID 与 password；不生成非标准 URI |
| VLESS + FinalMask/Sudoku | TCP | Xray-core | `vless://`、Xray client JSON | Plain VLESS，不启用 VLESS Encryption |
| VLESS + REALITY + Vision | TCP / REALITY / `xtls-rprx-vision` | Xray-core | `vless://`、Xray JSON、Mihomo YAML、sing-box JSON | 独立命名实例与可配置伪装目标 |
| SSH Tunnel | TCP forwarding：`-L` / `-D` / `-R` | 系统现有 OpenSSH `sshd` | private key、`known_hosts`、OpenSSH config、SOCKS5 命令 | key-only；不提供 shell 或原生 UDP forwarding |

Port Forward 是通用网络功能，不是代理协议；其 nftables 与 Realm 后端见[端口转发](#端口转发)。

## 安装

推荐从 GitHub Latest Release 获取正式安装器：

```bash
curl -fsSLO https://github.com/ike-sh/NoBrand-OneClick/releases/latest/download/install-nobrand.sh
sudo bash install-nobrand.sh
```

安装器会打开统一交互菜单。完成管理器安装后，公开命令位于：

```text
/usr/local/bin/install-nobrand
/usr/local/bin/nobrand
/usr/local/bin/nb
```

Alpine Linux 默认可能没有 Bash；请先安装 `bash` 与 `curl`，然后以 root 身份执行 `bash install-nobrand.sh`，不使用 `sudo`。

## 快速开始

```bash
nobrand --version
nobrand --help

sudo nobrand
sudo nobrand status
sudo nobrand nodes
sudo nobrand doctor
```

不带参数运行 `nobrand` 会进入统一菜单。`nb` 与 `nobrand` 完全等价；安装、修改、恢复和卸载等管理操作需要 root 权限。

可以按协议筛选统一节点视图：

```bash
sudo nobrand nodes --protocol mieru
sudo nobrand nodes --protocol vless-reality
sudo nobrand nodes --protocol forward
```

## Multi-Ingress

Ingress Profile 用于描述客户端如何进入服务器，并将入口身份、端口分配、真实监听和客户端展示信息分开管理。

| 概念 | 用户可见含义 |
|---|---|
| Ingress Profile | 入口名称、类型、本地接口与 IPv4、端口策略、默认 Display Endpoint 和 Enforcement |
| Actual Listener | 协议服务或 Forward 数据面真实接收流量的地址与端口 |
| Display Endpoint | 写入分享链接、客户端配置、导出和 `nobrand nodes` 的地址与端口 |
| Forward Target | Forward 规则的目标地址；不等于入口地址或 Display Endpoint |

Profile 类型：

- `public`：所选本地 IPv4 可直接作为默认公开入口；未指定 Display Host 时使用该地址。
- `mapped`：服务器本地接收地址与客户端连接地址不同；必须明确提供 Display Host。

端口策略：

- `derived-tail`：若所选本地 IPv4 的最后一段为 `N`，保留 `N×100`，自动端口池为 `N×100+1` 至 `N×100+99`。
- `custom-range`：使用管理员指定的自动端口范围与保留端口。
- `manual-only`：不自动分配端口，创建节点或 Forward 规则时必须指定 Actual port。

Ingress Enforcement：

- `permissive` 是默认模式，保留 wildcard listener 行为。
- `strict` 将 NoBrand 管理的入口限制到 Profile 的本地地址。它不会修改 Linux 的地址、路由、`ip rule`、默认 egress 或服务商映射。
- SSH Tunnel 复用系统 `sshd`，因此 Strict Ingress 不接管其真实监听；Profile 只为 SSH 节点提供展示默认值。

创建 Profile 时需要提供服务器上的真实接口和本地 IPv4。CLI 语法如下：

```text
sudo nobrand ingress add --name NAME --type public|mapped \
  --interface INTERFACE --address LOCAL_IPV4 \
  --port-policy derived-tail|custom-range|manual-only \
  --enforcement permissive|strict
```

常用操作：

```bash
sudo nobrand ingress set-default PROFILE
sudo nobrand ingress modify PROFILE --enforcement strict --apply-existing -y
sudo nobrand ingress apply PROFILE
sudo nobrand ingress list
sudo nobrand ingress show PROFILE
sudo nobrand ingress doctor
```

设置默认 Profile 只影响之后未显式选择入口的新节点；现有节点不会被自动改写。修改被现有节点引用的 Enforcement 或 strict 本地地址时，使用 `--apply-existing` 执行显式迁移。

完整模型与端口策略见 [Multi-Ingress 文档](docs/MULTI-INGRESS-3.2.md)。

## 节点与协议管理

### Mieru

Mieru 使用官方 Mita runtime，并保留多用户、独立实例、TCP/UDP/BOTH、Profile、MTU、Multiplexing、Handshake、Traffic Pattern、Low Entropy、配额、到期、限速与批量客户端导出等管理能力。

默认 `stable` channel 在安装或显式升级事务开始时解析官方最新稳定版；`latest` 是相同语义的兼容别名。v3.2.0 发布时验证版本以及在线 release metadata 获取失败时使用的已知良好回退版本为 3.36.0。`status`、`nodes`、`doctor` 等只读操作不会联网解析版本，也不会静默升级现有 runtime。

```bash
sudo nobrand mieru install
sudo nobrand mieru users
sudo nobrand mieru user-add
sudo nobrand mieru user-show USER
sudo nobrand mieru user-export-clients
sudo nobrand mieru show
sudo nobrand mieru status
sudo nobrand mieru doctor
```

Display Endpoint 变更只更新节点和客户端输出，不会改写 Mita 服务端配置、listener、service、firewall、限速或配额状态。完整参数合同见 [Mieru 文档](docs/MIERU-PARITY-3.0.md)。

### 其他协议入口

| 产品 | 安装入口 | 常用管理动作 |
|---|---|---|
| Snell | `nobrand snell install --name NAME` | `show`、`status`、`doctor`、`set-quic`、`set-endpoint`、`remove` |
| Hysteria2 | `nobrand hy2 install` | `show`、`status`、`doctor`、`set-endpoint`、`remove` |
| TUIC v5 | `nobrand tuic install --name NAME --user USER` | `user`、`show`、`export`、`status`、`doctor`、`set-endpoint`、`upgrade-runtime`、`uninstall` |
| VLESS + FinalMask/Sudoku | `nobrand vless-sudoku install` | `show`、`status`、`doctor`、`set-endpoint`、`remove` |
| VLESS REALITY | `nobrand vless-reality install --name NAME` | `show`、`export`、`status`、`doctor`、`set-endpoint`、`remove` |
| SSH Tunnel | `nobrand ssh install --user USER` | `user`、`show`、`export`、`status`、`doctor`、`set-endpoint`、`uninstall` |

对配置有写入的命令请使用 root 权限。`status`、`nodes` 和普通 Doctor 不显示密码或私钥；`show` / `export` 属于明确请求凭据或客户端配置的操作，应谨慎保存其输出。

## REALITY

NoBrand 将 REALITY 作为独立命名实例管理，固定使用 `VLESS + TCP + REALITY + xtls-rprx-vision`。每个实例拥有独立的 UUID、X25519 keypair、short ID、公开 TCP listener、Ingress Profile、Display Endpoint 与伪装配置。

默认伪装模式为 `auto`，默认伪装目标端口为 `443`。安装时会从内置合格候选池中选择当前可用的 hostname，并将选择结果持久化到该节点；restart、status、show、export、Doctor、backup 和 restore 不会重新随机。公开 REALITY listen port 与伪装 target port 相互独立。

```bash
sudo nobrand vless-reality install --name edge-reality
sudo nobrand vless-reality show --name edge-reality
sudo nobrand vless-reality export --name edge-reality
sudo nobrand vless-reality doctor
```

需要自定义目标时，可分别设置 hostname 和 target port：

```text
sudo nobrand vless-reality install --name NAME \
  --target CAMOUFLAGE_HOST --target-port CAMOUFLAGE_PORT
```

自定义目标会按原值验证；不兼容时安装事务终止，不会静默改用自动候选。并非所有正常 HTTPS 网站都适合作为 REALITY 伪装目标，自定义目标需要满足 REALITY/TLS 兼容性要求。

服务端保持 `minClientVer=0.0.0`；该字段不需要写入客户端导出。REALITY 还使用内部 loopback defender 隔离 fallback，只允许符合目标 hostname 的 TLS 流量进入伪装目标。Public Profile 是推荐入口；Mapped Profile 可以使用，但需要管理员确认实际网络映射与返回路径。

字段、导出格式与排障说明见 [VLESS REALITY 文档](docs/VLESS-REALITY-3.2.md)。

## 端口转发

`nobrand forward` 使用统一规则模型管理两种后端：

| 后端 | 数据面 | 协议 | Target | 适用场景 |
|---|---|---|---|---|
| nftables | 内核 DNAT | TCP / UDP / BOTH | IPv4 literal | 轻量 IP 转发；默认 MASQUERADE，可选 Preserve Source |
| Realm | userspace relay | TCP / UDP / BOTH | IPv4 / IPv6 / domain | 域名、指定出站地址或接口、Proxy Protocol、DNS、transport 与负载均衡 |

下面的目标地址是文档示例，使用时请替换为真实目标：

```bash
sudo nobrand forward add --name web \
  --backend nftables --protocol TCP \
  --listen 0.0.0.0 --port 24443 \
  --target 203.0.113.10 --target-port 443
```

```bash
sudo nobrand forward list
sudo nobrand forward show web
sudo nobrand forward modify web --target 198.51.100.20 --target-port 443
sudo nobrand forward disable web
sudo nobrand forward enable web
sudo nobrand forward switch-backend web --backend realm
sudo nobrand forward set-endpoint web --advertise-host edge.example.com --advertise-port 443
sudo nobrand forward doctor
sudo nobrand forward export /root/nobrand-forward.json
sudo nobrand forward import /root/nobrand-forward.json
```

Display Endpoint 变更只更新规则的客户端展示信息，不改变 listener、DNAT/Realm 数据面、Target 或端口占用关系。Preserve Source 模式要求目标服务器具有返回转发机的正确路由。

详细后端差异和高级参数见 [Port Forward 文档](docs/FORWARD-REFERENCE-3.1.md)。

## 常用管理命令

| 命令 | 用途 |
|---|---|
| `nobrand --help` | 查看完整 CLI 与各协议入口 |
| `nobrand --version` | 查看当前管理器版本 |
| `nobrand status` | 查看全部已管理产品的综合状态 |
| `nobrand nodes [--protocol P]` | 查看全部节点或按协议筛选 |
| `nobrand doctor` | 执行综合状态、配置、listener 与引用检查 |
| `nobrand ingress list`、`nobrand ingress show PROFILE`、`nobrand ingress doctor` | 查看或检查 Ingress Profile |
| `nobrand backup create`、`nobrand backup list`、`nobrand backup restore FILE` | 创建、列出或恢复统一备份 |
| `nobrand manager install`、`nobrand manager upgrade` | 从当前实际执行的安装器安装或替换统一管理器 |
| `nobrand uninstall [-y]` | 统一卸载 NoBrand 管理的资源 |

各协议的准确参数以 `nobrand --help` 为准。

## 配置、备份与恢复

NoBrand 的权威状态与配置分别保存在：

```text
/var/lib/nobrand-oneclick/
/etc/nobrand-oneclick/
```

```bash
sudo nobrand backup create
sudo nobrand backup list
sudo nobrand backup restore /path/to/nobrand-backup.tar.gz
```

统一备份包含 Ingress Profile、节点、Forward 规则、服务配置及恢复所需凭据，包括 REALITY private key、TUIC password、TLS key 和 SSH private key。备份文件应按 root 级敏感文件处理，不应上传到公开存储、日志或工单。

备份归档不包含已下载的 runtime binary；恢复流程会根据权威状态重新安装所需 runtime 并重建服务。恢复还会验证归档类型、schema、路径与配置。服务、listener 或策略验收失败时，恢复流程会尝试回滚到原有状态。备份恢复的是 NoBrand 应用状态，不会创建网卡地址、系统路由或服务商侧映射。

## 更新与卸载

更新到新的 NoBrand 正式版本时，先按[安装](#安装)章节重新下载 Latest Release 安装器，再让这份新安装器替换统一管理器：

```bash
sudo bash install-nobrand.sh manager upgrade
nobrand --version
```

直接运行已安装的 `nobrand manager upgrade` 只会重新部署当前版本，不会自行下载或切换到另一个发布版本。

协议 runtime 使用显式升级入口，例如：

```bash
sudo nobrand mieru upgrade
sudo nobrand tuic upgrade-runtime
```

只读命令不会隐式升级 runtime、旋转凭据或重启服务。

统一卸载：

```bash
sudo nobrand uninstall -y
```

卸载只清理由 NoBrand 明确管理的协议实例、配置、服务、端口、转发规则、凭据和命令；系统 `sshd`、外部 Xray/sing-box/Realm、无关 firewall 规则、系统网络配置与服务商映射不会被接管或删除。

如果安装了 SSH Tunnel，策略变更和卸载采用管理员连接确认流程。请保持原管理员会话打开，并从全新的 SSH 管理员连接执行 NoBrand 输出的 `nobrand ssh confirm-admin --token ...` 命令；确认完成前，统一卸载不会继续删除其他协议。

## 平台支持

| 类别 | 支持范围 |
|---|---|
| Linux 发行版 | Debian / Ubuntu、RHEL-compatible（当前矩阵以 Rocky Linux 9 为代表）、Alpine Linux |
| CPU 架构 | amd64 / arm64 |
| 服务管理器 | systemd / OpenRC |
| 基本权限与工具 | root、Bash、curl；安装器按所选功能补充平台依赖 |

当前平台参考范围为 Debian 12、Ubuntu 24.04、Rocky Linux 9 与 Alpine Linux 3.20。Multi-Ingress 不负责配置云厂商 NAT、IPLC/DNAT 映射、额外网卡地址或返回路由。使用 Mapped Profile、Strict Ingress、Preserve Source 或指定 Realm 出站接口前，应先确认底层网络已经正确配置。

## 安全与设计原则

- 状态、配置、凭据和私钥采用受限权限保存；备份同样视为敏感文件。
- 部署不会以关闭系统防火墙或清空整机 firewall 规则作为手段。
- Display Endpoint 与 Actual Listener 相互独立，修改展示地址不会隐式改变真实服务入口。
- Strict Ingress 只约束 NoBrand 管理服务的入口，不接管系统 egress、系统 `sshd` 或服务商网络。
- 配置与生命周期变更尽可能采用可验证、可回滚的事务式流程。
- 卸载只清理由 NoBrand 管理且能够确认归属的资源，保留外部服务与系统配置。
- 不应将生成的密码、private key、客户端配置或备份提交到公开仓库。

## 已知限制

- 合法的 NoBrand v3.0/v3.1 schema-v3 状态可以继续使用；缺少 Ingress 字段时按 Legacy Default Route 与 `permissive` 兼容读取，普通只读命令不会为此改写状态或重启服务。
- 旧 Mieru、旧管理 wrapper 与 NoBrand 1.x state 不会自动导入或迁移，需要先自行备份并清理后重新部署。
- Ingress Profile 只管理入口身份、端口策略、监听约束与展示默认值，不配置 Linux policy routing、默认 egress 或服务商映射。同一 transport 与数值端口不能跨 Profile 重复使用。
- Snell 只支持 v5 与 v4；v5 的 QUIC 公网暴露默认关闭。官方 QUIC Proxy Mode 的端到端兼容性尚未确认，Mihomo 的普通 `udp: true` 不代表该模式已兼容，sing-box 不支持该模式。
- Hysteria2 的普通 TCP/HTTPS 使用不受此项影响，但部分较大的 SOCKS5 UDP datagram 可能出现完整性或超时问题。
- Forward 不会分片、缩小或改写应用层 UDP datagram；可用大小取决于服务商、NAT、隧道和 Internet path。nftables 后端只接受 IPv4 literal Target；IPv6 或域名 Target 请使用 Realm。
- TUIC 只支持 v5，使用自签名 TLS 证书，客户端导出会相应启用证书跳过验证；当前没有确认的标准 TUIC v5 URI。
- VLESS + FinalMask/Sudoku 提供 Xray client JSON 与 `vless://` 分享链接；不声明未经项目支持的 Mihomo 或 sing-box 组合。
- SSH Tunnel 只提供 TCP forwarding。Tunnel 用户可以访问服务器本身可达的 TCP 目标；若需要目标访问控制，应使用主机或网络策略。
- REALITY 自动候选和自定义目标均依赖第三方 TLS 站点的持续兼容性；候选池中的 hostname 可能随外部站点变更而暂时不可用。

## 文档

- [CHANGELOG.md](CHANGELOG.md)：版本变化记录。
- [Multi-Ingress 与 Strict Ingress](docs/MULTI-INGRESS-3.2.md)：Profile、端口策略、Enforcement、迁移和兼容行为。
- [VLESS REALITY + Vision](docs/VLESS-REALITY-3.2.md)：服务端合同、导出、伪装目标与故障排查。
- [Mieru 功能与参数合同](docs/MIERU-PARITY-3.0.md)：Profile、用户、配额、限速与客户端配置。
- [Port Forward](docs/FORWARD-REFERENCE-3.1.md)：nftables / Realm 后端与高级参数。
- [TUIC v5](docs/TUIC-V5-3.1.md)：runtime、服务端字段和导出格式。
- [SSH Tunnel](docs/SSH-TUNNEL-3.1.md)：权限边界、key-only policy 与管理员确认流程。
- [协议支持范围](docs/PROTOCOL-SCOPE.md)：支持和明确不支持的协议、传输与迁移边界。
- [贡献指南](CONTRIBUTING.md)：源码、构建、测试和提交要求。

## License

NoBrand-OneClick 以 [GNU General Public License v3.0](LICENSE) 发布。项目引用或下载的第三方源码与 runtime 仍遵循各自许可证和使用条款，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
