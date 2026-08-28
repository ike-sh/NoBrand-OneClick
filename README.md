# NoBrand-OneClick

作者：**ike**

**Current release: 1.3.0**

NoBrand-OneClick 是面向 IPLC、专线、中转、特殊 QoS 以及特殊 TCP/UDP 网络环境的小众协议一键部署与管理工具箱。它不是通用代理面板；v1.3 只管理：

- Mieru
- Snell v4 / v5
- Hysteria2（Xray-core backend）
- Plain VLESS + FinalMask + Sudoku（TCP，Xray-core backend）

VLESS Sudoku 明确是 plain VLESS：`VLESS Encryption: NOT USED`。项目不会调用 Encryption key generator，不生成 encryption/decryption key pair，也不加入 REALITY、Vision、XHTTP、FullStack 或其它 VLESS 模式。VMess、Trojan、Shadowsocks、TUIC、Naive、WireGuard 等其它协议同样不在范围内。

## 协议与状态

| 协议 | 状态 | Server runtime | 传输/备注 |
|---|---|---|---|
| Mieru | Supported | 官方 `mita` | 保留 isolated-v2、多用户、TCP/UDP/BOTH、quota、tc 与导出语义 |
| Snell v5 | Stable / Recommended / Default | Surge 官方 `snell-server` | 默认 TCP ownership；可显式开放同号 UDP 作为 QUIC Proxy Mode server exposure |
| Snell v4 | Compatibility | Surge 官方 `snell-server` | TCP listener |
| Hysteria2 | Supported | NoBrand 独立管理的官方 Xray-core | UDP；保持 Xray-OneClick Hysteria2 v2 + TLS + Salamander 语义 |
| VLESS/Sudoku | Supported | 与 HY2 共用 NoBrand 管理的官方 Xray-core | Plain VLESS；TCP；`security=none`；FinalMask Sudoku；不使用 VLESS Encryption |

Snell v1、v2、v3、v6 明确不受支持，也没有隐藏兼容开关。

Snell v6 已在 1.3.0 删除。最终一次强制公网资格测试使用 NoBrand exporter、官方 sing-box 1.14.0-rc.1 和 `211.136.162.185` 公网入口，只得到 3/20 HTTPS，download/upload 均失败；它没有被 localhost、guest 或 private-path 结果“救回”。升级时一次性 migration 只清理身份完全匹配的历史 v6 service/state/config/TCP ownership 和独立 runtime，identity mismatch 会 fail closed。

## 架构

```text
NoBrand Common Core
├── OS / arch / download / atomic write / lock / rollback
├── transport-aware port registry       tcp:PORT / udp:PORT
├── Real Endpoint / Display Endpoint
├── firewall ownership / service adapters
├── unified nodes / status / doctor / backup / CLI / menu
│
├── Mieru adapter     → 原 /var/lib/mita-oneclick 与 /etc/mita
├── Snell engine      → 多实例 state + 官方 per-major runtime
├── Hysteria2 engine  → 独立 config/state/service ┐
└── VLESS Sudoku      → 独立 config/state/service ┴→ 共用 NoBrand Xray binary
```

`src/` 是开发源码真源。根目录和 `dist/` 中的单文件安装器都由 `scripts/build.sh` 确定性生成；不要直接长期维护生成文件。

## 支持系统与架构

| 系统 | amd64 | arm64 | 说明 |
|---|---:|---:|---|
| Debian / Ubuntu | ✓ | ✓ | Mieru、Snell、HY2、VLESS Sudoku；Snell arm64 依赖官方 aarch64 asset |
| RHEL / CentOS / Rocky | ✓ | ✓ | Mieru、Snell、HY2、VLESS Sudoku |
| Alpine Linux | ✓ | ✓ | Mieru、Snell v4/v5、HY2、VLESS Sudoku |

自动化矩阵覆盖 Debian 12、Ubuntu 24.04、Rocky 9、Alpine 3.20。arm64 会验证官方 asset mapping；仍建议在目标硬件执行 `nobrand doctor`。

## 安装与入口

