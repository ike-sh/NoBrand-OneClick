# NoBrand-OneClick

NoBrand-OneClick 是一个面向 Linux 服务器的多协议部署与网络管理工具。3.1.0 延续 3.0 的 clean architecture：一个安装器、一个正式管理命令、一套 ownership-aware schema-v3 状态模型，统一管理 Mieru、Snell、Hysteria2、TUIC v5、Plain VLESS + FinalMask/Sudoku、复用系统 OpenSSH 的 SSH Tunnel，以及 nftables/Realm 双后端 Port Forward。

- 作者：ike
- 当前正式版本：3.1.0
- 最新发布标签：`v3.1.0`
- 3.0 升级兼容基线：`v3.0.0`
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
| TUIC v5 | NoBrand 管理的官方 sing-box | UDP / QUIC / TLS / h3 | v5 only |
| VLESS/Sudoku | Xray-core | TCP | Plain VLESS + FinalMask/Sudoku |
| SSH Tunnel | 机器现有 OpenSSH `sshd` | SOCKS5 via `ssh -N -D` | key-only、无普通 shell |

Snell v1、v2、v3、v6 与 TUIC v1、v2、v3、v4 不受支持，也不存在隐藏安装开关。VLESS Encryption 明确关闭；本项目不会生成或保存 ML-KEM、xorpub、server ticket 或 VLESS Encryption keypair。3.1.0 完成后协议范围冻结：`PROTOCOL_FEATURE_FREEZE=true`。

Port Forward 是 Common Network Feature，不是代理协议：

| 后端 | 数据面 | 协议 | Target | 典型用途 |
|---|---|---|---|---|
| nftables | 内核 DNAT | TCP / UDP / BOTH | IPv4 literal | 最轻量的 IP 转发；默认 MASQUERADE，可选 Preserve Source |
| Realm | 官方 Realm userspace relay | TCP / UDP / BOTH | IPv4 / IPv6 / domain | 域名或高级转发；支持 DNS、through/interface、Proxy Protocol 与负载均衡 |

## 安装

正式安装始终使用 GitHub Latest Release 中的发布资产，不以 raw main 或固定旧标签作为默认入口。以下命令下载并安装当前正式发布的 3.1.0 资产：

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
NoBrand-OneClick 3.1.0
Author: ike
```

协议入口：

```bash
nobrand mieru
nobrand snell
nobrand hy2
nobrand tuic
nobrand vless-sudoku
nobrand ssh
nobrand forward
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

Snell v5 QUIC Proxy Mode 的官方 QUIC wire 端到端兼容性仍为 **NOT VERIFIED**；Mihomo 的普通 `udp: true` 不能作为 QUIC Proxy Mode 通过证据。3.1.0 的默认配置和最终真机验收状态均为 **OFF**。

## TUIC v5

TUIC 只支持 v5，服务端使用 NoBrand 下载、校验和独立管理的官方 sing-box。稳定通道固定到经过验收的 sing-box 1.13.20；amd64、arm64 及对应 musl 资产均有官方 SHA-256 约束。每个实例有独立 UDP listener、P-256 自签名证书、配置、service、state 和 firewall ownership；同一 NoBrand TUIC runtime 可由多个实例共享。

```bash
sudo nobrand tuic install --name primary --user alice --port 24443 \
  --advertise-host entry.example.com --advertise-port 443 -y
nobrand tuic user add --name primary --user bob
nobrand tuic user rotate --name primary --user alice
nobrand tuic user delete --name primary --user bob
nobrand tuic set-endpoint --name primary \
  --advertise-host entry.example.com --advertise-port 443
nobrand tuic status --name primary
nobrand tuic doctor --name primary
nobrand tuic export --name primary --user alice
```

每名用户拥有独立 UUID 与 password。普通 `status`、`doctor`、`nodes` 和菜单不输出这些凭据；`show`/`export` 是用户明确请求的 secret action。用户 add/delete/rotate 会先生成和校验完整候选配置，活动实例只有在 restart、UDP listener 和同进程 ownership 全部验收后才提交新 state；失败时恢复原配置与其它用户凭据。

