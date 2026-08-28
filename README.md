# NoBrand-OneClick

多协议菜单式一键部署与管理脚本。

Author: **ike**
Current Version: **1.3.0**

NoBrand-OneClick 面向 VPS、IPLC、NAT、四层转发和特殊 TCP/UDP 网络环境，统一提供安装、服务管理、节点展示、客户端导出、Endpoint 管理、Doctor 与 Backup/Restore。

## 支持协议

| 协议 | 状态 | 说明 |
|---|---|---|
| Mieru | Supported | 多用户、每用户独立实例 |
| Snell v5 | Recommended | Stable / Default；可选 QUIC 公网暴露 |
| Snell v4 | Compatibility | 兼容用途 |
| Hysteria2 | Supported | Xray-core Hysteria2 |
| VLESS + FinalMask + Sudoku | Supported | TCP / Xray-core |

> Snell v1、v2、v3、v6 不受支持，也没有隐藏兼容开关。

Snell v6 曾进行实际兼容性验证，但没有达到本项目的稳定性要求，因此自 1.3.0 起移除。

## 主要特性

- 统一菜单与 CLI：安装、查看、启停、重启、升级、删除。
- 统一节点视图、状态检查和 Doctor。
- Real Endpoint 与 Display Endpoint 分离。
- TCP 与 UDP 端口分别登记和管理 ownership。
- 按项目边界执行配置、状态、防火墙和服务回滚。
- 按客户端能力生成协议对应的分享链接或配置。

Mieru 保留多用户、每用户独立实例、独立端口、TCP/UDP/BOTH、Profile、MTU、quota、tc、backup、client export 与 custom Display Endpoint。

Hysteria2 使用 Xray-core，传输为 UDP，采用 self-signed TLS、ALPN h3 与 Salamander obfs。

VLESS + FinalMask + Sudoku 使用 Xray-core 和 TCP，FinalMask mode 为 Sudoku；**VLESS Encryption is NOT used.**

## 系统要求

- Debian / Ubuntu、Rocky / RHEL 系或 Alpine Linux
- amd64 或 arm64
- root 权限
- Bash、curl 和系统包管理器

不同协议仍受上游 runtime 的系统与架构支持范围约束。安装后建议运行 `nobrand doctor`。

## 安装

固定版本 URL：

```text
https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/v1.3.0/install-nobrand.sh
```

进入 root shell 后直接运行：

```bash
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/v1.3.0/install-nobrand.sh)
```

也可以先下载：

```bash
curl -fL -o install-nobrand.sh \
  https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/v1.3.0/install-nobrand.sh
chmod +x install-nobrand.sh
sudo ./install-nobrand.sh
```

安装后提供 `nobrand` 与 `nb`；Mieru compatibility 入口 `mita` 与 `install-mita` 继续保留。

## 基本使用

先查看当前真实帮助：

```bash
nobrand --help
```

常用命令：

```bash
nobrand
nb
nobrand status
nobrand nodes
nobrand doctor
```

协议入口：

```bash
nobrand mieru
nobrand snell
nobrand hy2
nobrand vless-sudoku
```

非交互安装需要明确提供 Display Endpoint，或显式使用 `--advertise-auto`：

```bash
nobrand snell install \
  --name example-node \
  --version 5 \
  --port <SERVER_PORT> \
  --quic off \
  --advertise-host <CLIENT_ENTRY_HOST> \
  --advertise-port <CLIENT_ENTRY_PORT> \
  -y
```

## 客户端展示入口

```text
Real Endpoint                  Display Endpoint
    ↓                              ↓
服务端真实监听                  客户端看到的入口

0.0.0.0:<SERVER_PORT>          <CLIENT_ENTRY_HOST>:<CLIENT_ENTRY_PORT>
```

修改 Display Endpoint 不会修改 listener、service、firewall listener port、tc 或 quota；它只影响节点展示、分享链接和客户端配置。

Snell 示例：

```bash
nobrand snell set-endpoint \
  --name example-node \
  --advertise-host <CLIENT_ENTRY_HOST> \
  --advertise-port <CLIENT_ENTRY_PORT>
```

HY2 和 VLESS/Sudoku 分别使用 `nobrand hy2 set-endpoint` 与 `nobrand vless-sudoku set-endpoint`。

## 端口分配

默认路由 IPv4 尾号记为 `xx`：

```text
xx00       保留
xx01-xx99  自动端口池
```

抽象示例：

```text
尾号为 36
→ 3600 保留
→ 3601-3699 自动选择
```

`TCP/P` 与 `UDP/P` 独立判断。TCP 端口 `P` 被占用，不代表 `UDP/P` 一定被占用；协议启用哪一种 transport，就登记和管理对应 ownership。

## 节点展示

`nobrand nodes` 提供统一视图，形式类似：

