# Real IPLC / Debian Validation

日期：2026-08-27（Asia/Shanghai）

本报告只记录脱敏结果。完整 node credential、UUID、PSK、auth、Sudoku password、certificate private key 与 SSH material 不进入仓库；远程最终凭据只保存于服务端 root-owned `0600` 文件。

## 结论

- 产品代码、本地 Debian 12 全量回归、真实 TTY、CLI、生命周期、Endpoint、备份恢复、删除重装、共享 Xray 与五项最终公网共存数据面：**PASS**。
- 第一轮独立公网 E2E 中六协议全部达到 20/20，restart 后全部达到 5/5：**PASS**。
- 最终六协议同时存在的两轮有界复测中，Mieru、Snell v4、Snell v5、Hysteria2、VLESS Sudoku 均为 5/5；Snell v6 两轮均为 1/5：**ENVIRONMENT BLOCKED**。
- Snell v6 最终异常已由双端抓包定位为公网入口在三次握手后未把 v6 client payload 交付给 guest；相同 runtime、PSK 与 exporter config 的 IPLC localhost 回环为 PASS。因此该结果没有降级为内网 PASS，也没有归因成伪造的产品 PASS。
- 最终 IPLC 仍保留六个有效节点且全部服务 Running；`<SSH_PORT>` 未被代理占用，公网 SSH 可持续重连。

## Lab contract

- 服务端：`<IPLC_SERVER>`
- 客户端：`<DEBIAN_CLIENT>`
- 强制公网入口：`<PUBLIC_ENTRY_IP>`
- 代理 listener 允许范围：`<AUTO_PORT_POOL>`
- `<SSH_PORT>/TCP`：公网 SSH；同号 TCP/UDP 均禁止分配给代理
- 不允许以 guest/private IP、localhost、hostname 或其它公网 IP 替代强制入口

实验室值没有进入 `src/`；只出现在本报告、被 `.gitignore` 排除的 `<LOCAL_LAB_DIR>` 与远程 `<LAB_ROOT>`。

## Baseline protection

- 权威 baseline：当前未提交 working tree，而不是旧 HEAD 的单协议内容。
- 开始开发前记录了 `git status --short`、`git diff --stat`、完整 diff 与最近提交。
- 本地安全快照：`<LOCAL_SAFETY_SNAPSHOT>`。
- 基线 HEAD：`<BASELINE_COMMIT>`。
- 未使用 `reset --hard`、`clean`、全树 restore/checkout；未 commit、push、PR 或 Release。
- reference worktree 与 SSH helper 配置全程只读。

## Source and protocol audit

- FinalMask/Sudoku 结构以只读 Xray-OneClick 实现为事实来源，并通过固定 UUID/port/password 的 `jq -S` canonical golden diff 验证。
- 允许差异仅为 plain VLESS、NoBrand 路径/状态/服务/tag 与 Display Endpoint wrapper。
- VLESS 服务端固定 `decryption=none`，客户端固定 `encryption=none`，两者都是 plain VLESS 的合法字段。
- transport 固定为 TCP；没有 XHTTP、REALITY、Vision、FullStack 或其它 VLESS 模式。
- 没有调用 `xray vlessenc`，没有生成或保存 Encryption key、decryption secret、ML-KEM、xorpub、method、RTT 或 ticket。

```text
xray vlessenc dependency: NONE
VLESS Encryption: DISABLED / NOT USED
VLESS_ENCRYPTION_ENABLED=false
FINALMASK_MODE=sudoku
TRANSPORT=tcp
```

## Local and container evidence

最终产品修复后在 Docker Debian 12 重新完整运行 `bash scripts/test.sh --runtime`：

| Check | Result | Evidence |
|---|---|---|
| build + deterministic second build | PASS | 两次 generated installer SHA-256 一致 |
| all-shell Bash syntax | PASS | source 与 generated installers |
| warning-level ShellCheck | PASS | 完整 source graph 与 generated installer |
| Common Port + tail-base reservation | PASS | transport-aware registry/listener/bind probe |
| Endpoint isolation | PASS | Mieru/Snell/HY2/VLESS |
| HY2 golden + P-256 certificate | PASS | Xray 26.3.27 `run -test` |
| VLESS server/client canonical golden | PASS | Xray-OneClick parity + `run -test` |
| VLESS Encryption absence | PASS | server/state/client forbidden-field audit |
| VLESS local data plane | PASS | Plain VLESS + FinalMask/Sudoku TCP |
| Snell v4/v5/v6 | PASS | official 4.1.1 / 5.0.1 / 6.0.0rc2 listeners |
| nodes/status/backup/uninstall/rollback | PASS | ownership and restore boundaries |
| CLI + menu mapping | PASS | missing-value parser regression included |
| full NoBrand runtime suite | PASS | all tests completed |

