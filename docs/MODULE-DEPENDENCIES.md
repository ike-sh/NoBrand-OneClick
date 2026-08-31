# Module Dependencies and Runtime Contracts

## 顶层顺序

1. strict mode、umask、attribution；
2. 路径、版本、CLI globals；
3. Bash check、日志、ERR trap；
4. 根据 `$0`/argv 选择 parser；
5. Common/platform/engines/presentation；
6. 唯一 `main` 和 `MITA_SOURCE_ONLY` guard。

Mieru 保留原 global/state 传递。管理锁继续使用 fd 8 与 `_ADMIN_LOCK_HELD`。NoBrand firewall adapter 动态设置 `MITA_FIREWALL_OWNED_STATE=/var/lib/nobrand-oneclick/firewall-owned.bindings` 和 comment，再调用原 implementation。

| Owner | Authority |
|---|---|
| Mieru | `/var/lib/mita-oneclick`, `/etc/mita` |
| Snell | `/var/lib/nobrand-oneclick/snell`, `/etc/nobrand-oneclick/snell` |
| HY2 | `/var/lib/nobrand-oneclick/hysteria2`, `/etc/nobrand-oneclick/hysteria2` |
| VLESS Sudoku | `/var/lib/nobrand-oneclick/vless-sudoku`, `/etc/nobrand-oneclick/vless-sudoku` |
| TUIC v5 | `/var/lib/nobrand-oneclick/tuic`, `/etc/nobrand-oneclick/tuic` |
| SSH Tunnel | NoBrand state/key/marker directories plus a managed sshd policy block/drop-in; system sshd remains external |
| Port Forward | `/var/lib/nobrand-oneclick/forward`, `/etc/nobrand-oneclick/forward`, owned nft table/sysctl fragment, and `nobrand-realm` only |
| Shared Xray binary | `/usr/local/lib/nobrand-oneclick/bin/xray`（仅 NoBrand HY2/VLESS） |
| Shared sing-box binary | `/usr/local/lib/nobrand-oneclick/bin/sing-box`（仅 NoBrand TUIC v5） |
| Realm binary | `/usr/local/lib/nobrand-oneclick/bin/realm`（仅 NoBrand Forward Realm） |

旧 Mieru single-instance state 必须先通过 `state_file_is_secure`，并在子 shell source。

Port registry normalize transport；Snell v4、VLESS Sudoku 与 SSH Tunnel display endpoint 只使用 TCP，Snell v5 QUIC OFF 只申请 TCP、QUIC ON 申请同号 TCP+UDP，HY2 与 TUIC v5 只申请 UDP，Mieru 与 Forward 按 TCP/UDP/BOTH adapter 输出。SSH Tunnel 复用外部 sshd 的真实 listener，因此不注册或管理该 listener/firewall。Forward 禁用 rule 仍保留端口 ownership。自动分配提交前二次检查。同数字 TCP/UDP 可以共存，同 transport 冲突。

Endpoint contract：`listen_*` 是服务端权威配置；`advertise_*` 只属客户端。setter 禁止调用 config writer、service、firewall、tc、quota。

安装事务顺序：prepare → admin lock → snapshot → runtime/config compatibility → 收集请求 → 停旧实例 → TOCTOU → 临时 config/state/client → JSON/semantic/Xray validation → atomic server config → service/firewall → active+listener → atomic client/state commit → 清理旧 firewall。失败执行 ownership-aware rollback，且 listener 验收前不提交 VLESS state。

共享 Xray upgrade：snapshot binary + HY2/VLESS state → 安装并用新 binary 校验两个现存配置 → 只重启升级前 active 的服务 → UDP/TCP listener acceptance → 更新两个 runtime metadata。任一步失败恢复旧 binary/state 并在旧 runtime 上重启原 active 集合。

共享 sing-box upgrade：snapshot runtime/metadata/TUIC state → 用候选 runtime 校验所有实例 → 只重启升级前 active 的 TUIC service → UDP listener acceptance → atomic metadata/state commit。任一步失败恢复旧 runtime、service template、metadata/state 与原 active 集合。

SSH Tunnel apply：snapshot sshd main/drop-in → stage dedicated account/key/marker/state → `sshd -t` 与 per-user `sshd -T -C` → reload → 启动 administrator watchdog。未确认新的管理员 SSH session 前不得确认 policy 变更；超时自动恢复旧 config 并 reload。账号、group、authorized-key 与 state commit 失败必须 ownership-aware rollback。

Forward transaction：exact candidate state validation → snapshot Realm runtime/service、owned nft table、sysctl 与 firewall → Realm candidate temporary-listener probe or `nft -c` → minimum-interruption data-plane order → Realm service/PID/listener or nft ownership acceptance → firewall reconcile → atomic authoritative-state commit。任何失败恢复全部 side effects。Realm domain/IPv6 转 nftables 必须显式新 IPv4 target。

Unified restore 把文件恢复和外部副作用视为同一事务：snapshot sshd config、TUIC runtime/template、Forward Realm/nft/sysctl 和现有 state/config，记录本轮创建的 exact SSH UID/GID/GECOS 与 staged resources；任何后续 acceptance 失败都恢复 snapshot 并删除本轮副作用。

Plain VLESS contract：server `decryption=none`、client `encryption=none`、TCP、`security=none`、FinalMask `tcp[0].type=sudoku`。不存在 Encryption key pair、method、RTT、ticket 或 key-generation dependency。

节点内部行：`protocol|name|display endpoint|status|transport`；Stopped 不丢弃。Running 必须同时满足 service active 和 listener。
