# NoBrand-OneClick

NoBrand-OneClick 是一个面向 Linux 服务器的多协议部署与管理工具。3.0.0 是 clean-break 版本：一个安装器、一个正式管理命令、一套 ownership-aware 状态模型，统一管理 Mieru、Snell、Hysteria2 与 Plain VLESS + FinalMask/Sudoku。

- 作者：ike
- 当前版本：3.0.0
- 发布标签：`v3.0.0`
- 正式安装器：`install-nobrand.sh`
- 正式命令：`nobrand`
- 短别名：`nb`

## 协议支持

| 协议 | 服务端实现 | 传输 | 状态 |
|---|---|---:|---|
| Mieru | 官方 Mita runtime | TCP / UDP / BOTH | 完整支持 |
| Snell v5 | Surge 官方 `snell-server` | TCP；可选同端口 QUIC 公网暴露 | Stable / Recommended / Default |
| Snell v4 | Surge 官方 `snell-server` | TCP | Compatibility |
| Hysteria2 | Xray-core | UDP / TLS / h3 / Salamander | 完整支持 |
| VLESS/Sudoku | Xray-core | TCP | Plain VLESS + FinalMask/Sudoku |

Snell v1、v2、v3、v6 不受支持，也不存在隐藏安装开关。VLESS Encryption 明确关闭；本项目不会生成或保存 ML-KEM、xorpub、server ticket 或 VLESS Encryption keypair。

## 安装

正式安装始终使用 GitHub Latest Release 中的发布资产，不以 raw main 或固定旧标签作为默认入口：

```bash
curl -fsSLO https://github.com/ike-sh/NoBrand-OneClick/releases/latest/download/install-nobrand.sh
sudo bash install-nobrand.sh
```

也可以先做语法检查和哈希留档：

```bash
curl -fsSLO https://github.com/ike-sh/NoBrand-OneClick/releases/latest/download/install-nobrand.sh
bash -n install-nobrand.sh
sha256sum install-nobrand.sh
sudo bash install-nobrand.sh
```

安装完成后：

```text
/usr/local/bin/install-nobrand
/usr/local/bin/nobrand -> /usr/local/bin/install-nobrand
/usr/local/bin/nb -> /usr/local/bin/nobrand
```

`nb` 没有独立 parser、state 或业务逻辑。

## 快速使用

```bash
nobrand
nobrand --help
nobrand --version
nobrand status
nobrand nodes
nobrand doctor
nobrand backup create
nobrand network
```

`nobrand --version` 与 `nb --version` 均输出：

```text
NoBrand-OneClick 3.0.0
Author: ike
```

协议入口：

```bash
nobrand mieru
nobrand snell
nobrand hy2
nobrand vless-sudoku
```

## Mieru 完整能力

3.0 保留成熟 Mieru 管理面的用户功能、默认值、参数语义、配置输出和 exporter。统一入口只是把公开命令收敛为 `nobrand mieru ...`，不会把 Mieru 简化成单用户协议。

主要动作：

```bash
nobrand mieru install
nobrand mieru reconfigure
nobrand mieru upgrade
nobrand mieru uninstall
nobrand mieru start
nobrand mieru stop
nobrand mieru restart
nobrand mieru status
nobrand mieru doctor
nobrand mieru perf
nobrand mieru show
```

用户与实例：

```bash
nobrand mieru users
nobrand mieru user-add --user alice --password 'replace-me'
nobrand mieru user-show alice
nobrand mieru user-del alice
nobrand mieru user-enable alice
nobrand mieru user-disable alice
nobrand mieru user-set-endpoint --user alice --advertise-host entry.example.com
nobrand mieru user-set-quota --user alice --quota-mb 102400 --quota-mode calendar
nobrand mieru user-set-expire --user alice --expire +30d
nobrand mieru user-set-rate --user alice --bandwidth 100
nobrand mieru user-usage
nobrand mieru user-export-clients
nobrand mieru user-backup
nobrand mieru user-restore /path/to/backup.json
```

