# NoBrand-OneClick

NoBrand-OneClick 是一个面向 Linux 服务器的多协议部署与网络管理工具。当前工作树是 **3.2.0 release candidate / unreleased**：它在 3.1.0 clean architecture 上增加 Multi-Ingress、strict ingress enforcement 和独立的 VLESS REALITY + Vision 产品，同时继续使用一个安装器、一个正式管理命令和 ownership-aware schema-v3 状态模型。3.1.0 仍是不可变的当前正式发布。

- 作者：ike
- 当前正式版本：3.1.0
- 最新发布标签：`v3.1.0`
- 当前发布候选：3.2.0（未发布）
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
| VLESS REALITY | Xray-core 26.3.27 | TCP + REALITY + XTLS Vision | 3.2 release candidate；Public Recommended |
| VLESS/Sudoku | Xray-core | TCP | Plain VLESS + FinalMask/Sudoku |
| SSH Tunnel | 机器现有 OpenSSH `sshd` | SOCKS5 via `ssh -N -D` | key-only、无普通 shell |

Snell v1、v2、v3、v6 与 TUIC v1、v2、v3、v4 不受支持，也不存在隐藏安装开关。VLESS Encryption 明确关闭；本项目不会生成或保存 ML-KEM、xorpub、server ticket 或 VLESS Encryption keypair。VLESS REALITY 是 3.2 最后一个计划协议功能；完成后协议范围保持冻结：`PROTOCOL_FEATURE_FREEZE=true`。

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

以上是当前正式发布资产的输出；本仓库 3.2 release candidate 构建后输出 `NoBrand-OneClick 3.2.0`。不要把候选工作树当成已发布的 3.2 release。

协议入口：

```bash
nobrand mieru
nobrand snell
nobrand hy2
nobrand tuic
nobrand vless-reality
nobrand vless-sudoku
nobrand ssh
nobrand forward
nobrand ingress
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

默认 `stable` 会在每次安装或显式升级事务开始时读取官方 `enfein/mieru` release metadata，选择最高的严格 `vMAJOR.MINOR.PATCH`、`draft=false`、`prerelease=false` 版本；`latest` 只是相同语义的兼容别名。解析成功后，版本、tag、平台 asset、下载 URL、API SHA-256 与官方 checksum manifest 会在整个事务中固定，下载内容和已安装 `mita version` 必须与它们完全一致。`--mieru-version VER` 仍优先并切换为 `pinned` 精确版本。

本候选在 2026-09-01 合格的官方最新稳定版与 last-known-good 都是 `3.36.0`。只有 live release metadata 获取失败时，默认通道才会明确输出 `LATEST_RESOLUTION_FAILED` 和 `USING_LAST_KNOWN_GOOD=3.36.0` 后使用该回退；成功获取但 metadata/asset/digest 不合法时会 fail closed。NoBrand 不承诺未来每个 Mieru release 都自动兼容，而是在安装/升级时验证当前支持的 runtime contract，并在候选或应用失败时保留/恢复旧 managed runtime、用户、端口和凭据。普通 `status` 不联网，只显示已安装版本、已保存通道与合格回退版本。

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

## 3.2 Release Candidate：Ingress Profiles

Ingress Profile 把“客户端从哪里进入”与“Linux 默认从哪里出站”分开。Ingress 决定服务入口身份、自动端口策略和默认 Display Endpoint；egress 继续完全由现有 Linux routing 决定。创建或修改 Profile 不会配置 NIC 地址、default route、`ip rule`、policy routing、`rp_filter`、provider NAT 映射或 system sshd。

Profile 类型：

- `public`：所选本地 IPv4 本身可作为默认公开入口；未指定 Display Host 时默认使用该本地地址。
- `mapped`：本地接收地址与客户端看到的入口不同；必须显式提供 Display Host，NoBrand 不会根据 RFC1918 或接口名称猜测运营商映射。

端口策略：

- `derived-tail`：从 Profile 所选本地 IPv4 的最后一段 `N` 推导 `N×100` 保留基准和 `N×100+1` 到 `N×100+99` 自动池。例如文档地址 `192.0.2.110` 推导 `11000` 与 `11001-11099`。无效、特权或越界结果会被拒绝，不会随机回退。
- `custom-range`：显式设置任意合法自动池和保留端口列表。
- `manual-only`：不自动分配；创建节点或 Forward rule 时必须显式传入实际端口。

入口强制策略与端口策略相互独立：

- `permissive`：默认和 legacy-compatible 行为；managed listener 使用既有 wildcard 语义。
- `strict`：只允许从 Profile 的本地地址进入。Snell、HY2、VLESS/Sudoku、VLESS REALITY、TUIC 和 Realm 使用原生精确地址 bind；Mieru 使用 NoBrand-owned nftables fallback；nftables Forward 在 DNAT 前匹配目标地址。

缺少 `ingress_enforcement` 的合法 schema-v3 Profile 或 node 继续按 `permissive` 读取。Strict 始终使用 Profile local address，绝不使用 Display Host，也不配置 Linux route、`ip rule`、policy routing、`rp_filter` 或默认 egress。

示例只使用 RFC 文档地址：

```bash
sudo nobrand ingress add --name Example-Mapped --type mapped \
  --interface eth1 --address 192.0.2.110 --port-policy derived-tail \
  --reserve 11000 --advertise-host 203.0.113.50 \
  --enforcement strict -y

