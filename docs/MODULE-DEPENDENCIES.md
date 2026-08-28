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
| Shared Xray binary | `/usr/local/lib/nobrand-oneclick/bin/xray`（仅 NoBrand HY2/VLESS） |

旧 Mieru single-instance state 必须先通过 `state_file_is_secure`，并在子 shell source。

Port registry normalize transport；Snell v4 与 VLESS Sudoku 只申请 TCP，Snell v5 QUIC OFF 只申请 TCP、QUIC ON 申请同号 TCP+UDP，HY2 只申请 UDP，Mieru 按 TCP/UDP/BOTH adapter 输出。自动分配提交前二次检查。同数字 TCP/UDP 可以共存，同 transport 冲突。

Endpoint contract：`listen_*` 是服务端权威配置；`advertise_*` 只属客户端。setter 禁止调用 config writer、service、firewall、tc、quota。

安装事务顺序：prepare → admin lock → snapshot → runtime/config compatibility → 收集请求 → 停旧实例 → TOCTOU → 临时 config/state/client → JSON/semantic/Xray validation → atomic server config → service/firewall → active+listener → atomic client/state commit → 清理旧 firewall。失败执行 ownership-aware rollback，且 listener 验收前不提交 VLESS state。

共享 Xray upgrade：snapshot binary + HY2/VLESS state → 安装并用新 binary 校验两个现存配置 → 只重启升级前 active 的服务 → UDP/TCP listener acceptance → 更新两个 runtime metadata。任一步失败恢复旧 binary/state 并在旧 runtime 上重启原 active 集合。

Plain VLESS contract：server `decryption=none`、client `encryption=none`、TCP、`security=none`、FinalMask `tcp[0].type=sudoku`。不存在 Encryption key pair、method、RTT、ticket 或 key-generation dependency。

节点内部行：`protocol|name|display endpoint|status|transport`；Stopped 不丢弃。Running 必须同时满足 service active 和 listener。