每个启用用户拥有稳定的 `instance_id`、独立 Mita 实例、独占真实 listener、独立 metrics 与可选 tc 限速。配额、到期、calendar reset、scheduler、firewall 与 tc 都按 NoBrand ownership 记录和回滚。交互菜单的“性能与网络”同时可达 Profile、MTU、Multiplexing、Handshake、Traffic Pattern、Low Entropy、BBR/FQ、tc 状态/恢复与 Mieru 版本通道。

### Mieru 参数与默认值

| 参数 | 值 / 语义 | 默认 |
|---|---|---|
| Profile | IPLC Performance / Balanced / Stealth / Custom | Balanced |
| Transport | TCP / UDP / BOTH | TCP |
| MTU | safe / auto / 1280–1500 | safe = 1400 |
| Multiplexing | off / low / middle / high | off |
| Handshake | no-wait / standard | no-wait |
| Traffic Pattern | off / conservative / aggressive | conservative |
| Low Entropy | off / 56 / 48 / 40 / 32 | off |
| Version channel | stable / latest / pinned exact version | stable |
| Client RPC | official client RPC port | 8964 |
| SOCKS5 | official client SOCKS port | 1080 |
| HTTP | official client HTTP port | 8080 |

Profile 会一次性确定完整真实参数；Custom 保留用户选择的具体值。项目不会自行“优化”成熟默认值。完整对等清单见 [docs/MIERU-PARITY-3.0.md](docs/MIERU-PARITY-3.0.md)。

### Mieru 输出

每个用户可生成：

- `mierus://` 分享链接
- 官方 Mieru client JSON
- Mihomo YAML
- 人类可读连接摘要
- 批量客户端导出目录

展示 Endpoint 只影响节点与客户端产物，不会修改服务端配置、listener、PID、service、firewall、tc 或 quota metrics。

## Display Endpoint 与真实 Endpoint

NoBrand 严格分离两类地址：

```text
REAL ENDPOINT     = 服务端监听、服务健康、真实防火墙 ownership
DISPLAY ENDPOINT  = 分享链接、客户端 JSON/YAML、nobrand nodes
```

支持：

- 自动探测
- 仅修改展示 host（沿用当前有效 port）
- 仅修改展示 port（沿用当前有效 host）
- 同时修改 host 与 port
- 恢复自动
- IPv4、IPv6、域名

停止服务后，持久化节点仍会出现在 `nobrand nodes`，状态显示为 Stopped；凭据不会从进程或 listener 反推。

## Snell v5 QUIC

Snell v5 默认 QUIC 公网暴露为 OFF。

| 模式 | TCP ownership | UDP public ownership | state |
|---|---:|---:|---|
| OFF | ON | OFF | `quic_proxy_enabled=false`, `managed_udp=false` |
| ON | ON | ON（同数值端口） | `quic_proxy_enabled=true`, `managed_udp=true` |

这个开关管理 UDP 公网暴露、firewall ownership、state 与 UI。它不会向官方 Snell 配置发明不存在的 `quic=true` 参数。

## 统一端口层

端口 registry 以 `transport:port` 为键。TCP 与 UDP 同数值端口可以由不同协议共存；相同 transport 上的端口不能冲突。

默认路由 IPv4 尾号 `xx` 对应：

```text
xx00       所有 transport 永久保留
xx01-xx99 自动分配池
```

手工指定与自动分配都会拒绝 `xx00`。allocator 还会检查现有 listener、NoBrand state、端口范围和 SSH 保留边界。

## State、配置与 runtime

3.0 的唯一权威 state：

```text
/var/lib/nobrand-oneclick/
├── state.json              # schema_version = 3, ownership = nobrand-v3
├── mieru/
├── snell/
├── hysteria2/
├── vless-sudoku/
├── backups/
├── locks/
└── firewall-owned.bindings
```

