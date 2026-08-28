# Baseline and Verification Record

日期：2026-08-27

Windows `bash.exe` 是没有发行版的 WSL 入口（`execvpe(/bin/bash) failed`），因此测试使用 Docker Linux，并只读挂载 source repo。

## 开工前 Mieru baseline

- PASS build `--check`、全部 syntax、Docker `SMOKE_OK`
- PASS Debian、Ubuntu、Rocky、Alpine compatibility
- 既有 ShellCheck SC2120：`profile_label` optional argument

## 开工前 Xray-OneClick baseline

参考项目原 `tests/run_all.sh` 的模块、syntax、ShellCheck、config、regressions、HY2 删除回滚、endpoint/security/binary rollback 通过。环境没有真实 Xray，明确输出 `[SKIP] 未找到可执行 xray，跳过 xray run -test`；该项不是 PASS。

NoBrand 后续单独下载官方 Xray 执行真实 `run -test`，并真实启动 Surge Snell v4/v5/v6 localhost listener。

## 第二阶段改动前保护与 baseline

- 权威第一阶段 HEAD：`<BASELINE_COMMIT>`
- 未提交工作树完整快照：`<LOCAL_SAFETY_SNAPSHOT>`（被 `.gitignore` 排除）
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

## NoBrand commands

```bash
bash scripts/build.sh
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
```

覆盖 Common port/transport、legacy Mieru adapter、Endpoint isolation、HY2 JSON/URI/cert、VLESS golden/Encryption absence/client/server/data plane、Snell resolver/config/state/export/service/no-Mihomo-v6、nodes/Stopped、backup boundary、CLI/menu、config/port/state/firewall/service/binary rollback。最终结果以当次 log/交付报告为准；不能把未运行项计为 PASS。