客户端输出包括：

- Mihomo TUIC YAML
- sing-box TUIC JSON

项目没有确认到上游标准化的 TUIC v5 URI，因此不会自行发明 `tuic://`。Mihomo 与 sing-box exporter 都经过真实 parser、TCP 和 SOCKS5 UDP ASSOCIATE 数据面测试，UDP payload 覆盖 64、512、1200、1400 字节。详细上游字段、默认值和 runtime digest 见 [docs/TUIC-V5-3.1.md](docs/TUIC-V5-3.1.md)。

## SSH Tunnel

SSH Tunnel 的产品目标很简单：

- 复用机器现有 OpenSSH `sshd`，不安装第二个 SSH server；
- 创建独立的 key-only Tunnel account；
- 禁止普通 shell、命令、TTY、SFTP/SCP、X11、agent 与 TUN/TAP；
- 通过 `ssh -N -D` 为客户端提供本地 SOCKS5。

```bash
sudo nobrand ssh install --user alice \
  --advertise-host entry.example.com --advertise-port 443 -y
nobrand ssh show --user alice
nobrand ssh export --user alice
```

`show` 只显示名称、入口、用户名、认证方式、host-key fingerprint 与状态，不打印 private key。只有显式 `export` 才输出 private key/保存位置、`known_hosts` entry、OpenSSH config 和可直接使用的 SOCKS5 命令，例如：

```bash
ssh -N -D 127.0.0.1:1080 -i <PRIVATE_KEY> -p <PORT> <USER>@<SERVER>
```

NoBrand 不拥有 system sshd、SSH listener、public firewall、host keys 或管理员认证。服务端保持 `AllowTcpForwarding yes`，但产品 UI 与真机验收聚焦 `-D` SOCKS5。策略变更会校验候选并启动管理员 lockout watchdog；完整安全与恢复模型见 [docs/SSH-TUNNEL-3.1.md](docs/SSH-TUNNEL-3.1.md)。

## Port Forward

`nobrand forward` 管理一套统一规则 state；每条规则选择 `nftables` 或 `realm` 后端。两种后端都支持 TCP、UDP、BOTH、enable/disable、modify、delete、Display Endpoint、JSON export/import、Doctor 与事务式 backend switch。禁用规则仍保留端口 ownership，避免端口被另一模块静默复用。

基础示例：

```bash
sudo nobrand forward add --name web-kernel --backend nftables --protocol TCP \
  --listen 0.0.0.0 --port 24443 --target 203.0.113.10 --target-port 443

sudo nobrand forward add --name dns-relay --backend realm --protocol BOTH \
  --listen 0.0.0.0 --port 25353 --target upstream.example.com --target-port 53

nobrand forward list
nobrand forward show web-kernel
sudo nobrand forward disable web-kernel
sudo nobrand forward enable web-kernel
sudo nobrand forward switch-backend web-kernel --backend realm
nobrand forward doctor
nobrand forward export --file /root/forward.json
sudo nobrand forward import --file /root/forward.json
```

Display Endpoint 只改变用户看到的入口 metadata：

```bash
sudo nobrand forward set-endpoint web-kernel \
  --advertise-host entry.example.com --advertise-port 443
```

它不会改 nft rule、Realm config、真实 listener、target、PID 或端口。

### nftables backend

nftables 后端只接受 IPv4 literal target，不解析域名，也不声称支持 IPv6 forwarding。它生成并原子更新唯一的 NoBrand-owned `table ip nobrand_forward_v4`，其中包含 `prerouting`、`postrouting` 与 `forward` chains，以及带 `nobrand:<rule-id>:...` comment 的 DNAT、MASQUERADE 与 forwarding rules。更新和卸载只允许触碰带明确 NoBrand ownership marker 的这个表，绝不执行 whole-ruleset flush。

默认 Source Mode 是 MASQUERADE。Preserve Source 不做 SNAT，目标服务器必须把返回路径指回转发机，否则连接通常会失败：