```text
Protocol        Endpoint
Mieru           <HOST>:<PORT>
Snell v5        <HOST>:<PORT>
Hysteria2       <HOST>:<PORT>
VLESS/Sudoku    <HOST>:<PORT>
```

分享链接和客户端配置可能包含连接凭据，应按敏感文件管理。

## 客户端导出

| 协议 | 当前导出 |
|---|---|
| Mieru | `mierus://`、Mieru JSON、Mihomo 配置片段 |
| Snell | Surge、Mihomo、sing-box |
| Hysteria2 | `hysteria2://`、Mihomo、sing-box |
| VLESS + FinalMask + Sudoku | VLESS URL、Xray client JSON |

Snell 导出会按服务端版本与客户端能力生成。sing-box 对普通 Snell v5 使用其当前支持的兼容 wire 表达，不代表官方 QUIC Proxy Mode 支持。

## Snell v5 QUIC

Snell v5 是 Stable / Recommended / Default。QUIC exposure 可选 ON/OFF，默认 **OFF**。

开启后 NoBrand 会管理同号 UDP 公网暴露及对应防火墙 ownership。

官方 Snell v5 server 本身可能存在同号 UDP socket；本地 UDP socket 的存在不等同于 NoBrand 已开放 QUIC 公网入口。

- Mihomo：普通 Snell v5 已验证；官方 QUIC Proxy wire 尚未作为已验证能力声明。
- sing-box：普通 Snell v5 已验证；不支持官方 Snell v5 QUIC Proxy Mode。

## 客户端兼容性

| 协议 | Mihomo | sing-box | Reference |
|---|---:|---:|---|
| Mieru | ✅ | — | Mieru |
| Snell v4 | ✅ | ✅ | — |
| Snell v5 | ✅ | ✅ | — |
| Hysteria2 | ✅ | ✅ | Xray-core |
| VLESS/Sudoku | — | — | Xray-core |

`—` 表示当前未提供或未声明该客户端兼容性，不表示协议本身不可用。

## 文件与服务

```text
/etc/nobrand-oneclick/          NoBrand 配置
/var/lib/nobrand-oneclick/      NoBrand 状态与备份
/usr/local/lib/nobrand-oneclick/ NoBrand runtime 与辅助文件
/etc/mita/                      Mieru 配置
/var/lib/mita-oneclick/         Mieru 管理状态
```

systemd 服务名：

```text
nobrand-snell@<INSTANCE_ID>.service
nobrand-hysteria2.service
nobrand-vless-sudoku.service
mita-oneclick@<USER_ID>.service
```

Alpine 使用对应的 OpenRC service。

## 更新

进入 `nobrand` 菜单并选择 Upgrade，或运行：

```bash
nobrand mieru upgrade
nobrand snell upgrade
nobrand hy2 upgrade
nobrand vless-sudoku upgrade
```

从旧版本升级时，NoBrand 会清理身份匹配的旧 Snell v6 管理资源。

## 备份与恢复

```bash
nobrand backup create
nobrand backup list
nobrand backup restore <BACKUP_FILE>
```

NoBrand backup 覆盖 Common registry 以及 Snell、HY2、VLESS/Sudoku 的项目管理状态与配置。Mieru 用户和实例备份由 Mieru 子菜单管理。

## Doctor

```bash
nobrand doctor
```

Doctor 检查 runtime、service、listener、firewall 和 config/state，默认不输出连接凭据。

## 已知限制

- Snell 仅支持 v4/v5；v1/v2/v3/v6 不受支持。
- Snell v5 QUIC 默认关闭。
- Mihomo 的官方 Snell v5 QUIC wire 未声明为已验证。
- sing-box 不支持官方 Snell v5 QUIC Proxy Mode。
- VLESS/Sudoku 当前以 Xray-core 作为参考客户端。

项目经过本地、容器和真实客户端数据面验证。详细开发资料位于 `docs/`；历史实验结论不构成对所有网络环境的性能保证。

## 卸载

```bash
nobrand uninstall
```

该命令只删除 NoBrand 管理的 Snell、Hysteria2、VLESS/Sudoku 与 Common 资源，不会顺带删除 Mieru。Mieru 可从 `nobrand mieru` 子菜单单独管理。

## Project Structure

```text
src/      模块化源码
scripts/  构建与检查脚本
tests/    自动化测试
docs/     设计与历史文档
```

模块关系见 `docs/MODULARIZATION.md` 与 `docs/MODULE-DEPENDENCIES.md`。

## License

NoBrand-OneClick 以 GPL-3.0 发布，详见 `LICENSE`。

Mieru MIT attribution、Xray-core、Xray-OneClick-derived logic 与 Surge Snell Server 等第三方说明见 `THIRD_PARTY_NOTICES.md`。