最终 generated `install-nobrand.sh` SHA-256（加入通用 tail-base reservation 后）：

```text
9050e0597c482f1693f2894114f88773192ccc5342edf70bede17de37e4c1a7c
```

## IPLC identity, inventory and backup

清理前确认：

```text
hostname: <IPLC_SERVER>
OS: Debian 13
guest IPv4: <BACKEND_IP>
default gateway: <BACKEND_GATEWAY>
guest sshd: <BACKEND_SSH_PORT>/TCP
public SSH entry: <PUBLIC_ENTRY_IP>:<SSH_PORT>
```

公网 `<SSH_PORT> -> guest <BACKEND_SSH_PORT>` 的 DNAT 不会出现在 guest `ss` 中。NoBrand 因此新增通用规则：从默认路由 IPv4 尾号推导出的 `xx00` 是保留基数，自动代理仍只从 `xx01-xx99` 选择；冲突 owner 显示为 `common:tail-base:<guest-ip>`。产品代码没有硬编码本实验室 IP 或端口。

清理前发现的旧代理内容：

- `snell-server.service`
- `xray.service`
- host-network `remnanode` container（`remnawave/node:latest`，曾占用 TCP/<LEGACY_PROXY_PORT>）
- Remnawave 专属 nft tables `table ip remnanode` 与 `table ip6 remnanode6`

证据与可恢复备份：

```text
inventory: <LAB_ROOT>/preclean-inventory
backup: <LAB_ROOT>/preclean-backup.tar.gz
mode: 0600
SHA-256: 6e007d11df208e94f43987a9eb93bc987cda2b11f377ac8590c44ab1a4822ee2
```

只清理了已识别的旧代理 unit/path/container/table；没有 flush 全局 firewall。清理后重新建立公网 SSH 会话，确认 guest SSH、默认路由、主机身份与网络均正常。

## Port validation

| Check | Result | Detail |
|---|---|---|
| derived block | PASS | `PORT_BASE=<TAIL_BASE_PORT>` |
| formal allocator sample | PASS | 120/120 位于 `<AUTO_PORT_POOL>`；0 次选择 `<TAIL_BASE_PORT>` |
| transport awareness | PASS | `TCP/<TEST_PORT>` 占用时 `UDP/<TEST_PORT>` 可用；反向也可用 |
| explicit tail-base TCP rejection | PASS | rc=1，无 Snell state/config/service 落盘 |
| SSH reconnect after rejection | PASS | 公网 `<PUBLIC_ENTRY_IP>:<SSH_PORT>` |

一次 400-sample 探针超过 SSH wrapper 的单次时间窗口，因没有完整输出而没有计为 PASS；随后正式重跑的 120 samples 位于规范要求的 100-500 范围内并完整 PASS。

第一次显式 tail-base 测试用“所有 Common 文件数完全不变”断言，被首次创建空 Common layout 影响。协议 state/config/service 均未产生；第二次将断言收窄到协议边界与 Common state hash 后 PASS。这是测试断言修正，不是 Snell state 泄漏。

## Initial six-protocol public E2E

所有 client config 均来自 NoBrand exporter/state，先断言 host 等于强制公网入口，再使用 `curl --noproxy '' --socks5-hostname`。每项覆盖 Cloudflare trace 与 Apple success endpoint；tcpdump 证明目标为强制公网地址；exit IP 只保存脱敏值。

