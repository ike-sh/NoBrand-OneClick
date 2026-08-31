# Baseline and Verification Record

日期：2026-08-31（Asia/Shanghai）

## 3.1.0 发布资格基线

- 分支：`main`
- 权威基线提交：`2bb6bea47f3fb0f98c4cbced1ca77e1240e1a7c9`
- 基线 tag：`v3.0.0`
- 最终发布候选：`3.1.0`
- 发布目标 tag：`v3.1.0`
- 开发安全快照始终位于被忽略的仓库外发布范围；不属于源码、commit 或 release asset

`v3.0.0` 是升级兼容边界。schema 继续是 `schema_version=3`；TUIC v5、SSH Tunnel 与 Port Forward 都是可选模块，合法的 3.0 state 无需转换即可继续使用。`docs/MIERU-PARITY-3.0.md` 的七项断言必须继续全部 PASS。

## 3.1.0 本地证据

开发过程已经取得以下直接证据；发布门禁仍以所有改动完成后的最终整套重跑为准，不能用较早结果替代最终结果。

- PASS `scripts/test.sh` 完整普通测试
- PASS `scripts/test.sh --runtime`，包括官方 Xray/Surge Snell、sing-box/Mihomo TUIC v5 与真实 OpenSSH forwarding-only runtime
- PASS SSH Tunnel real OpenSSH：`-N/-L/-D/-R`、TCP 字节完整性、shell/exec/TTY/SFTP/SCP/TUN 拒绝、用户隔离、密钥轮换、watchdog、备份恢复与卸载
- PASS TUIC v5 real runtime：sing-box server、sing-box/Mihomo clients、TCP、SOCKS5 UDP 64/512/1200/1400、双用户隔离、凭据轮换、备份恢复与卸载
- PASS Debian、Ubuntu、Rocky、Alpine 官方 rootfs 平台矩阵，包括真实 sshd config/account/reload 路径
- PASS TUIC install/upgrade 与 SSH identity/policy transaction failure injection
- PASS unified restore external-side-effect rollback
- PASS ordinary status/doctor/nodes/menu sensitive-output audit
- PASS repository sanitization：无私钥、TUIC credential bundle、lab infrastructure literal、runtime binary 或 client bundle
- PASS architecture audit：orphan、duplicate 与 accidental override 均为 0
- PASS Port Forward focused state/config/import/export、transaction/backend-switch rollback、sysctl refcount/ownership、Realm runtime/service 与 nftables external-ownership tests
- PASS privileged isolated-network real backend switch：nftables TCP/UDP/BOTH → official Realm TCP/UDP/BOTH → nftables，并证明失败 Realm candidate 不改变 authoritative state、旧 nft table 或活动数据面
- PASS warning-level ShellCheck after the Forward ownership and candidate-probe changes

加入 Forward 及最终 auto Display Endpoint 修复后，完整候选重新通过 build/check、Bash syntax、warning-level ShellCheck、完整普通测试、统一 runtime、独立 nftables namespace、真实 official Realm 与双向 backend switch、Debian/Ubuntu/Rocky/Alpine container/rootfs matrices、legacy Docker smoke、七项 Mieru parity、diff/sanitization/sensitive-output/architecture/security 审计。连续构建的 root/dist 结果逐字节一致：每份 768316 bytes，SHA-256 均为 `9c320c931edbfa7ca2e3085630e31f63c94a83dfb173ca3152a47a1a09872d6d`。当前证据支持 `LOCAL_TEST_GATE=PASS`。

## 3.1.0 真机资格

授权 SSH helper 的正常用户连接路径已经通过严格 pinned Host Key 检查、既有加密密钥认证和全新管理员连接验收；没有关闭 Host Key 校验、读取或发布 helper trust store，也没有修改服务器 Host Key、sshd Host Key 或管理员私钥。