Debian / Ubuntu / Rocky 等：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | sudo bash
```

Alpine：

```bash
apk add --no-cache bash curl
curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | bash
```

本地开发树：

```bash
bash scripts/build.sh
sudo bash install-nobrand.sh
```

统一入口：`install-nobrand`、`nobrand`、`nb`。Mieru compatibility 入口 `install-mita`、`mita` 继续保留。前者无参数进入统一菜单，后者无参数仍进入 Mieru 子菜单。

## 常用 CLI

```bash
nobrand
nobrand --version
nobrand nodes [--protocol mieru|snell|hy2|vless-sudoku]
nobrand status
nobrand doctor
nobrand backup create [FILE]
nobrand backup list
nobrand backup restore FILE
nobrand uninstall [-y]          # 删除 NoBrand Snell/HY2/VLESS/Common；保留 Mieru
```

### Mieru

```bash
nobrand mieru users
nobrand mieru doctor
nobrand mieru user-add --user alice --password 'secret'
nobrand mieru user-set-endpoint --user alice \
  --advertise-host entry.example.com --advertise-port 443
```

原 `install-mita` / `mita` CLI 保持可用。Mieru 的 isolated-v2、多用户、独立 instance ID、quota、expire、用户扫描、tc、备份、客户端 JSON、`mierus://`、Mihomo、Profile、MTU、Multiplexing、Handshake、Traffic Pattern、Low Entropy、BBR/FQ、Doctor、systemd/OpenRC 与 firewall ownership 均保留。

Mieru 分享链接中的 `profile=default` 是上游 Mieru 客户端的 `profileName`，不是管理 UI 的 `iplc|balanced|stealth|custom` Profile。

### Snell

```bash
# v5 默认 / 推荐
nobrand snell install --name alice --version 5 \
  --quic off --advertise-host entry.example.com --advertise-port 443 -y
nobrand snell install --name quic-opt-in --version 5 \
  --quic on --advertise-host entry.example.com --advertise-port 443 -y
nobrand snell install --name compatibility --version 4 --advertise-auto -y

nobrand snell show [--name NAME]
nobrand snell status|start|stop|restart --name NAME
nobrand snell set-quic --name NAME --quic on|off -y
nobrand snell set-endpoint --name NAME \
  --advertise-host 211.136.1.2 --advertise-port 50021 -y
nobrand snell set-endpoint --name NAME --advertise-auto -y
nobrand snell upgrade --version 4|5
nobrand snell doctor
nobrand snell remove --name NAME
```

每个节点有独立 stable random ID、名称、PSK、TCP listener、Display Endpoint、state、config 与 service instance。客户端输出：

- v4：Surge、Mihomo、sing-box `version: 4`
- v5：Surge `version: 5`、Mihomo `version: 5`、sing-box `version: 4`

v5 的 sing-box `version: 4` 是当前上游对 v5 server 的非 QUIC wire-compatible 表达，不是把 server 降级。官方 v5 runtime 会由同一个 `snell-server` 进程同时 bind TCP/UDP，且没有可供 NoBrand 写入的 `quic=true` server config；因此 NoBrand 不发明配置字段，也不重写 server config。

- `--quic off`（默认）：canonical transport 与 firewall ownership 只有 TCP；同进程本地 UDP socket 可作为 INFO 存在，但 NoBrand 不拥有/开放该 UDP 入口。
- `--quic on`：在 state 中原子记录 `quic_proxy_enabled=true`、`managed_udp=true`，开放同号 TCP/UDP，并验收两个 listener 都属于同一官方进程。
- ON/OFF 只改变 state/firewall ownership，不重写 server config、不重启 service、不轮换 PSK。Display Endpoint 修改仍与 listener/firewall 严格隔离。
- Snell ordinary UDP relay 是 UDP over TCP；官方 v5 QUIC Proxy Mode 是 UDP over UDP。Mihomo 的普通 `udp: true` 不等同于官方 QUIC wire。

## 客户端兼容性（2026-08-28 实测）

| Protocol / mode | Mihomo 1.19.30 | sing-box 1.14.0-rc.1 | Reference |
|---|---|---|---|
| Mieru | Supported / Tested | `CLIENT_UNSUPPORTED` | Mieru 3.35.0: Tested |
| Snell v4 | Supported / Tested | Supported / Tested | — |
| Snell v5, QUIC OFF | Supported / Tested | Supported / Tested as v4-compatible wire | — |
| Snell v5 official QUIC wire | `NOT VERIFIED` | `CLIENT_UNSUPPORTED` | Surge-compatible client required |
| Hysteria2 | Supported / Tested | Supported / Tested | — |
| VLESS/FinalMask/Sudoku | `CLIENT_UNSUPPORTED` | `CLIENT_UNSUPPORTED` | Xray 26.3.27: Tested |