```bash
sudo nobrand forward add --name preserve-example --backend nftables --protocol BOTH \
  --listen 0.0.0.0 --port 24444 --target 203.0.113.20 --target-port 443 \
  --source-mode preserve
```

只在至少一条 nftables 规则启用时才需要 `net.ipv4.ip_forward=1`。NoBrand 会记录原值、是否由自己改变及活动规则数，只写 `/etc/sysctl.d/90-nobrand-forward.conf`。最后一条规则移除时，仅在 fragment/state ownership 仍完整且 NoBrand 曾把原值 0 改为 1 的情况下恢复 0；原本为 1 的系统保持 1。外部同名 fragment 或不匹配状态会 fail closed。

### Realm backend

Realm 后端使用官方 `zhboner/realm` stable `v2.9.6` musl asset，并同时校验 GitHub Release digest、NoBrand 固定测试 digest、架构和二进制版本。runtime 只安装到 `/usr/local/lib/nobrand-oneclick/bin/realm`，不会覆盖 `/usr/bin/realm`、`/usr/local/bin/realm` 或外部 service/config。

所有启用的 Realm rules 生成一份 `/etc/nobrand-oneclick/forward/realm.toml`，由一个 `nobrand-realm` systemd/OpenRC daemon 承载。普通默认是 raw、system DNS、无 Proxy Protocol、无指定 interface、无负载均衡。高级选项包括：

- outgoing `through`、outgoing interface、listen interface；
- TCP/UDP timeout；
- 分开的 Proxy Protocol send/accept 与 v1/v2；
- 官方 DNS mode/protocol/nameserver socket addresses；
- 官方 `listen_transport` / `remote_transport` strings；
- `extra_remotes`、`roundrobin` / `iphash` 与一一对应的 weights。

每个 extra remote 和 DNS nameserver 都必须是有效 IPv4/IPv6/domain 加端口；weights 数量必须等于 primary 加 extra remotes 数量。Realm domain target 会原样写入配置并由 Realm DNS 机制处理。切换到 nftables 时，domain/IPv6 target 必须由用户明确提供新的 IPv4 target，不会被一次 DNS 解析偷偷固定。

事务应用先结构校验，再用临时空闲 listener 启动短生命周期的官方 Realm candidate；旧 Realm 数据面在 candidate 通过前保持运行。生产服务重启后还必须通过 service、PID 和 TCP/UDP listener ownership 验收，之后才提交 state。失败会恢复原 state、nft table、Realm runtime/config/service、sysctl 与 firewall ownership。

完整功能取舍、官方 asset digest 与 realm-xwPF 参考审计见 [docs/FORWARD-REFERENCE-3.1.md](docs/FORWARD-REFERENCE-3.1.md)。realm-xwPF 只作为设计参考；NoBrand 没有复制其源码、安装 `pf` command 或采用 `/etc/realm` state authority。

## 统一端口层

端口 registry 以 `transport:port` 为键。TCP 与 UDP 同数值端口可以由不同协议共存；相同 transport 上的端口不能冲突。

默认路由 IPv4 尾号 `xx` 对应：

```text
xx00       所有 transport 永久保留
xx01-xx99 自动分配池
```

手工指定与自动分配都会拒绝 `xx00`。allocator 还会检查现有 listener、NoBrand state、端口范围和 SSH 保留边界。

## State、配置与 runtime

3.1 的唯一权威 state 仍是 schema v3：

```text
/var/lib/nobrand-oneclick/
├── state.json              # schema_version = 3, ownership = nobrand-v3
├── mieru/
├── snell/
├── hysteria2/
├── tuic/
├── vless-sudoku/
├── ssh-tunnel/
├── forward/
│   ├── state.json
│   ├── realm-runtime.json
│   └── sysctl.json
├── backups/
├── locks/
└── firewall-owned.bindings
```

NoBrand 配置根：

