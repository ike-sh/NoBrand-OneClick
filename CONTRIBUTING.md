# Development Workflow

## 修改代码

开发源码位于 `src/`。请修改对应的 `src/*.sh` 模块，不要直接修改生成产物 `install-mita.sh`。

## Build

修改源码后执行：

```bash
bash scripts/build.sh
```

该命令会重新生成发布脚本；提交前应确保生成产物与源码同步。

## Test

至少执行：

```bash
bash -n install-mita.sh
shellcheck install-mita.sh
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
```

## Commit 内容

按变更范围提交以下内容：

- `src/`
- `install-mita.sh`
- `dist/install-mita.sh`
- `scripts/`
- `docs/`

README、CHANGELOG 或贡献指南有变化时一并提交对应文件。

提交前再次运行构建，确保生成产物已同步。

## 禁止事项

- 不要修改 `install-mita.sh` 而不同步 `src/`。
- 不要修改 state schema 却不提供对应 migration。
- 不要在没有测试覆盖时修改用户配置行为。
- 不要破坏客户端 endpoint 与 backend 监听地址的分离逻辑。