sudo nobrand ingress add --name Example-Public --type public \
  --interface eth0 --address 198.51.100.20 --port-policy manual-only \
  --enforcement permissive -y

sudo nobrand ingress set-default Example-Mapped
nobrand ingress list
nobrand ingress show Example-Mapped
nobrand ingress doctor
```

设置默认 Profile 后，新节点在没有显式选择时使用该 Profile；现有节点不会被重写。也可以逐次覆盖：

```bash
sudo nobrand tuic install --name mapped-tuic --user alice \
  --ingress-profile Example-Mapped -y
sudo nobrand snell install --name public-snell --version 5 --quic off \
  --ingress-profile Example-Public --port 24443 -y
```

改变被引用 Profile 的 enforcement，或在 strict 下改变 interface/address，是显式 runtime migration：有非 SSH owner 时必须使用 `--apply-existing`，所有 owner 验收后才提交；任一失败会恢复原 Profile JSON 并补偿恢复已迁移 owner。也可运行 `sudo nobrand ingress apply PROFILE` 按当前策略重新应用所有非 SSH owner。SSH Tunnel 继续复用 external system sshd，strict 对它是 `NOT_APPLICABLE_TO_SYSTEM_SSH`。

无论 enforcement 如何，不同 Profile 仍共享 host-global + transport-aware 端口 ownership；同 transport + 同数值 port 不允许跨 Profile 复用。完整 capability table、Mieru owned firewall、Forward strict 语义、兼容与生命周期顺序见 [docs/MULTI-INGRESS-3.2.md](docs/MULTI-INGRESS-3.2.md)。

## 3.2 Release Candidate：VLESS REALITY + Vision

VLESS REALITY 是独立于已发布 VLESS/Sudoku 的 named-instance 产品，固定且只支持 `VLESS + TCP + REALITY + xtls-rprx-vision`。每个 instance 独立拥有 UUID、X25519 keypair、16 位十六进制 short ID、target/serverName、public TCP listener、自动分配且仅监听 `127.0.0.1` 的 defender、service、firewall/Common Port ownership、Ingress Profile 与 Display metadata；不会把现有 Sudoku state/config 改造成 REALITY。

Public Profile 是推荐入口；mapped/dedicated Profile 会显示中性警告但仍允许安装。`manual-only` Profile 必须显式给出 Actual TCP port：

```bash
sudo nobrand vless-reality install --name public-reality \
  --ingress-profile Example-Public --port 32052 --advertise-auto -y

# host 与伪装目标端口可独立覆盖
sudo nobrand vless-reality install --name custom-reality \
  --target www.example.com --target-port 8443 \
  --ingress-profile Example-Public --port 32053 --advertise-auto -y