```text
/etc/nobrand-oneclick/
├── snell/
├── hysteria2/
├── tuic/
├── vless-sudoku/
├── ssh-tunnel/
└── forward/
    ├── realm.toml
    └── nftables.nft
```

NoBrand 管理的 runtime：

```text
/usr/local/lib/nobrand-oneclick/bin/
├── mita
├── xray
├── sing-box
├── realm
└── snell/
```

上游 Mieru runtime 的真实二进制仍名为 `mita`，NoBrand 通过明确路径调用它。它是协议 runtime，不是管理命令。3.0 不安装名为 `mita`、`mita-menu` 的管理 wrapper，也不提供第二套管理 parser。

secret state、TUIC server config/TLS key 与 SSH private key 使用 0600，state 和各协议 secret config 目录使用 0700。为了让 `sshd` 在切换到目标用户后读取集中管理的公钥，`/etc/nobrand-oneclick` 与 `ssh-tunnel/` 使用 0711（可穿越、不可列目录），`authorized_keys/` 使用 0755，公钥文件使用 0644；其它协议 secret 目录仍为 0700。

## Clean-break 与旧状态

3.1 可以直接使用合法的 NoBrand 3.0 schema-v3 state；SSH Tunnel、TUIC 与 Forward 是 optional modules，不存在就保持空状态，升级不会旋转现有 credential、改变 Display Endpoint、port、listener 或 service。它仍不迁移、导入或转换旧 Mieru 用户、NoBrand 1.x state 或旧管理 wrapper。检测到旧目录或不是明确 schema v3 的 NoBrand state 时会 fail closed：

```text
检测到旧版安装数据。
NoBrand-OneClick 3.1.0 不提供旧用户自动迁移。
请先备份并清理旧安装后重新部署。
```

检测过程不会读取、复制、删除或修改旧 state。`--help` 与 `--version` 不依赖 state，仍可用于确认版本和处理方式。

## 备份与恢复

```bash
nobrand backup create
nobrand backup list
nobrand backup restore /path/to/nobrand-backup.tar.gz
```

备份只包含 NoBrand schema v3 的 state/config，并带有项目、版本、schema 与 ownership manifest，归档权限固定为 0600。Forward authoritative state、Realm runtime metadata、生成的 Realm/nftables artifacts 与 sysctl ownership metadata 都在这些 root 内。归档还包含 TUIC UUID/password、TLS key 和 SSH private key，因此必须按 root secret 处理，不应上传到日志、工单或公开存储。

恢复拒绝绝对路径、`..`、无效 JSON、旧 schema、非 NoBrand 归档，以及当前系统中没有本地 ownership marker 的同名 SSH 用户/group。TUIC 与 Realm runtime 按备份 metadata 的精确版本和官方 digest 重建；SSH Linux identity、authorized key 与 policy 重新验收；Forward nft table、Realm data plane 和 sysctl ownership 重新应用。任何后续 service/policy acceptance 失败都会同时回滚 state/config、TUIC/Realm runtime 与 service artifacts、Forward nft/sysctl、SSH 新建用户/group 和 sshd managed config。

## 统一卸载

```bash
sudo nobrand uninstall -y
```

统一卸载会删除 NoBrand 3 明确拥有的：

- Mieru 实例、配置、服务、调度器、firewall/tc、runtime/package/account（遵循安装前 ownership 标记）
- Snell v4/v5 实例、配置、服务与 runtime
- Hysteria2 与 VLESS/Sudoku 服务、配置和 Xray runtime
- TUIC 实例、UDP firewall ownership、配置、证书、state、service 与 NoBrand-managed sing-box runtime
- SSH Tunnel managed Match policy、专用 Linux users/group、authorized keys、private keys 与模块 state
- Port Forward state、准确的 NoBrand Realm service/config/runtime、`nobrand_forward_v4` table 与安全拥有的 `ip_forward` fragment/state
- NoBrand state、config、library roots
- `nb`、`nobrand`、`install-nobrand`（最后删除）