QUIC ON 时 Mihomo/sing-box 的普通 Snell 路径仍是 TCP-compatible path；即使该路径连通，也不能写成“QUIC Proxy E2E PASS”。NoBrand 不为 unsupported 组合生成近似、降级或假配置。

### Hysteria2

```bash
nobrand hy2 install --sni www.microsoft.com \
  --advertise-host entry.example.com --advertise-port 443 -y
nobrand hy2 show
nobrand hy2 status|start|stop|restart
nobrand hy2 set-endpoint \
  --advertise-host 211.136.1.2 --advertise-port 55001 -y
nobrand hy2 set-endpoint --advertise-auto -y
nobrand hy2 upgrade
nobrand hy2 doctor
nobrand hy2 remove
```

HY2 继续使用 Xray-core inbound，而不是 hysteria 官方 server、sing-box 或 Mihomo。核心保持：

```text
protocol = hysteria
settings.version = 2
streamSettings.network = hysteria
streamSettings.security = tls
tlsSettings.alpn = h3
hysteriaSettings.version = 2
finalmask.udp[0] = salamander
```

认证和证书保持 Xray-OneClick 原语义：16-byte random hex auth、16-byte random hex Salamander password、ECDSA P-256 (`prime256v1`)、自签 3650 天、`CN = SNI`、key `0600`、cert `0644`。URI 继续包含 `sni`、`alpn=h3`、`insecure=1`、`obfs=salamander` 与 `obfs-password`。

### Plain VLESS + FinalMask + Sudoku（TCP）

```bash
nobrand vless-sudoku install \
  --advertise-host entry.example.com --advertise-port 443 -y
nobrand vless-sudoku show
nobrand vless-sudoku status|start|stop|restart
nobrand vless-sudoku set-endpoint \
  --advertise-host entry.example.com --advertise-port 8443 -y
nobrand vless-sudoku set-endpoint --advertise-auto -y
nobrand vless-sudoku doctor
nobrand vless-sudoku smoke
nobrand vless-sudoku upgrade
nobrand vless-sudoku remove

# 同一 canonical backend 的短别名
nobrand sudoku show
```

服务端核心语义固定为：

```text
protocol = vless
settings.decryption = none
streamSettings.network = tcp
streamSettings.security = none
streamSettings.finalmask.tcp[0].type = sudoku
settings.password = 16-byte random hex
ascii = prefer_ascii
paddingMin = 0
paddingMax = 3
```

客户端 `users[0].encryption = none` 与服务端 `decryption = none` 是当前 Xray-core 的 plain VLESS 合法语义，不表示启用 VLESS Encryption。NoBrand 不调用 `xray vlessenc`，不生成 ML-KEM/xorpub/native Encryption material，不保存 encryption/decryption secret、method、RTT 或 ticket。

`show` 输出 VLESS URL、完整手工参数与可直接用于兼容 Xray-core 的 client JSON。URL 和 client JSON 都使用 Display Endpoint，server config 永远使用 Real Endpoint。FinalMask/Sudoku 是较新的 Xray 扩展；客户端必须使用实际支持该结构的 Xray-core。NoBrand 不生成未经验证的 Mihomo 或 sing-box 配置。

HY2 与 VLESS 有独立 config、state、service 和 Xray process，但共享 `/usr/local/lib/nobrand-oneclick/bin/xray`。执行任一协议的 runtime upgrade 时，NoBrand 会用新 binary 校验两个现存配置，重启并验收两个此前 active 的服务；任一 listener 失败则同时恢复旧 binary 与两个 state。

## 统一端口分配

自动端口沿用 Mieru 尾号算法：

```text
默认路由出口 IPv4: 172.16.1.36
末位:               36
保留基数:           3600
自动候选:           3601-3699
遍历:               段内随机起点 + 环形扫描
```

优先读取默认路由出口，避免 Docker bridge/第二网卡抢占。尾号 `0` / `255`、段落入特权端口、无可靠 IPv4 或段耗尽时，回退到 `1025-65535` 随机端口。