nobrand vless-reality show --name public-reality
nobrand vless-reality export --name public-reality
nobrand vless-reality doctor --name public-reality
```

REALITY 伪装 hostname 默认使用 `auto`：安装事务会把发布时通过 NoBrand 精确 REALITY 栈资格测试的候选池随机排序，按不重复顺序使用当前请求的 target port 做公网 DNS、TLS 1.3 与证书检查，选择首个可用 hostname。默认伪装 target port 是 443。自动选择后，state 会同时持久化 `camouflage_mode="auto"` 和实际 hostname；restart、status、nodes、show、export、Doctor、backup/restore 都复用该值，不会重新随机。

显式 `--target`、`--server-name` 或 `--sni`（同一既有参数合同）记录为 `camouflage_mode="custom"` 并严格使用用户值；验证失败会关闭事务，不会静默换成自动候选。hostname 与 target port 可分别覆盖；`auto` 配合非 443 port 时，每个候选必须在该实际 port 上通过检查，池耗尽则完整失败。这里的 443 只代表默认伪装 target port，不会自动成为公网 REALITY listener port。候选资格只说明发布时在测试栈中已知可用；第三方 TLS 站点可能变化，候选域名所有者不参与、运营、支持或认可 NoBrand/REALITY。

REALITY permissive public listener 使用 `0.0.0.0`；strict Profile 通过 Xray native bind 使用 Profile local IPv4，并要求 exact-address listener 验收。public `realitySettings.target` 始终指向该 instance 的 loopback defender，而 defender 使用 TLS-only sniffing、精确 `full:<serverName>` allow 和紧邻的 catch-all block；无 SNI、错误 SNI、HTTP、随机或畸形 TLS probe 不会被转发到 camouflage target。private-address、指定危险 TCP ports 与 BitTorrent block 位于 allow 之前。defender port 不进入 Common Port、Display Endpoint 或 firewall ownership，普通状态只显示 `Defender: Active|Inactive`。

Xray 仍固定为 26.3.27，并从同一个官方 SHA-256 验证 archive 私有安装 `xray`、`geoip.dat` 与 `geosite.dat`。服务端 `realitySettings` 固定包含 `minClientVer="0.0.0"`；该服务端门槛字段不会写入 Xray、Mihomo、sing-box 客户端导出或 URI。为避免 Xray 在没有 sniffed SNI 时保留 dokodemo 原始 hostname 而误中 allow，defender 的内部 dispatch 使用不可解析的 `nobrand.invalid` sentinel；只有精确 sniffed SNI rule 能进入带固定 `freedom.settings.redirect=<validated-target>:<port>` 的 `DIRECT` outbound。sentinel 从不作为客户端 hostname、公开 target 或 exporter 字段。标准 `vless://`、Xray 26.3.27 JSON、Mihomo 1.19.30 YAML 与 sing-box 1.13.20 JSON 仍从同一 authoritative state 生成且客户端 contract 不变。Mihomo 固定 `mode: rule`，Mihomo/sing-box 完整配置均没有 DIRECT member/fallback。完整字段、安全模型、Actual/Display 语义、target 验证与故障排查见 [docs/VLESS-REALITY-3.2.md](docs/VLESS-REALITY-3.2.md)。

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

## Hysteria2 已知限制（3.2 release candidate）

Normal HTTPS/TCP use tested PASS.

Some larger SOCKS5 UDP datagrams may experience integrity/time-out issues.

This is not classified as Dual-specific.

No upstream defect has been confirmed.

较大的 proxied UDP datagram 在本阶段保持 `KNOWN_LIMITATION / DEFERRED`；这不会触发 backend、Xray、MTU、framing、routing、sysctl 或 network-policy 变更。

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

sudo nobrand forward add --name strict-kernel --backend nftables --protocol BOTH \
  --ingress-profile Example-Mapped --port 11031 \
  --target 198.51.100.31 --target-port 443

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

它不会改 nft rule、Realm config、真实 listener、target、PID、enforcement 或端口。

### nftables backend

nftables 后端只接受 IPv4 literal target，不解析域名，也不声称支持 IPv6 forwarding。它生成并原子更新唯一的 NoBrand-owned `table ip nobrand_forward_v4`，其中包含 `prerouting`、`postrouting` 与 `forward` chains，以及带 `nobrand:<rule-id>:...` comment 的 DNAT、MASQUERADE 与 forwarding rules。Strict rule 的 DNAT path 额外要求 `ip daddr PROFILE_LOCAL_ADDRESS`，因此送到另一入口地址的 packet 不会匹配；permissive rule 保持 wildcard destination。更新和卸载只允许触碰带明确 NoBrand ownership marker 的这个表，绝不执行 whole-ruleset flush。

