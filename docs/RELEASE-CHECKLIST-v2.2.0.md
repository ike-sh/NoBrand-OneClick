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
- [ ] mihomo import
- [ ] Official Mieru URI import
- [ ] Official Mieru JSON import
- [ ] Real backup/restore verification
- [ ] Real uninstall ownership verification (three independent cases)
- [ ] Real OpenRC verification
- [ ] IPLC performance A/B recorded (normally non-blocking)
