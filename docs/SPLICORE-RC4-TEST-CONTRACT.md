# rc.4 Fresh Architecture Test Contract

本轮验收对应 fresh-install-only 产品合同。`scripts/test.sh` 中的显式清单是当前验收入口；
旧多 Core fixture 不再作为兼容承诺。没有运行的历史测试不能计作 PASS。所有 shell 文件仍参与
`bash -n` 和 ShellCheck。历史报告及其原始 BLOCKED/PENDING 结论保持不变。

## Current acceptance

- 30 个 Bash 验收入口；112 个 Python 测试，批次为 27 + 10 + 22 + 33 + 20；42 个真实 rc.4 回环 runtime 检查。
- `test_splicore_runtime.sh` 内含 27 个 Python 测试：原生 generation、artifact、精确版本/架构、校验失败前无服务变更、并发、持久恢复、单一 supervisor、备份/恢复、候选失败回滚和幂等卸载。
- `test_splicore_fresh.sh` 内含 10 个 Python 测试：13 类旧 ownership 证据 × 7 类操作零变更、第三方误判、marker、新证书/信任、失败清理、旧备份拒绝、Ingress 和 REALITY guard。
- `test_splicore_cert_lifecycle.sh` 内含 22 个证书所有权、校验和重装生命周期测试。
- `test_splicore_qualification.sh` 内含 33 个资格/脱敏诊断/发布元数据/生命周期修复完整性测试及 20 个 root 能力边界测试；不跳过必需 fixture。
- `test_splicore_legacy_refusal.sh` 从真实 main 验证 8 类入口在 lock/package/runtime/backup/uninstall 之前拒绝；旧文件字节保持一致。
- `test_splicore_shell_surface.sh` 验证 manager 新装、schema、备份、native 端口 registry、guard 端口保留、菜单选择、v4 生命周期和卸载重装，以及旧架构、畸形版本和未来 schema 的零变更拒绝。
- `test_splicore_rc4_contract.sh` 验证唯一 rc.4 manifest、公开资产、限定架构、旧转换/API/下载器和兼容升级状态均已删除。
- Ingress、Forward、SSH、Sudoku、CLI、菜单并发/选择、schema、版本、本地化、代码结构及仓库脱敏测试保留或重写为当前接口。

当前入口：

```text
test_splicore_runtime.sh
test_splicore_legacy_refusal.sh
test_splicore_fresh.sh
test_splicore_cert_lifecycle.sh
test_splicore_shell_surface.sh
test_splicore_rc4_contract.sh
test_splicore_qualification.sh
test_architecture_audit.sh
test_repository_sanitization.sh
test_schema_v3.sh
test_common_port.sh
test_ingress_profiles.sh
test_ingress_interactive.sh
test_ingress_enforcement.sh
test_ingress_enforcement_transaction.sh
test_forward.sh
test_forward_transaction.sh
test_forward_sysctl.sh
test_forward_ownership.sh
test_ssh_tunnel.sh
test_ssh_tunnel_transaction.sh
test_vless_sudoku_golden.sh
test_vless_sudoku_encryption_absence.sh
test_vless_sudoku_lifecycle.sh
test_cli.sh
test_menu.sh
test_menu_lifecycle_lock_scope.sh
test_menu_instance_selection.sh
test_version_consistency.sh
test_localization.sh
```

## v4.0.0 release metadata integrity

历史 frozen/certificate-fix manifests 保持原字节。发布资格额外要求 `src/05-constants.sh`、`src/18-core-nodes.sh` 和 `runtime/splicore.py` 的完整字节精确等于 e90695，仅允许各一个已声明版本字段从 3.2.6 改为 4.0.0；生成安装器仍须由未修改的构建脚本精确重建。版本字段之外的改动、其他版本、缺失文件和 symlink 均拒绝。其他冻结产品文件及历史报告继续校验原哈希，certificate AST 边界和全部回归断言保留；root executor、九个必需边界和退出传播语义不变。

已提交的生命周期修复通过 `tests/fixtures/splicore-rc4-lifecycle-fix.json` 对 `src/15-core-state.sh` 校验精确完整哈希；该路径不享有通用豁免。

## Retired legacy acceptance fixtures

旧多 Core 的 `scripts/docker-smoke.sh`、`platform-case.sh`、`platform-smoke.sh` 和 `platform-rootfs-smoke.sh` 保留为历史平台材料，不属于 v4.0.0 执行入口；其 3.x 版本断言不代表当前产品版本。本轮不运行这些入口或操作其目标环境，仅保留全仓 shell 语法与 ShellCheck 检查。

以下 35 个现存入口未计入本轮执行结果。文件作为可复查的旧测试材料保留；
它们不提供旧安装迁移功能。旧 migration-blocker Python/包装测试已移除。