默认 Source Mode 是 MASQUERADE。Preserve Source 不做 SNAT，目标服务器必须把返回路径指回转发机，否则连接通常会失败：

```bash
sudo nobrand forward add --name preserve-example --backend nftables --protocol BOTH \
  --listen 0.0.0.0 --port 24444 --target 203.0.113.20 --target-port 443 \
  --source-mode preserve
```

只在至少一条 nftables 规则启用时才需要 `net.ipv4.ip_forward=1`。NoBrand 会记录原值、是否由自己改变及活动规则数，只写 `/etc/sysctl.d/90-nobrand-forward.conf`。最后一条规则移除时，仅在 fragment/state ownership 仍完整且 NoBrand 曾把原值 0 改为 1 的情况下恢复 0；原本为 1 的系统保持 1。外部同名 fragment 或不匹配状态会 fail closed。

### Realm backend

Realm 后端使用官方 `zhboner/realm` stable `v2.9.6` musl asset，并同时校验 GitHub Release digest、NoBrand 固定测试 digest、架构和二进制版本。runtime 只安装到 `/usr/local/lib/nobrand-oneclick/bin/realm`，不会覆盖 `/usr/bin/realm`、`/usr/local/bin/realm` 或外部 service/config。

所有启用的 Realm rules 生成一份 `/etc/nobrand-oneclick/forward/realm.toml`，由一个 `nobrand-realm` systemd/OpenRC daemon 承载。Permissive rule 使用 wildcard listener；strict rule 原生 bind Profile local address，并在提交前验证 exact TCP/UDP listener。普通默认是 raw、system DNS、无 Proxy Protocol、无指定 interface、无负载均衡。高级选项包括：

- outgoing `through`、outgoing interface、listen interface；
- TCP/UDP timeout；
- 分开的 Proxy Protocol send/accept 与 v1/v2；
- 官方 DNS mode/protocol/nameserver socket addresses；
- 官方 `listen_transport` / `remote_transport` strings；
- `extra_remotes`、`roundrobin` / `iphash` 与一一对应的 weights。

每个 extra remote 和 DNS nameserver 都必须是有效 IPv4/IPv6/domain 加端口；weights 数量必须等于 primary 加 extra remotes 数量。Realm domain target 会原样写入配置并由 Realm DNS 机制处理。切换到 nftables 时，domain/IPv6 target 必须由用户明确提供新的 IPv4 target，不会被一次 DNS 解析偷偷固定。

事务应用先结构校验，再用临时空闲 listener 启动短生命周期的官方 Realm candidate；旧 Realm 数据面在 candidate 通过前保持运行。生产服务重启后还必须通过 service、PID、TCP/UDP listener ownership 和 strict exact-address 验收，之后才提交 state。`nftables → Realm → nftables` 会保留 Profile、port、protocol、Display、Target 与 enforcement；失败会恢复原 backend、state、nft table、Realm runtime/config/service、sysctl 与 firewall ownership。

完整功能取舍、官方 asset digest 与 realm-xwPF 参考审计见 [docs/FORWARD-REFERENCE-3.1.md](docs/FORWARD-REFERENCE-3.1.md)。realm-xwPF 只作为设计参考；NoBrand 没有复制其源码、安装 `pf` command 或采用 `/etc/realm` state authority。

可用的最大 UDP application datagram 大小取决于 provider、NAT、tunnel 和 Internet path。NoBrand Forward 是透明 L4 转发，不会自动分片、缩小、clamp 或改写 application UDP datagram；因此受控 backend path 可以通过某个 payload size，而特定 external path 仍可能在数据报到达服务器接口之前丢弃它。这种 external path capability 与 Hysteria2 的 larger proxied SOCKS5 UDP 已知限制是两个独立观察。

## 统一端口层

端口 registry 以 `transport:port` 为键。TCP 与 UDP 同数值端口可以由不同协议共存；相同 transport 上的端口不能冲突。

3.2 release candidate 的显式 Ingress Profile 通过 `derived-tail`、`custom-range` 或 `manual-only` 决定自动端口。Profile 的保留端口同时约束手工与自动请求；显式端口在合法、空闲且非保留时可以位于当前自动池之外。不同 Profile 在 permissive 和 strict 下都共享 host-global ownership；strict 不开放同 transport + 同数值 port 的跨 Profile 复用。

