# 新架构安装、升级与故障排查

文件路径为既有文档链接保留。当前合同是 fresh install，不再提供 legacy migration。

## 旧版与新版

旧 NoBrand 多 Core 安装无法原地升级到 Splicore。新版检测 NoBrand 拥有的旧状态、Mita/sing-box/Hysteria/Xray 路径和旧服务名，并在任何安装变更前拒绝。已有 Sudoku 的专用 Xray 例外保留。第三方 PATH 中的同名二进制或独立服务不构成旧安装证据。

按以下顺序处理旧安装：用对应旧版备份现有客户端信息，使用对应旧版卸载，确认旧版拥有的资源已清理，再新装新版并使用新配置。新版 `uninstall`、`purge`、`backup restore` 不会替你迁移或清理旧安装。不要手工伪造 `architecture` 标记绕过拒绝。

## 新装

参见 [README](../README.md) 的命令。Debian/Ubuntu、RHEL 系和 Alpine 的依赖/服务模板保留；公开 artifact 只支持 amd64/arm64，其他架构拒绝，无源码编译或 legacy fallback。

状态 authority：`architecture=splicore-native`、`splicore_version=v0.3.0-rc.4`、`config_schema=1`。产品 registry 的 `schema_version=3` 与原生 desired schema 是不同层次。节点直接保存原生 managed creation 文档，不经过 Xray/sing-box 配置转换。

默认 Mieru 是 TCP、MTU 1400、traffic off、低熵关闭。BOTH 映射为一对 TCP/UDP inbound，UDP 使用 port+1。无独立 Mita 下载、账号 metrics scheduler、配额或 tc 限速。旧版的 unsupported CLI 选项会拒绝。

## TLS

HY2/TUIC 默认：新私有 CA + 825 天非 CA leaf，SAN 使用 SNI 域名或 IP，serverAuth + digitalSignature，证书链 leaf 在前。私钥 0600；CA 签名 key 不保留。自备证书可在 `nobrand runtime apply --file DESIRED.json` 的原生 TLS 字段中指定，需要符合相同检查；ACME 自动签发不在项目功能内。

sing-box 导出显式 CA、主机名验证且 insecure=false。Mihomo 导出显式叶证书 pin 且 skip-cert-verify=false；已用公开参考客户端实测。HY2 URI 的 `insecure=1` 仅配合强制 `pinSHA256` 使用私有信任，绝不是无约束跳过校验。忽略 pin 的客户端不受支持；使用完整导出配置。不要修改 pin 去适应其他证书。

## REALITY

指定 cover 主机/端口即可。renderer 生成 UUID/keypair/short-id、Vision、回环 Local Tunnel Guard 以及有序的 allow-direct/reject 路由。guard 只拨固定 cover，不拨 sniffed SNI。合法 cover 的普通 TLS 探测可到 cover；其他 SNI、无 SNI 和非 TLS 失败关闭。错误 REALITY 凭据无法访问代理目的地。

cover 不是已认证 VLESS 的目的地白名单；项目没有在这里添加旧 defender/private-IP 防火墙。见[公开合同](SPLICORE-RC4-CONTRACT.md)。

## 原生版本升级

`nobrand mieru upgrade`、各协议 update 入口或 `runtime apply` 共享一个 artifact/generation 事务。相同 manifest 与 desired 只 verify，不重启。未来升级需维护者更新审核过的 manifest、校验和及测试；不会访问 Splicore latest/main/master/nightly。

候选先校验证书、端口、bootstrap 与 inbound；REALITY 另在 client runtime 停止的私有进程中校验 guard/rules。完成后才停止主服务并切换指针。失败恢复同一 Splicore 架构的上一代 binary/config/database/master key。首次失败不启动任何旧 Core。

`runtime rollback` 回滚上一代已知可用 Splicore。`runtime recover` 处理持久 journal。SIGKILL 后 launcher 检查精确拥有的残留 PID/socket/lock，拒绝活动或第三方占用。

## 备份与卸载

`nobrand backup create PATH` 保存完整 native state/config（0600），序列化 generation 指针，不包含下载二进制/普通服务文件。恢复前检查 archive traversal、link、类型、大小、native marker，下载并校验精确 artifact 后恢复服务。旧备份不导入。备份含凭据和主密钥，必须私下保存。

`runtime uninstall` 移除 native runtime 的活动资源；`runtime purge` 同时清理其拥有的数据。`nobrand uninstall` 还处理项目已有 Sudoku、Forward、SSH 和管理器资源；保留第三方资源与 SSH 管理员确认流程。legacy 命中时一律拒绝。

## FAQ / 排查

- **升级时显示 Legacy NoBrand…**：不会有自动迁移或自动修复。使用对应旧版备份/卸载，再 clean install。
- **CAPABILITY_UNSUPPORTED**：当前 release 没有该选项的映射；去掉显式不支持选项或选择已支持的模式。不会自动换 Core。
- **PORT_CONFLICT**：指定端口被第三方或其他 managed listener 使用；修改本次安装端口。端口冲突不会判作旧架构。
- **CONFIG_INVALID / native validator**：检查 canonical 文档、TLS 路径/SAN/权限及 cover；候选失败前不会切换主服务。安全错误摘要不含凭据。
- **客户端无法验证 TLS**：重新导入当前配置和 CA/pin，核对 SNI；不关闭验证。
- **只看状态**：`nobrand status`、`nobrand doctor`、`nobrand runtime plan`。显式 export/render/backup 含敏感数据，不要贴到公开报告。
- **systemd/OpenRC/arm64 是否已实机认证**：尚未。现有真实流量结果限 Linux amd64 回环和临时进程 supervisor；arm64 为 BUILD ONLY。