| Historical entry | Classification and current replacement |
|---|---|
| `test_backup_boundary.sh` | 旧多 Core archive/service/恢复 fixture；由 native archive 安全测试、完整 Bash 产品恢复/失败回滚和 native marker 拒绝覆盖。旧服务恢复/tc 清理不再是产品功能。 |
| `test_backup_restore_transaction.sh` | 旧多 Core archive/service/恢复 fixture；由 native archive 安全测试、完整 Bash 产品恢复/失败回滚和 native marker 拒绝覆盖。旧服务恢复/tc 清理不再是产品功能。 |
| `test_direct_3_2_4_upgrade.sh` | 旧 NoBrand 版本原地兼容升级合同取消；由 legacy refusal 和 native future-upgrade/rollback 测试替代。 |
| `test_display_endpoint_domain.sh` | 旧协议 state/export 聚合 fixture；由 native status/redacted plan/client projection、native shell registry、端点单元测试、仓库脱敏和真实新 profile 流量覆盖。 |
| `test_endpoint_isolation.sh` | 旧协议 state/export 聚合 fixture；由 native status/redacted plan/client projection、native shell registry、端点单元测试、仓库脱敏和真实新 profile 流量覆盖。 |
| `test_forward_backend_switch_runtime.sh` | 保留功能的真实 host/network campaign；本轮不运行，host qualification PENDING；当前单元/事务测试仍运行。 |
| `test_forward_nft_runtime.sh` | 保留功能的真实 host/network campaign；本轮不运行，host qualification PENDING；当前单元/事务测试仍运行。 |
| `test_forward_realm_runtime.sh` | 保留功能的真实 host/network campaign；本轮不运行，host qualification PENDING；当前单元/事务测试仍运行。 |
| `test_hy2_certificate.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_hy2_golden.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_ingress_enforcement_runtime.sh` | 保留功能的真实 host/network campaign；本轮不运行，host qualification PENDING；当前单元/事务测试仍运行。 |
| `test_lifecycle_recovery.sh` | 旧多 Core service/实例恢复与卸载合同；由 native transaction/recovery/uninstall、产品 restore rollback、CLI refusal、菜单锁和保留模块事务测试覆盖。 |
| `test_mieru_endpoint_isolation.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_mieru_latest_stable.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_mieru_latest_stable_runtime.sh` | 旧独立 Core 的真实流量 campaign；由公开 rc.4 单 runtime 新装/流量/探测/restart/SIGKILL campaign 替代。 |
| `test_mieru_parity.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_mieru_uninstall_boundary.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_mieru_user_add_endpoint.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_nodes.sh` | 旧协议 state/export 聚合 fixture；由 native status/redacted plan/client projection、native shell registry、端点单元测试、仓库脱敏和真实新 profile 流量覆盖。 |
| `test_rollback.sh` | 旧多 Core service/实例恢复与卸载合同；由 native transaction/recovery/uninstall、产品 restore rollback、CLI refusal、菜单锁和保留模块事务测试覆盖。 |
| `test_runtime_integration.sh` | 旧独立 Core 的真实流量 campaign；由公开 rc.4 单 runtime 新装/流量/探测/restart/SIGKILL campaign 替代。 |
| `test_sensitive_output.sh` | 旧协议 state/export 聚合 fixture；由 native status/redacted plan/client projection、native shell registry、端点单元测试、仓库脱敏和真实新 profile 流量覆盖。 |
| `test_snell.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_snell_quic.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_socks5_udp_reference_runtime.sh` | 旧独立 reference campaign；当前 rc.4 probe 使用同一 SOCKS5 TCP/UDP probe 验证新导出配置。 |
| `test_splicore_rc2_contract.sh` | 历史 rc.2 validator/迁移阻塞合同；由 rc.4 contract + fresh guard/certificate/runtime probe 替代。 |
| `test_ssh_runtime.sh` | 保留功能的真实 host/network campaign；本轮不运行，host qualification PENDING；当前单元/事务测试仍运行。 |
| `test_tuic_runtime.sh` | 旧独立 Core 的真实流量 campaign；由公开 rc.4 单 runtime 新装/流量/探测/restart/SIGKILL campaign 替代。 |
| `test_tuic_transaction.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_tuic_v5.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_uninstall_boundary.sh` | 旧多 Core service/实例恢复与卸载合同；由 native transaction/recovery/uninstall、产品 restore rollback、CLI refusal、菜单锁和保留模块事务测试覆盖。 |
| `test_upgrade_3_0_3_1.sh` | 旧 NoBrand 版本原地兼容升级合同取消；由 legacy refusal 和 native future-upgrade/rollback 测试替代。 |
| `test_vless_reality.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |
| `test_vless_reality_runtime.sh` | 旧独立 Core 的真实流量 campaign；由公开 rc.4 单 runtime 新装/流量/探测/restart/SIGKILL campaign 替代。 |
| `test_vless_reality_transaction.sh` | 旧 Mita/Xray HY2/sing-box/Snell/defender 的配置、证书、客户端或服务 fixture；由 native fresh/transaction/guard/profile 测试替代，不承诺旧字段兼容。 |

## Real public binary campaign

独立入口 `tests/helpers/splicore_rc4_probe.py` 使用公开 rc.4 amd64 资产和 digest 固定的
Mihomo v1.19.30 客户端。生成新的凭据、证书和客户端配置，验证 42 项检查；原始私有
日志不进入仓库。公开脱敏结果见 [runtime evidence](reports/SPLICORE_RC4_FRESH_RUNTIME_PROBE.json)。

```bash
NOBRAND_SPLICORE_PUBLIC_ARTIFACTS=/path/to/public-rc4-assets \
NOBRAND_REFERENCE_MIHOMO_GZIP=/path/to/mihomo-linux-amd64-v1.19.30.gz \
NOBRAND_RUNTIME_EVIDENCE_DIR=/path/to/private-evidence \
bash scripts/test.sh --runtime
```

缓存只替代 HTTPS 传输；production archive/checksum/ELF/binary/version gate 仍真实执行。
下载 trace 限 rc.4 archive 和 SHA256SUMS。验证环境是临时回环进程 supervisor；
真实 systemd、OpenRC 与 arm64 runtime 均不能据此宣称通过；nftables range 未开放，维持 N/A。

## Execution isolation

完整 suite 保持调用者身份。九个必需边界由 canonical root executor 按直接 root、已验证的非交互 sudo、兼容 user namespace 顺序取得权限，重新确认子进程 EUID 并检查清理与 checkout ownership；不可用时失败而不跳过。`NOBRAND_SYSTEM_ROOT` 指向临时目录，避免探测开发机既有 unit。
测试不操作真实 init、账户、网络规则或生产节点。
