# Modular build architecture

`scripts/build.sh` 按固定顺序拼接 `src/*.sh`，并内嵌 `runtime/splicore.py`、
`runtime/splicore-launch.py` 与唯一的 `runtime/splicore-release.json`。
`install-nobrand.sh` 和 `dist/install-nobrand.sh` 是字节一致的独立单文件安装器。

## Public entry topology

`/usr/local/bin/nb` → `/usr/local/bin/nobrand` → `/usr/local/bin/install-nobrand`。
统一 parser 根据协议/操作路由，不根据命令 basename 切换实现。

## Module responsibilities

| Module | Current responsibility |
|---|---|
| `00` / `05` / `10` | 启动、常量、统一 parser；固定 rc.4 协议入口 |
| `15`–`18` | schema-v3 registry、端口、Ingress、Endpoint、通用 lifecycle 和 native backup/restore |
| `19-splicore` + `runtime/` | 只读 legacy 拒绝、统一 artifact、原生 desired、单 daemon、generation 事务、客户端投影 |
| `20`–`25` | 公共依赖/平台工具；Xray 下载只供既有 FinalMask/Sudoku 例外 |
| `30`–`55` | 普通协议适配、通用诊断、参数选择；旧实例/配额实现已移除 |
| `56`–`59` | 普通协议薄入口和既有 FinalMask/Sudoku 实现 |
| `60` / `61` / `62` | 公共 firewall、系统 OpenSSH 账号策略、nftables/Realm Forward |
| `65`–`99` | BBR、管理器安装、lifecycle、状态、UI、main |

空模块保留在有序构建清单中，不提供旧 Core fallback。

## State boundary

产品 registry `state.json` 使用 `schema_version=3`，并明确标记
`architecture=splicore-native`、`splicore_version=v0.3.0-rc.4`、`config_schema=1`。
原生协议 authority 是 `splicore/current/desired.json`；`current` 指向已验证 generation。
每个 generation 使用独立 DB、私有控制 socket/key，普通协议共用一个活动 daemon。

任何 mutation 前先检查 NoBrand 拥有的旧路径/服务/状态。旧安装只拒绝，不转换、备份、
停止服务、重写证书或代为卸载。第三方同名软件不构成 ownership 证据。

Ingress Profile authority 在 `ingress.json`。原生节点持有 Profile ID；strict bind
通过原生 `set-listen` generation 事务应用。端口 registry 同时保留 Local Tunnel Guard
loopback 端口，Display Host 不决定 listener，也不创建 policy routing。

SSH Tunnel 保留系统 sshd 的账号/策略层和管理员确认流程。Forward 保留独立 ownership
的 nftables/Realm 资源。FinalMask/Sudoku 保留其固定 Xray 例外；这些资源不属于普通协议
下载路径。

## Backup, upgrade and rollback

统一备份只接受 native registry marker，提取前拒绝旧普通协议 namespace，归档权限为
`0600`。恢复保留原生 generation 事务和 SSH/Forward 的外部副作用快照；失败恢复原状态。
不再快照/恢复旧 Mita、Snell、sing-box 或 HY2 服务。

未来 Splicore 升级仍使用 exact artifact、预验证、原子 generation 发布和 binary/config
rollback。同版本执行 verify/no-op。当前 manifest 不承诺尚未公开版本的兼容性。

当前产品合同见 [README](../README.md)、[rc.4 contract](SPLICORE-RC4-CONTRACT.md)
和 [安装/升级说明](SPLICORE-MIGRATION.md)。