Common Port 还会把当前默认路由 IPv4 尾号对应端口块的 `xx00` 视为保留基数，永不分配给代理。例如尾号 36 的自动候选是 3601-3699，而 3600 即使在 guest `ss` 中看起来空闲也会报告 `common:tail-base:<guest-ip>` 冲突。这用于保护 IPLC/NAT 场景中只存在于外层 DNAT、guest 无法观察到的 SSH/管理入口；规则由本机默认路由地址推导，不硬编码任何实验室 IP 或端口。

占用按 transport 分离：Snell TCP/3611 或 VLESS TCP/3611 可与 HY2 UDP/3611 同数字共存；Snell 与 VLESS 都是 TCP，因此不能占用同一个 TCP key。两个 TCP/3611 或两个 UDP/3611 都冲突。检查包含 NoBrand state、Mieru state、`ss`、`netstat`、bind probe，并在提交前二次验收。手工端口通常允许 `1-65535`，超出推荐段只 warning；唯一的 Common Port 例外是由默认路由 IPv4 尾号推导的保留基数 `xx00`，TCP 与 UDP 都会明确拒绝，即使 guest 内看不到 listener。

## Real Endpoint 与 Display Endpoint

```text
REAL ENDPOINT
  listen_host / listen_port / transport
  用于 server config、listener、service、firewall、tc、健康检查

DISPLAY ENDPOINT
  advertise_host / advertise_port
  只用于链接、客户端配置、节点视图、摘要
```

IPLC / NAT 示例：

```text
服务器真实监听: 0.0.0.0:3621/TCP
IPLC 公网入口:  211.136.x.x:50021/TCP
NoBrand config/firewall: TCP 3621
客户端节点:     211.136.x.x:50021
```

修改 Display Endpoint **不会**修改 server config、listener、systemd/OpenRC、firewall、tc、quota，也不会重启服务。NoBrand **不会自动创建 DNAT、IPLC 或四层转发**；前置入口到真实 listener 的映射必须另行配置。

非交互 `-y` 必须显式给完整 `--advertise-host HOST --advertise-port PORT`，或明确 `--advertise-auto`。host 支持 IPv4、IPv6、域名。相同 transport 的相同 Display Endpoint 会被拒绝；TCP 与 UDP 相同 host/port 可并存。

## 文件、服务与隔离

```text
/var/lib/nobrand-oneclick/
  state.json
  firewall-owned.bindings
  snell/instances/<id>.json
  hysteria2/state.json
  vless-sudoku/state.json
  vless-sudoku/client.json
  backups/

/etc/nobrand-oneclick/
  snell/instances/<id>.conf
  hysteria2/config.json
  hysteria2/hysteria2-cert.pem
  hysteria2/hysteria2-key.pem
  vless-sudoku/config.json

/usr/local/lib/nobrand-oneclick/
  snell-run
  bin/xray
  bin/snell/snell-v4|snell-v5
  bin/snell/snell-v*.runtime.json
```

systemd：`nobrand-snell@<id>.service`、`nobrand-hysteria2.service`、`nobrand-vless-sudoku.service`。OpenRC：`nobrand-snell-<id>`、`nobrand-hysteria2`、`nobrand-vless-sudoku`。

Mieru 权威路径继续是 `/var/lib/mita-oneclick` 与 `/etc/mita`，不迁移 state。HY2/VLESS 不覆盖 `/usr/local/bin/xray`、`/etc/xray/config.json`、`xray.service`、`/usr/local/bin/ike`，也不自动迁移 Xray-OneClick 配置。单独删除 VLESS 不删除共享 binary 或 HY2；NoBrand 全局卸载才清理自身 runtime namespace。

## Backup、Doctor 与安全

`nobrand backup` 只保存 NoBrand registry/firewall ownership、Snell state/config、HY2 state/config/cert/key，以及 VLESS Sudoku state/config/client JSON。备份为 `0600`，不包含 `/etc/xray` 或 Mieru backup。恢复会检查 tar 路径穿越、manifest、JSON，并拒绝空路径、`/`、`/etc`、`/var`、`/usr`、`/usr/local`、含 `..` 或非 NoBrand namespace 的清空目标。

`nobrand status` 只有在 service active 且 listener 存在时才计为 Running。`nobrand nodes` 保留 Stopped 节点。`nobrand doctor` 检查 Common、原 Mieru doctor、Snell runtime/config/state/service/TCP/firewall/endpoint、HY2 Xray config/P-256/CN/permissions/service/UDP/firewall/URI，以及 VLESS plain semantics、FinalMask Sudoku、Xray `run -test`、client JSON、TCP listener、firewall、Display Endpoint、URL 与 Encryption absence；默认不输出 secret。