NoBrand 配置根：

```text
/etc/nobrand-oneclick/
├── snell/
├── hysteria2/
└── vless-sudoku/
```

NoBrand 管理的 runtime：

```text
/usr/local/lib/nobrand-oneclick/bin/
├── mita
├── xray
└── snell/
```

上游 Mieru runtime 的真实二进制仍名为 `mita`，NoBrand 通过明确路径调用它。它是协议 runtime，不是管理命令。3.0 不安装名为 `mita`、`mita-menu` 的管理 wrapper，也不提供第二套管理 parser。

目录默认 root-only：secret state 使用 0600，state/config ownership 目录使用 0700。

## Clean-break 与旧状态

3.0 不迁移、导入或转换旧 Mieru 用户、旧 NoBrand state 或旧管理 wrapper。检测到旧目录或不是明确 schema v3 的 NoBrand state 时会 fail closed：

```text
检测到旧版安装数据。
NoBrand-OneClick 3.0.0 不提供旧用户自动迁移。
请先备份并清理旧安装后重新部署。
```

检测过程不会读取、复制、删除或修改旧 state。`--help` 与 `--version` 不依赖 state，仍可用于确认版本和处理方式。

## 备份与恢复

```bash
nobrand backup create
nobrand backup list
nobrand backup restore /path/to/nobrand-backup.tar.gz
```

备份只包含 NoBrand schema v3 的 state/config，并带有项目、版本、schema 与 ownership manifest。恢复拒绝绝对路径、`..`、无效 JSON、旧 schema 和非 NoBrand 归档。

## 统一卸载

```bash
sudo nobrand uninstall -y
```

统一卸载会删除 NoBrand 3 明确拥有的：

- Mieru 实例、配置、服务、调度器、firewall/tc、runtime/package/account（遵循安装前 ownership 标记）
- Snell v4/v5 实例、配置、服务与 runtime
- Hysteria2 与 VLESS/Sudoku 服务、配置和 Xray runtime
- NoBrand state、config、library roots
- `nb`、`nobrand`、`install-nobrand`（最后删除）

它不会删除外部 Xray、sing-box、Mihomo、无 ownership 的 Mieru、无 ownership 的 Snell、无关 systemd/OpenRC unit、无关 firewall 规则、SSH 或基础网络配置。首次安装前已存在的 Mita package、账号、组和共享 runtime/config/service 路径会分别记录保护标记，Mieru 协议卸载不会按进程名批量终止或删除这些外部资源。

只卸载 Mieru 协议而保留管理器和其它协议：

```bash
sudo nobrand mieru uninstall
```

## 支持平台

- Debian / Ubuntu
- RHEL / Rocky / Alma 系
- Alpine
- amd64 / arm64
- systemd / OpenRC

Mieru 官方包支持 stable、latest 与 pinned 版本策略；Snell 使用 Surge 官方 runtime；Hysteria2 与 VLESS/Sudoku 使用 Xray-core。

## 本地验证

```bash
bash scripts/build.sh
bash scripts/build.sh --check
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/platform-smoke.sh
bash scripts/docker-smoke.sh
```

测试覆盖 deterministic build、ShellCheck、Mieru golden parity、Profile/default/config/export、端口与 Endpoint、协议 golden config、Snell v5 QUIC、rollback、backup boundary、统一卸载 ownership、菜单路由和真实 upstream runtime integration。

## 安全说明

- 不把密码、私钥或 SSH 凭据提交到仓库。
- 不以关闭证书校验或固定未知 checksum 的方式“修复”下载。
- 不 flush 用户 firewall。
- 不接管预先存在的外部规则、软件包、系统账号或服务。
- Display Endpoint 与真实 listener 永远分离。
- VLESS/Sudoku 始终为 Plain VLESS + FinalMask/Sudoku；`VLESS_ENCRYPTION_ENABLED=false`。
