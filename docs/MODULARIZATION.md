# Modular build architecture

NoBrand-OneClick 的单文件发布物由 `scripts/build.sh` 按固定顺序拼接 `src/*.sh`。

```text
src/*.sh
   │
   └── scripts/build.sh
         ├── install-nobrand.sh
         └── dist/install-nobrand.sh
```

只有这两个生成物。构建不生成第二安装器，也不按 `$0` 选择另一套 parser。

## Public entry topology

```text
/usr/local/bin/install-nobrand
        ▲
        │ symlink
/usr/local/bin/nobrand
        ▲
        │ symlink
/usr/local/bin/nb
```

顶层 parser 路由到 Ingress、Mieru、Snell、Hysteria2、VLESS/Sudoku、VLESS REALITY、TUIC v5、SSH Tunnel、Port Forward 与 Common Core。`nb` 不包含可执行逻辑。上游 Mieru runtime 位于 `/usr/local/lib/nobrand-oneclick/bin/mita`，不在 public management API 中。

## Module responsibilities

- `00-bootstrap` / `05-constants` / `10-cli-prelude`：启动、常量与统一 parser
- `15-18-core-*`：schema v3、port、Ingress Profile/enforcement、Endpoint、nodes、backup/uninstall common core
- `20-25-platform-*`：官方 Mieru/Xray/Snell/sing-box/REALITY runtime 下载、digest 校验、安装与平台 service adapter
- `25-network-mtu`：Mieru MTU 策略
- `30-55`：Mieru isolated-v2、多用户、quota/tc、diagnostics、Profile 与 config builder
- `56-59`：Snell、Hysteria2、VLESS/Sudoku、TUIC v5 与 VLESS REALITY 产品逻辑
- `60`：Mieru daemon/firewall；`61`：基于系统 OpenSSH sshd 的 SSH Tunnel
- `62`：nftables/Realm 双后端 Port Forward、Realm runtime/service 与 sysctl ownership
- `65-70`：BBR/FQ、client export 与 lifecycle
- `71-snell-export`：Surge/Mihomo/sing-box exporter
- `80-99`：lifecycle、status、UI 与统一 main dispatcher

## State boundary

`/var/lib/nobrand-oneclick/state.json` 是根 ownership marker。根目录存在但 marker 不是 exact schema v3，或检测到旧 Mieru state 时，除 help/version 外都 fail closed。模块不能添加 migration adapter、旧 client credential fallback 或 wrapper routing。

Mieru production state 位于根目录下的 `mieru/`；`/etc/mita` 只用于上游 runtime 真正需要的 per-instance 配置和 metrics，不是 NoBrand 权威 state。

TUIC 的 shared sing-box runtime、metadata 与 service template 由 NoBrand 管理，实例 state/config/certificate/key 分别位于 TUIC 专属目录。多实例共享 runtime，升级必须先校验所有实例并按事务恢复升级前 active 集合。

SSH Tunnel 只管理专属 Linux group/users、centralized authorized keys 与 forwarding-only `Match Group` policy。监听 socket、sshd binary、主服务和管理员账号都属于外部系统；NoBrand 不安装、替换、停止或卸载系统 sshd，也不管理 SSH firewall。

Forward authority 位于 `forward/state.json`。nftables runtime artifact 是唯一带 marker 的 `table ip nobrand_forward_v4`；Realm runtime/config/service 分别位于 NoBrand private binary path、`forward/realm.toml` 和 `nobrand-realm`。同名但无完整 ownership marker 的表、binary metadata、service 或 sysctl fragment 都是 external conflict，不得接管。

Ingress Profile authority 位于 `ingress.json`。Strict Mieru fallback 另外使用 `ingress-firewall.json`、生成的 `ingress-firewall.nft` 与唯一 `table inet nobrand_ingress`；input policy 保持 accept，规则不带 counter。其它 strict products 使用 native bind，nftables Forward 使用 `ip daddr` match。模块不得用 Display Host 作为 listener，也不得为 strict ingress 创建 policy routing。

## Unified backup/restore transaction

统一备份只包含 NoBrand ownership 内的 schema-v3 state、配置、证书、私钥和 runtime metadata，archive mode 必须是 `0600`。恢复 preflight 不把备份内 marker 当作当前系统账号 ownership 证明；已存在账号必须匹配恢复前的本地 ownership marker 与 UID。

恢复会在产生外部副作用前 snapshot 当前 sshd main/drop-in、TUIC shared runtime/service template，以及 Forward Realm binary/metadata/service、owned nft table 和 sysctl state/fragment；同时记录恢复过程中创建的 SSH user/group 精确身份和 staged resources。后续 config/service/policy acceptance 失败时，必须恢复这些 snapshot、删除本轮新建身份与资源，并恢复原 state/config；不得遗留监听、账号、group、policy、runtime、table、sysctl 或 service ownership。

## Build invariants

- manifest 明确、完整、无重复
- module 不带 shebang、CR 字节，并以 LF 结束
- 生成物必须通过 `bash -n`
- root/dist 内容必须 byte-identical
- `--check` 不写文件，只验证生成物是否陈旧
- 任何源码变化后都必须重新生成两个 artifact