- 下载只用 HTTPS，不使用 `--no-check-certificate`。
- Xray 只接受 XTLS 官方 GitHub release；API 提供 SHA-256 digest 时验证。
- Snell 只接受 `dl.nssurge.com` 官方 asset；验证 ZIP、ELF、major，并启动 localhost 临时实例。
- binary/config/state 原子替换并保留 rollback；失败不输出“完成”。
- 尾号端口易于专线运维但也较易被推测；公网仍应使用安全组/ACL。

## 开发与测试

```bash
bash scripts/build.sh
bash scripts/build.sh --check
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
```

测试包含 syntax、warning 级 ShellCheck、可复现构建、端口/Endpoint/HY2/Snell/VLESS/nodes/backup/rollback/CLI/menu；VLESS golden 使用 `jq -S` 与固定 Xray-OneClick reference inbound canonical diff，并单独验证 Encryption absence。`--runtime` 下载当前官方 Xray 和 Snell v4/v5，执行 HY2/VLESS server/client Xray `run -test`、真实 localhost FinalMask/Sudoku 数据面与 Snell listener 验收，并负向断言产品不再下载 v6。

`shfmt -d -i 2 -ci` 用于显示既有风格差异，当前是 advisory 而不是 release gate；项目不会为此对旧 Mieru Bash 执行大规模 `shfmt -w`。发布 gate 仍是 build、`bash -n`、warning 级 ShellCheck、自动化/runtime tests 与 `git diff --check`。

## Real-world validation

1.3.0 在真实 IPLC guest 与独立 Debian client 上直接消费 NoBrand exporter 输出，完成 Mihomo/sing-box 20-request、256 MiB 上下行、服务端/客户端重启、资源采样和 reference-client 验收。Snell v4 的两个核心都完成 3/3 download + 3/3 upload；其它后段 download 被公共 fallback endpoint 的 HTTP 429 限流，按 `ENVIRONMENT BLOCKED` 记录，不伪装成协议 PASS/FAIL。实验速度是特定日期、线路和端点的 **Lab result**，不是 guaranteed speed。

原始公网 baseline 中位数为 download 152.979 Mbps、upload 53.209 Mbps；Snell v4 的 Mihomo/sing-box download 中位数分别为 135.917/137.866 Mbps，upload 中位数为 52.967/53.547 Mbps。综合稳定性、完整 3-run 数据与重启结果，本实验室最保守的已验证组合是 Snell v4 + sing-box；产品默认仍是 Snell v5 + QUIC OFF，使用前应阅读已记录的 sing-box 冷启动敏感性。

完整的脱敏矩阵、失败历史、individual runs、资源与限制见 [Real Client Benchmark](docs/REAL-CLIENT-BENCHMARK.md)。1.1.0 的历史真机报告继续保留在 [Real IPLC / Debian Validation](docs/REAL-LAB-VALIDATION.md)。

更多信息：[CONTRIBUTING](CONTRIBUTING.md)、[模块化](docs/MODULARIZATION.md)、[依赖顺序](docs/MODULE-DEPENDENCIES.md)、[源码审计](docs/SOURCE-AUDIT.md)、[baseline](docs/BASELINE.md)、[1.3.0 真实客户端测试](docs/REAL-CLIENT-BENCHMARK.md)、[历史真机验收](docs/REAL-LAB-VALIDATION.md)。

## 上游与许可证

- 架构与 Mieru 母体：`ike-sh/mieru-OneClick`，保留 MIT attribution。
- Hysteria2 行为来源：`ike-sh/Xray-OneClick/lib/57-hysteria2.sh`，GPL-3.0。
- VLESS FinalMask/Sudoku 结构来源：`ike-sh/Xray-OneClick/lib/50-vless-enc.sh`；NoBrand 只保留 plain VLESS/TCP 与 FinalMask/Sudoku 结构，移除其 Encryption dependency。
- runtimes：`enfein/mieru`、`XTLS/Xray-core`、Surge 官方 Snell Server，各自遵循上游条款。

NoBrand-OneClick 融合源码按 [GPL-3.0](LICENSE) 发布。Mieru MIT notice 及第三方说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