| Protocol | Server Runtime | Transport | Real Listener | Display Endpoint | Client Runtime | Requests | Restart | Result |
|---|---|---|---|---|---|---:|---:|---|
| Mieru | 3.35.0 | TCP | TCP/<MIERU_PORT> | `<PUBLIC_ENTRY_IP>:<MIERU_PORT>` | Mieru 3.35.0 | 20/20 | 5/5 | PASS |
| Snell v4 | 4.1.1 | TCP | TCP/<SNELL_V4_PORT> | `<PUBLIC_ENTRY_IP>:<SNELL_V4_PORT>` | sing-box 1.14.0-rc.1 | 20/20 | 5/5 | PASS |
| Snell v5 | 5.0.1 | TCP | TCP/<SNELL_V5_PORT> | `<PUBLIC_ENTRY_IP>:<SNELL_V5_PORT>` | sing-box 1.14.0-rc.1 (`version=4` wire-compatible mode) | 20/20 | 5/5 | PASS |
| Snell v6 | 6.0.0rc2 | TCP | TCP/<LEGACY_SNELL_V6_PORT> | `<PUBLIC_ENTRY_IP>:<LEGACY_SNELL_V6_PORT>` | sing-box 1.14.0-rc.1 | 20/20 | 5/5 | PASS |
| Hysteria2 | Xray 26.3.27 | UDP | UDP/<HY2_PORT> | `<PUBLIC_ENTRY_IP>:<HY2_PORT>` | sing-box 1.14.0-rc.1 | 20/20 | 5/5 | PASS |
| VLESS Sudoku | Xray 26.3.27 | TCP | TCP/<VLESS_PORT> | `<PUBLIC_ENTRY_IP>:<VLESS_PORT>` | Xray 26.3.27 | 20/20 | 5/5 | PASS |

Snell v6 行由官方 Surge Snell Server 6.0.0rc2 与实际 sing-box v6 握手完成，不是只做 config check。Mieru 与 HY2 的真实失败/重测详见后面的异常表。

## TTY, lifecycle and isolation

真实 `python3-pexpect` PTY（不是 stdin pipe）结果：

```text
TRUE_TTY_MENU=PASS
top=0-11
mieru=0-10
snell=0-9
hy2=0-10
vless=0-11
backup=0-3
invalid=text,-1,999,empty
```

- Mieru reconfigure 没有 cancel affordance，因此独立菜单进程在到达真实首个表单 prompt 后用 Ctrl-C 结束，未提交配置；handler 可达性已覆盖。
- 删除菜单以 `no` 取消；真实 remove/reinstall 已由 CLI 独立完成。
- HY2/VLESS install 与 runtime upgrade、Backup create/list/restore 均通过真实菜单执行。
- TTY log 目录为 `0700`，每个 log 为 `0600`。

六协议 Endpoint isolation 均 PASS：仅改变 Display Endpoint 时 server config hash、PID、listener 与 firewall ownership hash 不变，node/export 改变；恢复原 Display Endpoint 后导出恢复。

六协议 Stop/Start 均 PASS：Stop 后 inactive、listener 消失、node 保留且显示 Stopped、state `enabled=false` 保留；Start 后 service/listener 恢复。

真实 Backup/Restore PASS：archive `0600`，managed hashes 与 nodes 恢复一致，service 运行，Mieru 保留。真实 archive：

```text
/var/lib/nobrand-oneclick/backups/nobrand-backup-real-lab.tar.gz
```

Idempotency 与 remove/reinstall：

- Mieru 二次安装保留 users/config 且 service singleton。
- Snell v4/v5/v6 同名 duplicate 被拒绝，实例数保持三个。
- HY2 singleton；VLESS singleton，二次安装不轮换现有 UUID/Sudoku password。
- 每协议 remove 后其它五项保持；reinstall 后服务、state、listener、export 恢复。
- 单删 HY2/VLESS 均保留另一个协议与共享 Xray；VLESS reinstall 后 Encryption absence 再次 PASS。

## Shared and external Xray

最终 HY2 与 VLESS：

- 两个独立 Xray PID。
- 独立 config/state/service。
- 共用 `/usr/local/lib/nobrand-oneclick/bin/xray`，`/proc/<pid>/exe` inode 相同。
- TTY 中从 HY2 和 VLESS 菜单分别执行 current-version shared-runtime upgrade；两个 config 均先验证，两个 active listener 均恢复。
- `/etc/xray` 与 `xray.service` 不存在。
- 旧 `/usr/local/bin/ike` 保留原 2026-08-25 时间戳，NoBrand config/state/unit 无引用，证明未覆盖也不依赖。