没有配置默认 Profile、且创建节点时没有 `--ingress-profile` 的旧脚本继续使用内置 `legacy-default-route` adapter。它保留 3.1 的默认路由 IPv4 尾号语义：

```text
xx00       所有 transport 永久保留
xx01-xx99 自动分配池
```

legacy 手工指定与自动分配都会拒绝 `xx00`。统一 allocator 还会检查现有 listener、NoBrand state、Profile 保留列表与实际自动池，并在显式 Profile 的自动池耗尽时 fail closed，不会逃逸到随机端口。

## State、配置与 runtime

3.1 的唯一权威 state 仍是 schema v3：

```text
/var/lib/nobrand-oneclick/
├── state.json              # schema_version = 3, ownership = nobrand-v3
├── ingress.json            # optional 3.2 Ingress Profiles/default
├── ingress-firewall.json   # optional strict Mieru firewall authority
├── mieru/
├── snell/
├── hysteria2/
├── tuic/
├── vless-reality/
│   └── instances/<id>/state.json
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
├── ingress-firewall.nft
├── snell/
├── hysteria2/
├── tuic/
├── vless-reality/
│   └── instances/<id>/
│       ├── config.json
│       └── private.key
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

/usr/local/lib/nobrand-oneclick/xray-assets/
├── geoip.dat
└── geosite.dat
```

上游 Mieru runtime 的真实二进制仍名为 `mita`，NoBrand 通过明确路径调用它。它是协议 runtime，不是管理命令。3.0 不安装名为 `mita`、`mita-menu` 的管理 wrapper，也不提供第二套管理 parser。

secret state、REALITY server config/private key、TUIC server config/TLS key 与 SSH private key 使用 0600，state 和各协议 secret config 目录使用 0700。REALITY state 只保存 public key 和 private-key path；Xray 必需的 `privateKey` 仅存在于 root-only private key/config。为了让 `sshd` 在切换到目标用户后读取集中管理的公钥，`/etc/nobrand-oneclick` 与 `ssh-tunnel/` 使用 0711（可穿越、不可列目录），`authorized_keys/` 使用 0755，公钥文件使用 0644；其它协议 secret 目录仍为 0700。

## Clean-break 与旧状态

3.2 release candidate 可以直接使用合法的 NoBrand 3.0/3.1 schema-v3 state。没有 `ingress.json` 或 `ingress_profile_id` 的 3.1 state 通过内置 `legacy-default-route` adapter 保持原行为；普通 read-only 启动、`status`、`nodes` 和 Ingress list/Doctor 不会自动创建 Profile state、重写节点、旋转 credential、换 port、换 Display Endpoint 或重启 service。REALITY legacy state 缺少显式 `target_port` 时只读解释为 443，读取、状态、Doctor 与导出不会为此写回文件；已有自定义 host/port 不会被默认或迁移。它仍不迁移、导入或转换旧 Mieru 用户、NoBrand 1.x state 或旧管理 wrapper。检测到旧目录或不是明确 schema v3 的 NoBrand state 时会 fail closed：

```text
检测到旧版安装数据。
NoBrand-OneClick 3.2.0 不提供旧用户自动迁移。
请先备份并清理旧安装后重新部署。
```

检测过程不会读取、复制、删除或修改旧 state。`--help` 与 `--version` 不依赖 state，仍可用于确认版本和处理方式。

## 备份与恢复

```bash
nobrand backup create
nobrand backup list
nobrand backup restore /path/to/nobrand-backup.tar.gz
```

备份只包含 NoBrand schema v3 的 state/config，并带有项目、版本、schema 与 ownership manifest，归档权限固定为 0600。Ingress Profiles、默认 Profile、node/Forward association、Forward authoritative state、Realm runtime metadata、生成的 Realm/nftables artifacts 与 sysctl ownership metadata 都在这些 root 内。归档还包含 REALITY private key/UUID/short ID、TUIC UUID/password、TLS key 和 SSH private key，因此必须按 root secret 处理，不应上传到日志、工单或公开存储。恢复 Profile 只恢复 NoBrand application state，不写系统 NIC、route 或 provider mapping。存在 strict Mieru 时，恢复先应用 authoritative `inet nobrand_ingress` table，再启动其 wildcard runtime，避免短暂 permissive exposure。

