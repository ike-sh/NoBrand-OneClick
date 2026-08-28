# Contributing to NoBrand-OneClick

NoBrand-OneClick 3.0.0 是 clean-break 架构。所有变更必须同时维护统一产品边界与 Mieru 功能对等。

## 不可破坏的产品契约

- 唯一安装器：`install-nobrand.sh`
- 正式命令：`nobrand`
- 短别名：`nb -> nobrand`
- 唯一权威 state：`/var/lib/nobrand-oneclick/`，且 `schema_version=3`
- 旧 Mieru/NoBrand state 只检测并 fail closed，不读取、不导入、不转换、不删除
- 真正上游 Mieru runtime 可以名为 `mita`，但不得成为管理 wrapper
- Snell 只支持 v4/v5；v1/v2/v3/v6 不得有隐藏入口
- Hysteria2 与 VLESS/Sudoku 的 wire 语义不得重新设计
- 统一卸载只能删除 NoBrand 3 ownership 明确记录的资源

Mieru 是成熟功能基线。Profile、TCP/UDP/BOTH、MTU、Multiplexing、Handshake、Traffic Pattern、Low Entropy、multi-user、isolated-v2、quota、tc、Endpoint、backup 与 exporter 的用户语义和默认值必须保持。任何相关修改都要同步更新 [docs/MIERU-PARITY-3.0.md](docs/MIERU-PARITY-3.0.md) 与 golden fixture。

## 源码与构建

`src/*.sh` 是权威源码，`install-nobrand.sh` 与 `dist/install-nobrand.sh` 是生成物。不要直接编辑生成物。

```bash
bash scripts/build.sh
bash scripts/build.sh --check
```

`scripts/build.sh` 使用显式有序 manifest；新增模块必须加入且只能加入一次。

## 提交前测试

```bash
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/platform-smoke.sh
bash scripts/docker-smoke.sh
git diff --check
```

测试至少需要覆盖：

- Bash syntax 与 ShellCheck warning gate
- Mieru parameter/default/Profile/config/export/Endpoint/port parity
- schema v3 与 legacy fail-closed
- transport-aware allocator 与 xx00 reservation
- Display Endpoint runtime isolation
- Snell v4/v5 与 v5 QUIC ownership
- HY2/VLESS golden config 与真实 Xray 验证
- rollback、backup boundary 与 unified uninstall ownership
- deterministic two-build hash

`--runtime` 需要网络并下载真实 upstream runtime。无法运行时必须写 `NOT RUN` 和原因，不能标为 PASS。

## 安全要求

- 不提交 credential、私钥、真实实验地址或 SSH 配置。
- 不使用 raw main 作为正式安装默认 URL。
- 不关闭 TLS/checksum 校验来绕过下载失败。
- 不 flush firewall，不删除未知规则。
- 不用通配符删除未解析的宽目录。
- 外部 package/user/group/service 必须通过 preexisting ownership marker 保留。
- Display Endpoint 操作不得触发服务重启或改动真实配置、listener、firewall、tc、quota。

历史发布文档可以保留当时的命令与行为作为记录；活跃 README、源码、测试和 CI 必须描述当前 3.0 API。