真机资格完整覆盖 3.0→3.1 状态与既有协议保留、root-only production backup、SSH Tunnel SOCKS5 与管理员访问、TUIC 双客户端 TCP/UDP、nftables/Realm 双后端真实数据面、nftables→Realm→nftables 切换、失败 rollback、统一 backup/restore/uninstall、外部资源保留、fresh 3.1 reinstall 和最终 production-style 状态。最终结果为 `REAL_MACHINE_GATE=PASS`；Snell v5 QUIC 保持 OFF，且不把普通 UDP 行为表述为官方 QUIC wire E2E。

## 历史开发记录

早期 Windows `bash.exe` 是没有发行版的 WSL 入口（`execvpe(/bin/bash) failed`），当时测试使用 Docker Linux，并只读挂载 source repo。当前 3.1 验收使用可工作的 Ubuntu WSL、user/root mount namespace 与官方平台 rootfs fallback。

## 开工前 Mieru baseline

- PASS build `--check`、全部 syntax、Docker `SMOKE_OK`
- PASS Debian、Ubuntu、Rocky、Alpine compatibility
- 既有 ShellCheck SC2120：`profile_label` optional argument

## 开工前 Xray-OneClick baseline

参考项目原 `tests/run_all.sh` 的模块、syntax、ShellCheck、config、regressions、HY2 删除回滚、endpoint/security/binary rollback 通过。环境没有真实 Xray，明确输出 `[SKIP] 未找到可执行 xray，跳过 xray run -test`；该项不是 PASS。

NoBrand 后续单独下载官方 Xray 执行真实 `run -test`，并真实启动 Surge Snell v4/v5/v6 localhost listener。

## 第二阶段改动前保护与 baseline

- 权威第一阶段 HEAD：`2bb6bea47f3fb0f98c4cbced1ca77e1240e1a7c9`
- 未提交工作树安全快照：仓库发布范围之外并由 `.gitignore` 排除，不公开本机路径或内容
- 快照内容：baseline patch/metadata、src/scripts/tests/docs/CI、README/license/notices 与四份生成 installer
- 改生产代码前：Debian 12 runtime、build/check、syntax、warning ShellCheck、全部第一阶段 unit、Xray HY2 config、Snell v4/v5/v6 listener、Mieru Docker smoke、Debian/Ubuntu/Rocky/Alpine compatibility 全部 PASS；Alpine real-runtime 按设计 SKIP

禁止用 reset/clean/restore 覆盖这份 working-tree baseline。参考 worktree 与 SSH helper 配置均保持只读。

## 第二阶段本地验证记录

- PASS Debian 12 `scripts/test.sh`
- PASS Debian 12 `scripts/test.sh --runtime`
- PASS Xray-core 26.3.27 HY2 `run -test`
- PASS Xray-core 26.3.27 Plain VLESS FinalMask/Sudoku server/client `run -test`
- PASS Xray-core 26.3.27 localhost VLESS FinalMask/Sudoku TCP data plane
- PASS Surge Snell v4.1.1/v5.0.1/v6.0.0rc2 official localhost listeners
- PASS VLESS canonical golden、Encryption absence、lifecycle/idempotency/endpoint/remove/rollback、shared Xray rollback、menu mapping

容器兼容、Mieru smoke、静态审计与真机结果仍以最终当次记录为准，不从第一阶段结果推断 PASS。

## 常用本地验证命令

```bash
bash scripts/build.sh
bash scripts/build.sh --check
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
bash scripts/platform-rootfs-smoke.sh
```

覆盖 Common port/transport、legacy Mieru adapter、Endpoint isolation、HY2 JSON/URI/cert、VLESS golden/Encryption absence/client/server/data plane、Snell resolver/config/state/export/service/no-Mihomo-v6、TUIC v5 server/runtime/export/transaction、SSH Tunnel policy/identity/runtime/transaction、Port Forward nftables/Realm state/config/ownership/transactions/real data plane、nodes/Stopped、backup boundary、CLI/menu、config/port/state/firewall/service/binary rollback。最终结果以当次 log/交付报告为准；不能把未运行项计为 PASS。