恢复拒绝绝对路径、`..`、无效 JSON、旧 schema、非 NoBrand 归档，以及当前系统中没有本地 ownership marker 的同名 SSH 用户/group。TUIC 与 Realm runtime 按备份 metadata 的精确版本和官方 digest 重建；SSH Linux identity、authorized key 与 policy 重新验收；Forward nft table、Realm data plane 和 sysctl ownership 重新应用。任何后续 service/policy acceptance 失败都会同时回滚 state/config、TUIC/Realm runtime 与 service artifacts、Forward nft/sysctl、SSH 新建用户/group 和 sshd managed config。

## 统一卸载

```bash
sudo nobrand uninstall -y
```

统一卸载会删除 NoBrand 3 明确拥有的：

- Mieru 实例、配置、服务、调度器、firewall/tc、runtime/package/account（遵循安装前 ownership 标记）
- Snell v4/v5 实例、配置、服务与 runtime
- Hysteria2、VLESS REALITY 与 VLESS/Sudoku 服务、配置和共享 Xray runtime；REALITY template/OpenRC service 只有 ownership marker 匹配时才删除
- TUIC 实例、UDP firewall ownership、配置、证书、state、service 与 NoBrand-managed sing-box runtime
- SSH Tunnel managed Match policy、专用 Linux users/group、authorized keys、private keys 与模块 state
- Port Forward state、准确的 NoBrand Realm service/config/runtime、`nobrand_forward_v4` table 与安全拥有的 `ip_forward` fragment/state
- strict Mieru 的 counter-free `inet nobrand_ingress` table；卸载先停止 Mieru，再清理该 owned table
- Ingress Profile 与默认入口 state（不删除或修改 interface、IP、route、system sshd 或外部 provider mapping）
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

Mieru 默认解析官方 latest stable，`latest` 为兼容别名，`pinned` 保留精确版本覆盖；本候选合格 latest/last-known-good 为 3.36.0。Snell 使用 Surge 官方 runtime；Hysteria2、VLESS REALITY 与 VLESS/Sudoku 使用带私有官方 geo assets 的 NoBrand Xray-core；TUIC 使用官方 sing-box；SSH Tunnel 使用各平台已有 OpenSSH server；Forward 使用平台 nftables 和官方 Realm musl runtime。

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

测试覆盖 deterministic build、ShellCheck、Mieru golden parity、latest-stable metadata/asset/integrity/rollback、真实 3.36 fresh default 与 3.35→resolver-selected upgrade、官方客户端数据面、Profile/default/config/export、端口与 Endpoint、协议 golden config、Snell v5 QUIC、SSH/TUIC/Forward transaction 与 failure injection、统一 backup/restore/uninstall、敏感输出、仓库脱敏和真实 upstream runtime integration。Forward runtime 覆盖真实 nftables namespace TCP/UDP/BOTH、MASQUERADE、Preserve Source、外部 table 保留，官方 Realm TCP/UDP/BOTH/domain/multi-rule/advanced config，以及真实双向 backend switch 与失败回滚。无 Docker daemon 时，`platform-rootfs-smoke.sh` 使用官方容器 rootfs 在一次性 chroot 中执行 Debian、Ubuntu、Rocky、Alpine 的真实 OpenSSH 平台矩阵。

3.2 release candidate 还覆盖 public/mapped Profile、三种端口策略、missing-field permissive compatibility、strict native bind、Mieru owned-firewall fallback、Forward destination match、Profile-wide migration rollback、TCP/UDP cross-entry isolation、Display isolation、Doctor、backup/restore，以及四平台 Ingress parser/state。

## 安全说明

- 不把密码、私钥或 SSH 凭据提交到仓库。
- 不以关闭证书校验或固定未知 checksum 的方式“修复”下载。
- 不 flush 用户 firewall。
- 不接管预先存在的外部规则、软件包、系统账号或服务。
- Display Endpoint 与真实 listener 永远分离。
- Ingress Profile、Port Policy、Ingress Enforcement、Actual Listener、Display Endpoint 与 Forward Target 相互分离。
- Ingress 与 egress 永远分离；strict ingress 不管理 Linux 地址、route、rule、`rp_filter`、default egress 或 provider mapping。
- Mieru strict firewall 只管理 counter-free `inet nobrand_ingress`，input policy 保持 accept；不做 per-ingress accounting、quota 或 shaping。
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