## Final credential bundle

remove/reinstall 与 TTY 会轮换 credential，因此旧包未用于最终回归。最终包重新从当前 Mieru exporter、canonical Snell sing-box exporter、HY2 state conversion 与 NoBrand-generated VLESS Xray client JSON 构建。

```text
IPLC: <LAB_ROOT>/<CLIENT_BUNDLE>
local ignored lab: <LOCAL_LAB_DIR>/<CLIENT_BUNDLE>
Debian: <LAB_ROOT>/<CLIENT_BUNDLE>
SHA-256: <BUNDLE_SHA256>
mode: 0600
```

三段传输 SHA-256 一致。每个 remote target 都再次断言为 `<PUBLIC_ENTRY_IP>`；VLESS server/state/generated client/transferred client 再次通过 Encryption absence 与 Xray `run -test`。

完整最终 credential handoff：

```text
<LAB_ROOT>/<FINAL_NODES_FILE>
mode: 0600
```

本报告和对话均不输出其内容。

## Final simultaneous regression

Debian 原有 localhost OpenSnell 与 network-lab listener 在测试前后 PID/listener 一致。NoBrand 只临时使用 `<LOCAL_CLIENT_PORT_RANGE>`，同时启动六个 client；结束时只终止记录的测试 PID。

v6 公网异常出现后，先在旧端口重启服务，再由 Common Port 重装到 `<LEGACY_SNELL_V6_PORT>`；两端 exporter/state/PSK 与官方 runtime 均一致。端口变更没有改变公网 payload blackhole，因此执行两次有界完整共存复测，不无限重试“刷”PASS。

| Protocol | Final listener | Final Display Endpoint | Requests round 1 | Requests round 2 | Public packets | Result |
|---|---|---|---:|---:|---:|---|
| Mieru | TCP/<MIERU_PORT> | `<PUBLIC_ENTRY_IP>:<MIERU_PORT>` | 5/5 | 5/5 | 107 / 111 | PASS |
| Snell v4 | TCP/<SNELL_V4_PORT> | `<PUBLIC_ENTRY_IP>:<SNELL_V4_PORT>` | 5/5 | 5/5 | 69 / 70 | PASS |
| Snell v5 | TCP/<SNELL_V5_PORT> | `<PUBLIC_ENTRY_IP>:<SNELL_V5_PORT>` | 5/5 | 5/5 | 70 / 71 | PASS |
| Snell v6 | TCP/<LEGACY_SNELL_V6_PORT> | `<PUBLIC_ENTRY_IP>:<LEGACY_SNELL_V6_PORT>` | 1/5 | 1/5 | 60 / 60 | ENVIRONMENT BLOCKED |
| Hysteria2 | UDP/<HY2_PORT> | `<PUBLIC_ENTRY_IP>:<HY2_PORT>` | 5/5 | 5/5 | 61 / 66 | PASS |
| VLESS Sudoku | TCP/<VLESS_PORT> | `<PUBLIC_ENTRY_IP>:<VLESS_PORT>` | 5/5 | 5/5 | 16 / 43 | PASS |

Snell v6 的双端证据：

1. Debian 到 `<PUBLIC_ENTRY_IP>:<LEGACY_SNELL_V6_PORT>` 三次握手 PASS。
2. Debian tcpdump 看到 canonical sing-box client 发送 v6 payload 并重传。
3. 同时段 IPLC guest tcpdump 只看到 SYN/ACK/ACK，完全看不到该 payload；server 10 秒后关闭空连接。
4. 同一官方 1.14.0-rc.1 sing-box、同一 PSK、同一 exporter outbound，通过 IPLC localhost 回环访问 Cloudflare：PASS。
5. 公网 Snell v4 同期 3/3，最终两轮 v4/v5 仍 5/5；不是全局公网或 Debian 故障。
6. v6 更换端口后结果相同，排除单一端口编号。

以上满足环境阻塞的证据标准。没有用 guest IP 代替公网结果；localhost 只作定位，不计 E2E PASS。初始独立 20/20 与后期 final simultaneous 环境阻塞均保留。

## Final CLI, doctor and runtime state

以下均 PASS，输出保存到 `<LAB_ROOT>/final-audit/` 的 `0600` 文件：