它不会删除系统 sshd、SSH listener/firewall/host keys/admin keys、外部 Xray/sing-box/Mihomo/Realm、外部 nftables tables、外部 sysctl fragments、无 ownership 的 Mieru/Snell、无关 systemd/OpenRC unit、无关 firewall 规则或基础网络配置。首次安装前已存在的 Mita package、账号、组和共享 runtime/config/service 路径会分别记录保护标记，Mieru 协议卸载不会按进程名批量终止或删除这些外部资源。

如果已安装 SSH Tunnel，`nobrand uninstall -y` 会先只移除 managed Match policy、reload sshd 并显示 watchdog token；其它协议此时保持不变。必须从全新管理员 SSH connection 确认后，才会删除 Tunnel users/group 并继续统一卸载。不要关闭原管理员会话，直到新会话确认成功。

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

Mieru 官方包支持 stable、latest 与 pinned 版本策略；Snell 使用 Surge 官方 runtime；Hysteria2 与 VLESS/Sudoku 使用 Xray-core；TUIC 使用官方 sing-box；SSH Tunnel 使用各平台已有 OpenSSH server；Forward 使用平台 nftables 和官方 Realm musl runtime。

## 本地验证

```bash
bash scripts/build.sh
bash scripts/build.sh --check
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/platform-smoke.sh
bash scripts/platform-rootfs-smoke.sh
bash scripts/docker-smoke.sh
```

测试覆盖 deterministic build、ShellCheck、Mieru golden parity、Profile/default/config/export、端口与 Endpoint、协议 golden config、Snell v5 QUIC、SSH/TUIC/Forward transaction 与 failure injection、统一 backup/restore/uninstall、敏感输出、仓库脱敏和真实 upstream runtime integration。Forward runtime 覆盖真实 nftables namespace TCP/UDP/BOTH、MASQUERADE、Preserve Source、外部 table 保留，官方 Realm TCP/UDP/BOTH/domain/multi-rule/advanced config，以及真实双向 backend switch 与失败回滚。无 Docker daemon 时，`platform-rootfs-smoke.sh` 使用官方容器 rootfs 在一次性 chroot 中执行 Debian、Ubuntu、Rocky、Alpine 的真实 OpenSSH 平台矩阵。

## 安全说明

- 不把密码、私钥或 SSH 凭据提交到仓库。
- 不以关闭证书校验或固定未知 checksum 的方式“修复”下载。
- 不 flush 用户 firewall。
- 不接管预先存在的外部规则、软件包、系统账号或服务。
- Display Endpoint 与真实 listener 永远分离。
- VLESS/Sudoku 始终为 Plain VLESS + FinalMask/Sudoku；`VLESS_ENCRYPTION_ENABLED=false`。
- TUIC 只支持 v5；不输出未经上游确认的 URI，不复用外部 sing-box。
- SSH Tunnel 允许服务器可达目标的 TCP forwarding；`GatewayPorts=no` 只限制 RemoteForward 监听面，不是目标访问控制。
- SSH policy 变更后必须保留旧管理员会话，并从全新会话确认 lockout watchdog。
- Forward 永不 flush whole nftables ruleset；同名外部 nft table、Realm service/runtime 或 sysctl fragment 会触发安全拒绝。
- nftables target 仅支持 IPv4 literal；`IPV6_FORWARD_SUPPORT=UNSUPPORTED`。Realm domain/IPv6 target 切换 nftables 必须显式输入 IPv4。

## 最终协议范围

3.1.0 的最终协议集合是 Mieru、Snell v5、Snell v4、Hysteria2、TUIC v5、Plain VLESS + FinalMask/Sudoku over TCP、SSH Tunnel over existing OpenSSH；最终 Network Feature 是 Port Forward（nftables / Realm）。完成 3.1.0 后：

```text
PROTOCOL_FEATURE_FREEZE=true
3.1.x = bugfix / security / compatibility
3.2.x = UI / exporter / Doctor / management improvements
```

完整支持与不支持清单见 [docs/PROTOCOL-SCOPE.md](docs/PROTOCOL-SCOPE.md)。
