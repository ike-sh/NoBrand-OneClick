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

顶层 parser 路由到 Mieru、Snell、Hysteria2、VLESS/Sudoku 与 Common Core。`nb` 不包含可执行逻辑。上游 Mieru runtime 位于 `/usr/local/lib/nobrand-oneclick/bin/mita`，不在 public management API 中。

## Module responsibilities

- `00-bootstrap` / `05-constants` / `10-cli-prelude`：启动、常量与统一 parser
- `15-18-core-*`：schema v3、port、Endpoint、nodes、backup/uninstall common core
- `20-23-platform-*`：官方 runtime 下载、校验、安装与平台 service adapter
- `25-network-mtu`：Mieru MTU 策略
- `30-55`：Mieru isolated-v2、多用户、quota/tc、diagnostics、Profile 与 config builder
- `56-58`：Snell、Hysteria2、VLESS/Sudoku 产品逻辑
- `60-70`：Mieru daemon/firewall、BBR/FQ、client export 与 lifecycle
- `71-snell-export`：Surge/Mihomo/sing-box exporter
- `80-99`：lifecycle、status、UI 与统一 main dispatcher

## State boundary

`/var/lib/nobrand-oneclick/state.json` 是根 ownership marker。根目录存在但 marker 不是 exact schema v3，或检测到旧 Mieru state 时，除 help/version 外都 fail closed。模块不能添加 migration adapter、旧 client credential fallback 或 wrapper routing。

Mieru production state 位于根目录下的 `mieru/`；`/etc/mita` 只用于上游 runtime 真正需要的 per-instance 配置和 metrics，不是 NoBrand 权威 state。

## Build invariants

- manifest 明确、完整、无重复
- module 不带 shebang、CR 字节，并以 LF 结束
- 生成物必须通过 `bash -n`
- root/dist 内容必须 byte-identical
- `--check` 不写文件，只验证生成物是否陈旧
- 任何源码变化后都必须重新生成两个 artifact