- `nobrand status`、`nobrand nodes`、`nobrand doctor`
- `nb status`
- Mieru/Snell/HY2/VLESS status/doctor，VLESS smoke
- `mita users`、`mita doctor`、`mita perf`
- help 中显示 Plain VLESS + FinalMask + Sudoku/TCP 与 `VLESS Encryption: NOT USED`

最终 doctor：

```text
Mieru: PASS=23 WARN=0 FAIL=0
NoBrand unified checks: PASS=42 WARN=0 FAIL=0
```

最终 service/listener：

| Owner | Listener | Service state |
|---|---|---|
| public SSH DNAT | public TCP/<SSH_PORT> -> guest TCP/<BACKEND_SSH_PORT> | PASS / reconnect PASS |
| Mieru | TCP/<MIERU_PORT> | Running |
| Snell v4 | TCP/<SNELL_V4_PORT> | Running |
| Snell v5 | TCP/<SNELL_V5_PORT>（官方 runtime 同时有同号 UDP relay listener） | Running |
| Snell v6 | TCP/<LEGACY_SNELL_V6_PORT> | Running |
| Hysteria2 | UDP/<HY2_PORT> | Running |
| VLESS Sudoku | TCP/<VLESS_PORT> | Running |

所有代理端口位于 `<AUTO_PORT_POOL>`；`PROXY_SSH_PORT_COUNT=0`。所有 Display Host 为强制公网入口。

## Bugs and real failures

| ID | Severity | Symptom / original result | Root cause | Affected file or layer | Fix / retest | Real-machine result |
|---|---|---|---|---|---|---|
| NB-PORT-001 | High | guest 看不到 public SSH DNAT，allocator 可能认为同号内部端口空闲 | NAT 外部端口不出现在 guest socket table | `src/16-core-port.sh`, `src/35-users-state.sh` | 通用保留默认路由 IPv4 尾号块的 `xx00`，新增 Common Port regression | explicit tail-base rejection PASS；120 samples 0 次选择保留端口；SSH PASS |
| NB-STATE-001 | Medium | Stop 后 `enabled=false` 可能被当作字段缺失 | boolean getter 使用 truthiness 而非字段存在性 | protocol state getters | 按 JSON field presence 读取 false，新增 lifecycle regression | 六协议 Stop/Start PASS |
| LAB-MIERU-001 | Test | 首轮 Mieru 19/20 | Microsoft endpoint 单次 timeout | remote E2E target | 该轮 FAIL；换为 Cloudflare + Apple 后整轮重跑 | 20/20 PASS |
| LAB-MIERU-002 | Test | 次轮 20/20 但出口断言失败 | harness 遗漏 `--noproxy ''`，环境 `NO_PROXY` 可绕过 SOCKS | lab curl harness | 该轮作废；强制 `--noproxy '' --socks5-hostname` | 20/20 + target packets PASS |
| LAB-SNELL-001 | Client limit | Debian sing-box 1.13.19 报 `unknown outbound type: snell` | Snell outbound 从 sing-box 1.14 开始支持 | Debian client runtime | 换用官方 1.14.0-rc.1 并比对 release hash | v4/v5/v6 config check PASS；初始三项 20/20 PASS |
| LAB-HY2-001 | Test/runtime timing | restart 后立即请求出现 3 次 timeout/TLS EOF | QUIC client 会话恢复慢于 SOCKS listener | final restart harness | 原轮 FAIL；增加健康探针后重新完整 5 次 | 5/5 PASS |
| LAB-PORT-001 | Test | 首次 tail-base“文件总数不变”断言失败 | 首次运行只初始化空 Common layout | lab boundary assertion | 收窄为协议 state/config/service 与 Common hash | 第二次 PASS，无 Snell state 落盘 |
| LAB-TTY-001 | Test | TTY harness 两次停在真实 prompt | nested invalid input 有 pause；Mieru reconfigure 首 prompt 与初版 regex 不同 | ignored local TTY harness | 按真实 UI 顺序匹配后整轮重跑 | 全菜单 TRUE_TTY PASS |
| LAB-V6-001 | Environment | final simultaneous v6 两轮 1/5 | public path 在 TCP handshake 后未向 guest 交付 v6 payload；loopback wire PASS | external IPLC/NAT path | restart、换端口、重新 exporter/transfer、双端 capture、有界重测 | ENVIRONMENT BLOCKED；其它五项两轮 5/5 |

