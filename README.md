# NoBrand-OneClick

全部代理服务统一使用固定的 **Splicore v0.5.0**（`70b09da7d2758e19ba03df9ff9b9e541a669fa29`），支持原生 VLESS Encryption 与 FinalMask/Sudoku，共享一个运行时，无 Xray 服务端依赖。

当前稳定版本：[v4.1.0](https://github.com/ike-sh/NoBrand-OneClick/releases/tag/v4.1.0)。更新内容见 [CHANGELOG](CHANGELOG.md)。

v4.1.0 集成 Splicore v0.5.0；新建 VLESS + Sudoku 默认启用原生 VLESS Encryption，支持完整客户端 JSON 和 JSON 订阅输出。

## 重要升级说明：v3.x → v4.x

**需要干净安装。旧版 NoBrand 多 Core 安装不支持原地升级、自动迁移或由新版直接卸载／转换。**

1. 使用原 3.x 版本保存／导出现有客户端信息。
2. 使用对应旧版本完成卸载。
3. 确认旧 NoBrand-owned runtime、service 和 state 已清理。
4. 使用当前 v4.x 稳定版干净安装。
5. 使用当前 v4.x 稳定版重新生成并导入客户端配置。

检测到 NoBrand 拥有的旧状态、二进制或服务时，新版在创建锁、安装依赖、下载和服务操作前拒绝。第三方独立安装的同名软件不会被当作 NoBrand 资源。

## 当前协议范围

| 协议 / 模式 | 当前实现 |
|---|---|
| Mieru TCP / UDP / BOTH | Splicore；MTU、多路复用、客户端握手模式；默认 traffic off |
| Snell v4 / v5 | Splicore；v5 服务端使用 v4 客户端 wire；QUIC Proxy Mode 不支持 |
| Hysteria2 + Salamander | Splicore；新 CA + 服务器叶证书；独立 auth/obfs secret |
| TUIC v5 | Splicore；UUID + password；独立 TLS 信任 |
| VLESS + TCP + REALITY + Vision | Splicore 原生 Local Tunnel Guard |
| VLESS Encryption + FinalMask/Sudoku | Splicore 原生 TCP；新建默认 mlkem768 + random + 1rtt |
| SSH Tunnel | 系统 OpenSSH 策略与账号 |
| Port Forward | Realm / nftables |

Mieru 流量伪装、低熵、配额、到期、tc 限速及独立 Mita 版本通道不在当前原生界面中；显式请求不支持的配置会报错。HY2 Gecko 为 Core Experimental 能力，端口跳跃为 Core 支持能力，两者均未在 NoBrand 中开放，默认不启用端口范围。

## 安装和管理

下载并校验 v4.1.0 正式安装器：

```bash
curl -fLO https://github.com/ike-sh/NoBrand-OneClick/releases/download/v4.1.0/install-nobrand.sh
curl -fLO https://github.com/ike-sh/NoBrand-OneClick/releases/download/v4.1.0/SHA256SUMS
sha256sum -c SHA256SUMS
sudo bash install-nobrand.sh
```

从源码构建使用 `bash scripts/build.sh`，生成 `install-nobrand.sh` 与 `dist/install-nobrand.sh`。

Alpine Linux 请先安装 `bash` 与 `curl`，然后以 root 身份执行 `bash install-nobrand.sh`。

管理命令与示例配置：

```bash
# 也可先安装管理命令
sudo bash install-nobrand.sh manager install
sudo nobrand mieru install --user primary --port 31001 --advertise-host entry.example -y
sudo nobrand snell install --name snell --version 5 --port 31002 --advertise-host entry.example -y
sudo nobrand hy2 install --port 31003 --sni tls.example --advertise-host entry.example -y
sudo nobrand tuic install --name tuic --user primary --port 31004 --advertise-host entry.example -y
sudo nobrand vless-reality install --name reality --target www.microsoft.com --port 31005 --advertise-host entry.example -y
sudo nobrand vless-sudoku install --port 31006 --advertise-host entry.example -y
```

`entry.example`、端口和 TLS/cover 域名是占位值。监听端口与展示端点分开；`--advertise-auto` 可探测展示地址。REALITY cover 需要可用的 TLS 服务。全部代理协议（含 Sudoku）由一个 `nobrand-splicore` 服务承载；仅在候选校验时短暂启动私有验证进程。

```bash
nobrand status
nobrand doctor
nobrand nodes
nobrand runtime capabilities
nobrand runtime plan
nobrand runtime transactions   # 只读查看两类事务，不启动服务
sudo nobrand runtime recover  # 验证快照后恢复；依据不足则保留现场并报错
nobrand hy2 show
nobrand vless-reality export --name reality
nobrand vless-sudoku show
nobrand vless-sudoku export > sudoku-client.json
nobrand vless-sudoku subscription > sudoku-subscription.json
sudo nobrand runtime restart
sudo nobrand runtime rollback
sudo nobrand backup create /root/nobrand-native.tar.gz
sudo nobrand backup restore /root/nobrand-native.tar.gz
sudo nobrand uninstall
```

客户端导出包含 UUID、Sudoku 密码等连接凭据，请私下保存。Sudoku 的 JSON 导出与订阅采用 Xray 26.10.21 格式，完整保留公开 Encryption 和 FinalMask 参数；无法完整表达的 URI 或其他格式会明确报错。服务端 decryption 通过 Splicore 私有凭据保存，不进入客户端输出。备份含私钥、客户端凭据与数据库主密钥，文件权限为 0600。

## TLS 与 REALITY 安全边界

HY2/TUIC 默认生成新的私有 CA 和非 CA 服务器叶证书，校验 SAN、有效期、KeyUsage、serverAuth、链顺序和私钥匹配。CA 签名私钥生成后删除。sing-box 配置携带 CA 并验证主机名；Mihomo 配置带显式叶证书 SHA256 pin。HY2 URI 使用 `insecure=1&pinSHA256=...` 表达私有信任的强制 pin，不能删除 pin 或交给忽略 pin 的客户端。优先导入完整配置。自备证书使用显式 canonical desired state；项目不管理 ACME。

REALITY 目标是一个仅监听回环的原生 guard。guard 只将允许的 cover SNI 放行到固定目标，其后紧跟该 guard 的 reject 规则；HTTP、随机 TCP、畸形 TLS 和缺失 SNI 均拒绝。已认证的 VLESS 代理负载仍是正常代理流量，不继承 cover SNI 白名单；这不是旧 Xray defender/private-IP 防火墙的逐字段等价实现。

## 更新与回滚

旧 Xray/Mita 等多内核部署 → 新架构：**不支持自动原地迁移**。新版只读检测并拒绝，不转换或删除旧节点、凭据、服务或防火墙。使用匹配的旧安装器导出、备份并处理旧部署；第三方软件不被接管。

已有原生 v0.4.0 安装先用已校验的 v4.1.0 安装器执行 `sudo bash install-nobrand.sh manager upgrade`，再执行 `sudo nobrand vless-sudoku upgrade` 升级到固定 v0.5.0，按原有状态重建独立 SQLite 数据库，保留 UUID、端口、Sudoku 密码和原加密模式。新建节点才默认启用 Encryption。下载按正式 Manifest、SHA256SUMS、包内校验和与二进制身份核对，不使用浮动版本。

升级保留上一代二进制、数据库、密钥和状态用于整代回滚。相同版本和配置校验后不重复部署；失败的新装恢复到未安装状态，失败的更新恢复上一代。未知版本或不支持的配置明确拒绝。

- [安装、升级、FAQ 与排查](docs/SPLICORE-MIGRATION.md)
- [当前架构与模块边界](docs/MODULE-DEPENDENCIES.md)

## License

GPL-3.0。来源与第三方依赖见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
