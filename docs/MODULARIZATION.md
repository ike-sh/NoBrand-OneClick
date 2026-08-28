# NoBrand-OneClick Source Modularization

`src/` 是唯一开发真源；最终安装器自包含，不在用户机器 source 仓库模块。

```text
00 bootstrap             05 constants            10 dual CLI parser
15 Mieru state/lock      16 Common port          17 Common endpoint
18 nodes/status/backup   20 Mieru platform       21 shared Xray/HY2 platform
22 Snell platform        23 VLESS service        25-55 Mieru engines
56 Snell engine          57 HY2 engine           58 VLESS Sudoku engine
60-70 Mieru runtime      71 Snell exporters      80 lifecycle
85 actions               90 unified/Mieru UI     99 main
```

构建一次写出字节一致的：

```text
install-nobrand.sh
dist/install-nobrand.sh
install-mita.sh
dist/install-mita.sh
```

同一内容根据 `$0` 选择 NoBrand 或 Mieru compatibility parser/menu。

## 分层与边界

```text
bootstrap/constants/parser
          ↓
state + port + endpoint + nodes/backup Common Core
          ↓
Mieru / Snell / shared Xray / HY2 / VLESS-service platform
          ↓
protocol engines / exporters / lifecycle / UI / main
```

Mieru state/schema 不迁移。Common firewall adapter 通过 Bash dynamic scope 切换 ownership/comment 并复用成熟实现。所有协议共用原 Mieru admin lock。Display Endpoint setters 只写 state metadata/client output。

Snell engine 的产品 resolver 只接受 v4/v5。v5 QUIC exposure 由 `quic_proxy_enabled`/`managed_udp`、Common Port registry 和 NoBrand firewall adapter 共同表达；official server config/runtime path 不因 ON/OFF 分叉。唯一识别 historical v6 state 的生产路径是一轮 exact migration：state filename/instance identity 不匹配即 fail closed，只清理历史 TCP ownership，不推断同号 UDP。

HY2 与 VLESS Sudoku 共用 `NOBRAND_XRAY_BIN`，但分别由 `57-hysteria2.sh` 与 `58-vless-sudoku.sh` 管理独立 config/state，并由 platform service functions 运行两个独立 process。`nobrand_upgrade_xray_runtime` 是共享 binary 的唯一事务入口：校验两个现存配置，重启两个此前 active 的服务，任一失败恢复 binary 与两个 state。

VLESS engine 只产生 plain VLESS/TCP + FinalMask Sudoku。`settings.decryption=none` 与 client `encryption=none` 是合法普通字段；engine 不包含 Encryption key generation/state。`vless_sudoku_forbidden_absent` 是 install、doctor、smoke 与测试共同的否定性边界。

构建器拒绝缺 module、module shebang、CR byte 或无结尾 LF；生成后执行 `bash -n` 再原子替换。`--check` 逐字节比较四个产物。