## Static/orphan audit summary

- Build manifest 包含 VLESS Sudoku module 与 Snell exporter。
- 连续 build 可复现；generated installer 与 source graph 均通过 syntax/ShellCheck。
- duplicate-function audit 未发现无意覆盖。
- menu-to-handler mapping 由静态 test 与真实 TTY 双重覆盖。
- state 字段经 install/show/status/doctor/endpoint/stop-start/backup-restore/remove 路径覆盖；未发现会在 restore 中丢失的 VLESS 必需字段。
- systemd/OpenRC config/service 的安装与删除边界由 unit test 和实机循环覆盖。
- VLESS Encryption 专属 token/field 全仓与真机 artifact absence test PASS。

## Known limitations and SPEC deviations

- **ENVIRONMENT BLOCKED：**最终 simultaneous Snell v6 公网数据面只有 1/5 + 1/5。初始同一公网入口曾 20/20、restart 5/5；后期双端抓包证明 payload 在 guest 前消失。不能以 localhost PASS 替代。
- Snell v6 仍是实验协议；Mihomo 不支持，sing-box 需要 1.14+。本实验使用当前官方预发布 1.14.0-rc.1。
- Snell v5 sing-box `version=4` 只表达未启用 QUIC Proxy Mode 时的上游 wire compatibility，server 仍是官方 v5.0.1。
- Mieru 最终节点配置为 TCP；没有把未配置的 Mieru UDP relay 记为已测试。
- Snell v5 存在官方同号 UDP listener，但本报告没有单独宣称 UDP relay application E2E；标记 **NOT RUN**。HY2 的 UDP/QUIC 主数据面已执行。
- Mieru reconfigure 菜单没有 cancel；TTY 覆盖在首个真实 prompt 处 Ctrl-C，不提交一次无意义的 credential 轮换。真实配置/二次安装/Endpoint/删除重装已由其它路径完成。
- `shfmt -d -i 2 -ci`：**ADVISORY**，报告 30,194 行既有格式差异，主要是紧凑 `case`/多语句布局；命令的非零退出只表示存在 diff，不是 release gate。按“不要大规模审美格式化旧 Mieru”的约束未机械改写，Bash syntax、warning-level ShellCheck、build reproducibility 与全部 runtime tests 仍为 PASS。

除以上明确项目外，无其它已知 SPEC deviation。所有失败均保留原始分类，没有把 `FAIL`、`NOT RUN` 或 `ENVIRONMENT BLOCKED` 改写为 PASS。

## Release-hardening follow-up

2026-08-27 的发布收尾只更新管理脚本并执行非破坏性复验；没有重装、删除或重配任一协议服务，也没有修改 listener、state/config、firewall、tc/quota 或 credential。部署到 IPLC 的四份兼容管理入口与本地最终产物一致：

```text
artifact bytes: 559262
SHA-256: e112ab98670a7881e36dd683bb1c2d2fa3780c8269f1356937da6858d02385c8
version: NoBrand-OneClick 1.1.0
author: ike
```

### Local release gates

| Check | Result | Release-hardening evidence |
|---|---|---|
| Docker Debian unit suite | PASS | `bash scripts/test.sh` |
| Docker Debian 12 runtime suite | PASS | `bash scripts/test.sh --runtime`；HY2/VLESS/Snell real runtime 与 VLESS localhost data plane |
| Mieru lifecycle regression | PASS | `scripts/docker-smoke.sh` |
| Compatibility matrix | PASS | Debian 12、Ubuntu 24.04、Rocky 9、Alpine 3.20 |
| Build manifest | PASS | 30 个 source module，30 个唯一 manifest entry，无遗漏或重复 |
| Deterministic build | PASS | 两次 build、四份 installer 均为上列同一 SHA-256 |
| Generated artifact check | PASS | `bash scripts/build.sh --check` |
| Bash syntax | PASS | source、scripts、tests 与四份 installer，共 56 个 shell 文件 |
| Warning-level ShellCheck | PASS | source graph 与 generated installer |
| Git whitespace check | PASS | `git diff --check` |
| shfmt | ADVISORY | `shfmt -d -i 2 -ci` 返回 30,406 行风格差异；未运行 `shfmt -w`，不是 release blocker |

