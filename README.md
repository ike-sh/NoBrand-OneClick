# NoBrand-OneClick

新版以 **Splicore v0.3.0-rc.4** 为普通代理协议的唯一主运行时，NoBrand 负责安装、配置、客户端输出和生命周期管理。当前架构已在本地 Freeze，尚未发布；见[冻结报告](docs/reports/SPLICORE_RC4_FRESH_ARCHITECTURE_FREEZE_REPORT.md)。

当前稳定版本：[v3.2.6](https://github.com/ike-sh/NoBrand-OneClick/releases/tag/v3.2.6)。该已发布版本属于旧架构；本工作区暂时保留管理器版本号 3.2.6，新架构发布版本号将在后续发布准备时确定。

**需要干净安装。旧版 NoBrand 多 Core 安装不支持原地升级、自动迁移或由新版卸载。** 检测到 NoBrand 拥有的旧状态、二进制或服务时，在创建锁、安装依赖、下载和服务操作前拒绝。请使用对应旧版备份客户端信息并卸载，然后新装并导入新生成的客户端配置。第三方独立安装的同名软件不会被当作 NoBrand 资源。

## 当前协议范围

| 协议 / 模式 | 当前实现 | 本轮实际验证 |
|---|---|---|
| Mieru TCP / UDP / BOTH | Splicore；MTU、多路复用、客户端握手模式；默认 traffic off | TCP 新配置流量、重启和 SIGKILL 恢复；UDP/BOTH 配置校验 |
| Snell v4 / v5 | Splicore；v5 服务端按公开合同使用 v4 客户端 wire；QUIC Proxy Mode 不支持 | v5 服务端 TCP/UDP、新配置、重启和恢复 |
| Hysteria2 + Salamander | Splicore；新 CA + 服务器叶证书；独立 auth/obfs secret | TCP/UDP、证书 pin、错误凭据拒绝、重启和恢复 |
| TUIC v5 | Splicore；UUID + password；新 TLS 信任 | TCP/UDP、新配置、重启和恢复 |
| VLESS + TCP + REALITY + Vision | Splicore 原生 Local Tunnel Guard | 新配置流量、安全探针、重启和恢复 |
| VLESS + FinalMask/Sudoku | 项目已有的专用 pinned Xray 例外 | 既有静态/事务测试；不属于普通协议主运行时 |
| SSH Tunnel | 系统 OpenSSH 策略与账号 | 保留原组件，隔离单元/事务测试 |
| Port Forward | Realm / nftables | 保留原组件，隔离单元/事务测试 |

Mieru 流量伪装、低熵、配额、到期、tc 限速及独立 Mita 版本通道不在当前原生界面中；显式请求不支持的配置会报错。HY2 Gecko 为 Core Experimental 能力，端口跳跃为 Core 支持能力，两者均未在 NoBrand 中开放，默认不启用端口范围。

## 安装和管理

使用维护者审核过的本地单文件安装器。本工作区没有发布本轮变更，不要把线上旧版安装器当作新架构。

```bash
sudo bash install-nobrand.sh
# 也可先安装管理命令
sudo bash install-nobrand.sh manager install
sudo nobrand mieru install --user primary --port 31001 --advertise-host entry.example -y
sudo nobrand snell install --name snell --version 5 --port 31002 --advertise-host entry.example -y
sudo nobrand hy2 install --port 31003 --sni tls.example --advertise-host entry.example -y
sudo nobrand tuic install --name tuic --user primary --port 31004 --advertise-host entry.example -y
sudo nobrand vless-reality install --name reality --target www.microsoft.com --port 31005 --advertise-host entry.example -y
```

`entry.example`、端口和 TLS/cover 域名是占位值。监听端口与展示端点分开；`--advertise-auto` 可探测展示地址。REALITY cover 需要可用的 TLS 服务。多个普通协议由一个 `nobrand-splicore` 服务承载；仅在候选校验时短暂启动私有验证进程。

```bash
nobrand status
nobrand doctor
nobrand nodes
nobrand runtime capabilities
nobrand runtime plan
nobrand hy2 show
nobrand vless-reality export --name reality
sudo nobrand runtime restart
sudo nobrand runtime rollback
sudo nobrand backup create /root/nobrand-native.tar.gz
sudo nobrand backup restore /root/nobrand-native.tar.gz
sudo nobrand uninstall
```

客户端导出是显式敏感操作；请私下保存。状态、doctor 和 plan 不输出密码或 REALITY 私钥。备份含私钥、客户端凭据与数据库主密钥，文件权限为 0600。

## TLS 与 REALITY 安全边界

HY2/TUIC 默认生成新的私有 CA 和非 CA 服务器叶证书，校验 SAN、有效期、KeyUsage、serverAuth、链顺序和私钥匹配。CA 签名私钥生成后删除。sing-box 配置携带 CA 并验证主机名；Mihomo 配置带显式叶证书 SHA256 pin。HY2 URI 使用 `insecure=1&pinSHA256=...` 表达私有信任的强制 pin，不能删除 pin 或交给忽略 pin 的客户端。优先导入完整配置。自备证书使用显式 canonical desired state；项目不管理 ACME。

REALITY 目标是一个仅监听回环的原生 guard。guard 只将允许的 cover SNI 放行到固定目标，其后紧跟该 guard 的 reject 规则；HTTP、随机 TCP、畸形 TLS 和缺失 SNI 均拒绝。已认证的 VLESS 代理负载仍是正常代理流量，不继承 cover SNI 白名单；这不是旧 Xray defender/private-IP 防火墙的逐字段等价实现。

## 更新与回滚

旧 NoBrand → 新架构：**不支持原地迁移**。新版只检测并拒绝，不备份、转换或删除旧资源。

新架构 → 未来 Splicore：保留原子 artifact、候选 generation、持久事务和已知可用版本回滚。升级前必须审核新 release manifest；当前仅允许 rc.4，不能任意传入未来版本。相同版本和配置执行校验后 NO-OP。失败的新装恢复到未安装状态，失败的配置更新恢复上一代 Splicore。

## 验证与限制

```bash
bash scripts/build.sh
bash scripts/test.sh
```

完整测试在临时目录运行；普通用户可在可用的 Linux user namespace 中以映射 root 运行 fixture。真实公开 rc.4 二进制的回环资格见[验收报告](docs/reports/SPLICORE_RC4_FRESH_ARCHITECTURE_REPORT.md)。原生 systemd、OpenRC、arm64 运行及 nftables 端口范围资格仍为 PENDING / NOT CERTIFIED；不操作开发机网络规则或生产环境。

- [安装、升级、FAQ 与排查](docs/SPLICORE-MIGRATION.md)
- [公开 rc.4 合同](docs/SPLICORE-RC4-CONTRACT.md)
- [当前架构与模块边界](docs/MODULE-DEPENDENCIES.md)
- [历史迁移报告](docs/reports/SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md)：保留原有 BLOCKED/PENDING 结论，不能当作本轮验收结果。

## License

GPL-3.0。来源与第三方依赖见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
