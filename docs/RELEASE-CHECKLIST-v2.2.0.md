# v2.2.0 Release Checklist

已勾选项表示已通过自动化、容器化或夹具化验证；它们不替代文末列出的真实环境人工验收。

## Build

- [x] `scripts/build.sh`
- [x] Deterministic build
- [x] `install-mita.sh` generated

## Static

- [x] `bash -n`
- [x] ShellCheck
- [x] `git diff --check`

## Functional

以下项目已由 Docker smoke 的自动化生命周期与回归场景验证：

- [x] Fresh install
- [x] Upgrade
- [x] Uninstall
- [x] Endpoint update
- [x] Profile change
- [x] Doctor
- [x] Perf

## Compatibility

以下项目已在无 init 的容器兼容性 smoke 中验证：

- [x] Debian
- [x] Ubuntu
- [x] Rocky Linux
- [x] Alpine

## Migration

以下项目已通过迁移夹具验证：

- [x] v2.0 migration
- [x] v2.1 migration

## Endpoint

以下项目已通过自动化 endpoint 场景验证：

- [x] Default endpoint
- [x] Independent client endpoint

## Ownership

以下项目已通过自动化资源所有权与清理保护场景验证：

- [x] Package ownership
- [x] User ownership
- [x] Group ownership

## Manual verification required

以下真实环境项目仍须人工完成。执行步骤与证据模板见
[`REAL-WORLD-ACCEPTANCE-v2.2.0.md`](REAL-WORLD-ACCEPTANCE-v2.2.0.md)：

- [ ] Real systemd fresh install + default endpoint verification
- [ ] Endpoint-only no-restart/firewall/tc verification
- [ ] Real v2.1.x in-place upgrade verification
- [ ] Real IPLC endpoint verification
- [x] mihomo import and real proxy use (operator-confirmed)
- [x] Official Mieru URI/node-link import and real proxy use (operator-confirmed)
- [ ] Official Mieru JSON import
- [ ] Real backup/restore verification
- [ ] Real uninstall ownership verification (three independent cases)
- [ ] Real OpenRC verification
- [ ] IPLC performance A/B recorded (normally non-blocking)

2026-08-09 收到一次真实 systemd VPS 的终端记录及执行人后续确认：交互安装、isolated-v2 实例、用户增删、`mita perf`、`mita doctor`（`PASS=23 WARN=0 FAIL=0`）和卸载命令均正常完成；独立入口、节点链接和 mihomo 配置已实际用于代理。mihomo 与 URI 项据此勾选。该运行仍缺候选 hash、默认 endpoint、endpoint-only before/after、官方 JSON、IPLC 服务端控制面和 ownership 三阶段证据，其余总项保持未勾选。脱敏分析见 `REAL-WORLD-ACCEPTANCE-v2.2.0.md` §0.4；含凭据的原始终端记录不得提交。