### Final non-destructive IPLC control plane

通过新的公网 SSH 会话复验 `<PUBLIC_ENTRY_IP>:<SSH_PORT>`，连接 PASS。最终 `nobrand status`/`nodes`/`doctor` 与 `ss` 结果：

- Mieru 1/1 Running；Snell 3/3 Running；Hysteria2 Running；VLESS/Sudoku Running。
- Mieru doctor `PASS=23 WARN=0 FAIL=0`；NoBrand unified doctor `PASS=42 WARN=0 FAIL=0 INFO=3`。
- Snell v5 的同进程 `UDP/<SNELL_V5_PORT>` 只显示 auxiliary runtime INFO；canonical ownership 仍为 `TCP/<SNELL_V5_PORT>`。
- Snell v6 control plane PASS，并显示 Experimental/environment-dependent INFO；普通 Doctor 没有公网联网 gate。
- `PROXY_SSH_PORT_COUNT=0`；代理监听使用各协议对应的脱敏端口占位符。
- HY2/VLESS 仍为独立 PID、config/state/service，共享同一个 `/usr/local/lib/nobrand-oneclick/bin/xray` inode。

### One bounded Debian public-path retest

本轮只执行一次固定上限测试。五个稳定/兼容/受支持协议各 5 次全部成功；Snell v6 同一轮最多 5 次，没有追加重试、换内网地址或换端口：

| Protocol | Requests | Public entry packets | Result |
|---|---:|---:|---|
| Mieru | 5/5 | 109 | PASS |
| Snell v4 | 5/5 | 66 | PASS |
| Snell v5 | 5/5 | 71 | PASS |
| Snell v6 | 1/5 | 63 | ENVIRONMENT BLOCKED |
| Hysteria2 | 5/5 | 62 | PASS |
| VLESS/Sudoku | 5/5 | 53 | PASS |

Snell v6 再次表现为公网 TCP/packet 可达但 payload 在进入 guest 前丢失，与既有双端 capture 结论相同，因此立即停止并保留 `ENVIRONMENT BLOCKED`，没有把 localhost wire PASS 替代为公网 PASS。VLESS 同轮再次确认：

```text
VLESS_ENCRYPTION_ENABLED=false
FINALMASK_MODE=sudoku
TRANSPORT=tcp
```

### Minimal real-PTY release smoke

新的 `python3-pexpect` 真实 PTY 冒烟只覆盖菜单导航，没有调用 install、remove、reconfigure、upgrade、backup/restore 或 service-control handler：

```text
PTY_TOP=PASS invalid=PASS exit=PASS
PTY_SUBMENU=mieru invalid=PASS back=PASS exit=PASS
PTY_SUBMENU=snell invalid=PASS back=PASS exit=PASS
PTY_SUBMENU=hy2 invalid=PASS back=PASS exit=PASS
PTY_SUBMENU=vless invalid=PASS back=PASS exit=PASS
PTY_SUBMENU=backup invalid=PASS back=PASS exit=PASS
TRUE_TTY_RELEASE_SMOKE=PASS destructive_handlers=0
```

### Final release-tree security review

- release 文件集 73 个；本地实验目录与安全快照目录均被 Git 忽略。
- 没有超过 1 MiB/5 MiB 的 release 文件，没有 vendored binary、archive、PCAP 或 credential bundle。
- 没有 CRLF 文本、private-key header、SSH material 或敏感文件名。
- UUID literal 只存在于明确的 VLESS 测试 fixture；32-hex literal 只属于测试 fixture 或非秘密 fallback。
- 生产 `src/`、`scripts/` 没有真实实验 IP、节点端口或 SSH helper 路径；本历史验证文档也已使用占位符脱敏。
- 命名为 password/PSK/auth/UUID/secret/token 的固定 literal 只存在于测试 fixture；未发现真实 credential 进入 release tree 或 diff。

本 follow-up 不覆盖或改写前文任何原始 `FAIL`、`NOT RUN` 或 `ENVIRONMENT BLOCKED`。发布结论为 `READY WITH KNOWN LIMITATIONS`：已知限制仅包括上述 Snell v6 特定公网路径环境阻断和可见但非 gate 的 shfmt advisory。
