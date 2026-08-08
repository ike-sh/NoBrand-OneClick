# mieru-OneClick

基于 [enfein/mieru](https://github.com/enfein/mieru) 的 **mita 服务端**一键安装脚本，支持：

- **Debian / Ubuntu**（deb）
- **CentOS / RHEL / Rocky**（rpm）
- **Alpine Linux**（官方 tar.gz + OpenRC/systemd）

## 一键安装

**Debian / Ubuntu / CentOS / RHEL 等**（需 sudo）：

```sh
curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash
```

**Alpine Linux**（默认无 `sudo`，且需先安装 `bash`）：

```sh
apk add --no-cache bash curl && \
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash
```

> Alpine 容器内通常已是 root，**不要**加 `sudo`；脚本本身会 `apk add` 其余依赖（tar、iptables 等）。

运行后按菜单选择「安装 / 配置」，脚本将：

1. 默认从 GitHub Releases 下载项目测试过的 stable `mita`；也可显式选择 upstream latest 或精确版本
2. 自动生成随机用户名、密码；**询问端口时默认按本机内网 IP 尾号推导**，并选择 Profile
3. 始终询问“客户端连接入口地址/端口”；探测公网 IP 与真实监听端口只作为建议值
4. 应用配置并启动服务
5. 尝试放行防火墙（ufw / firewalld / Alpine iptables）
6. 安装完成**同时输出** `mierus://` 节点链接、客户端 JSON 保存路径、**Clash/mihomo 片段**及连接信息摘要
7. 下载包 **SHA256 校验**；提示云安全组放行端口

安装结束时会检测系统当前的 TCP BBR 与 FQ 状态：两者均已启用时直接跳过；缺少任一项时询问是否使用本地 sysctl 配置启用，回车默认执行，不下载或运行远程 BBR 脚本。

安装过程中必须确认“客户端连接入口”地址和端口，支持 IPv4、IPv6 与域名，适用于 IPLC、NAT、端口映射或前置入口。该入口只写入节点链接、客户端 JSON、Clash/mihomo 配置和摘要，不修改 mita 实际监听端口、防火墙规则或 `tc` 限速；填写错误只会导致导出的客户端配置不可用，不影响服务端运行。

### v2.2.0 性能、Profile 与诊断

- 增加「IPLC / 专线性能」「普通公网」「强化伪装」「高级自定义」Profile；内部键仍为 `iplc|balanced|stealth|custom`，state 始终保存完整真实参数
- v2.0/v2.1 state 缺少 `PROFILE` 时只按现有参数精确反推；不匹配即 `custom`，迁移绝不覆盖旧参数
- 安装始终询问客户端入口地址与端口；非交互安装必须显式给出入口，或使用 `--advertise-auto` 确认自动模式
- `advertise_host` 支持 IPv4、IPv6 与域名；官方客户端 JSON 对域名使用 `domainName`，服务端 listener/firewall/tc 继续只使用后端端口
- 新增只读 `mita perf`，报告 Profile、Mieru、内核、网络、endpoint、资源与 tc；自定义展示入口只作为合法信息提示
- 新增 `stable` / `latest` / 精确版本通道。新安装默认 stable；旧 state 缺少通道时继续 latest，保持旧升级语义
- 重组主菜单并保留全部原有 CLI；修正 Traffic Pattern 与 Low Entropy 的性能/开销文案
- 新增导出 golden、v2.0/v2.1 migration、perf 只读、Debian 生命周期与 Debian/Ubuntu/Rocky/Alpine 兼容测试

### v2.1.4 用户管理与状态输出修复

- 用户管理中的操作失败会留在用户管理菜单，并显示对应操作阶段，不再误报“权限检查”或直接返回主菜单
- 删除最后一个用户改为业务警告；用户列表完整显示 `unlimited` 套餐与配额
- 专属实例启动、重启结果不再重复输出；doctor 在零警告时显示简洁的“验收通过”

### v2.1.3 软件包服务启动保护修复

- 修复 v2.1.2 使用 runtime mask 后，官方 deb/rpm 安装脚本执行 `systemctl enable mita.service` 失败、导致软件包停在半配置状态的问题
- 安装期间改用临时 `systemctl` 代理，仅阻止官方包启用或启动默认 `mita.service`，其它 systemd 操作正常执行；首次安装仍直接进入 isolated-v2
- 升级前若旧默认服务正在运行，软件包处理完成后恢复其运行状态；专属实例部署不会误启动默认服务
- Debian 半安装状态执行 `dpkg --configure -a` 时复用同一保护逻辑，重新运行安装即可自动完成修复

### v2.1.2 状态脱敏与直接专属实例安装

- 主用户名变更时清理旧用户名导出；协议、MTU、流量伪装、低熵、握手或多路复用等全局参数变化时统一失效全部旧客户端 JSON，避免多用户读取过期配置
- 状态页不再输出包含密码的原始服务端 JSON；重配置页隐藏当前密码并使用无回显密码输入
- 重配置结果明确区分“无变化”“仅客户端参数变化”和“服务端配置变化”，摘要不再误显示“安装完成”
- doctor 在没有限速用户时将缺少 `clsact`/filter 视为正常；有限速用户缺少规则时改为失败
- 软件包安装期间临时屏蔽默认 `mita.service`，首次安装直接创建 isolated-v2 专属实例，不再先启动旧单实例再迁移
- 清理终端文本中的 Markdown 强调标记，并补充导出失效、状态脱敏、doctor 和首次安装回归测试

### v2.1.1 客户端导出与卸载输出修复

- 客户端 JSON 改为稳定路径 `/root/mieru-clients/current/<用户>_<协议>.json`，连续查看时原子覆盖；删除用户或恢复备份后同步清理失效导出，不再累积含明文凭据的时间戳文件
- JSON 导入提示不再使用可能展开成多个文件的服务器通配符；明确要求先下载文件，再在客户端使用本地路径导入
- 凭据恢复优先读取受保护的 `users.json`；仅在权威状态不可用时读取最新的有效客户端导出，避免恢复旧密码
- 自定义入口摘要增加“前置入口 -> 后端公网 IP/真实监听端口”映射，便于配置 IPLC 或四层转发
- isolated-v2 卸载不再调用已经停用的默认 mita daemon，消除成功卸载过程中的误导性报错

### v2.1.0 本地 BBR/FQ 与客户端展示入口

- BBR + FQ 改为本地检测和 sysctl 配置，不再下载并执行远程 Python；两者已启用时直接跳过，缺项时回车默认启用，失败自动恢复原配置
- 安装交互支持自定义客户端展示入口 IP 和端口，节点链接、客户端 JSON、Clash/mihomo 与摘要使用该入口
- 展示入口与 mita 实际监听完全分离，不参与端口占用、防火墙或 `tc`；普通 VPS 默认继续自动探测公网 IP
- 自定义入口随用户状态持久化，`show`、用户查看、批量导出、备份恢复和升级后继续生效
- OneClick 管理状态迁移到仅 root 可访问的 `/var/lib/mita-oneclick/`；`/etc/mita/` 只保留官方守护进程数据和专属实例配置
- 可用 `user-set-endpoint` 单独修改某个用户的展示入口；只更新状态和客户端产物，不重启服务端实例
- 卸载只恢复本脚本实际接管的 BBR/FQ 文件；接管后的文件若被人工修改，脚本会拒绝删除或覆盖

### v2.0.4 菜单返回修复

- 用户管理选择 `17) 返回主菜单` 后立即显示主菜单，不再多要求一次回车
- 用户管理执行其它操作后的暂停提示改为“返回用户管理菜单”，避免层级文案误导

### v2.0.3 安装端口修复

- IP 尾号段默认端口改为随机起点遍历，只返回与 TCP/UDP/双协议实际监听需求匹配的空闲端口
- 用户手填端口在下载前立即验占用并显示 `ss` 监听详情；自动端口在配置落盘前二次验收，被抢占时自动更换
- 修复软件包已安装、但上次安装在保存 OneClick 状态前中断时无法自愈的问题；再次选择安装会进入修复安装并重新生成配置
- 端口探测不再依赖不兼容的 `grep \s`，兼容 IPv4、IPv6、`ss`、`netstat` 及 Python bind 回退

### v2.0.2 卸载交互修复

- 修复无专属实例时 `pipefail`/ERR trap 误报“清理防火墙规则失败”
- 卸载按停止服务、防火墙、软件包、文件账号、最终验收分阶段执行；存在真实残留时不再宣称“完全卸载”
- 支持清理安装中断后的 OneClick 残留，并补充软件包、进程、systemd、账号及防火墙规则验收
- 不再安装重复的 `/etc/profile.d` `mita()` 函数；旧终端若仍缓存该函数，卸载完成后会显示明确清理命令

### v2.0.1 首次迁移修复

- 修复 `/etc/mita/instances` 为 `root:root 0750` 时服务用户无法穿越父目录、导致首次专属实例启动失败
- 回滚快照改为幂等，消除首次迁移失败后的重复“用户状态回滚失败”误报
- 专属实例启动、RPC `start` 或 RUNNING 验收失败时自动输出对应 systemd/OpenRC 日志尾部

### v2.0.0 用户专属实例模型

- `users.json` 是管理面的权威状态；每个启用账号运行一个独立 mita 实例，并拥有稳定 `instance_id`、单用户配置、专属监听端口、UDS 和 `metrics.pb`
- 端口、凭据和配额统计现在是真正的用户隔离边界；改端口或改用户名不会改变 `instance_id`，也不会丢失累计用量
- 旧单实例安装在下一次安装、升级或用户变更时事务迁移；迁移失败会停止新实例并恢复旧服务
- `calendar` 只清空到期用户自己的 metrics；不再清零其它 rolling/calendar 用户，失败会恢复 metrics 与 `users.json`
- `--bandwidth` 重新支持正整数 Mbps；通过专属端口实施 IPv4/IPv6 双向 police。脚本只维护自己记录的 filter，不删除或替换现有 root/ingress qdisc
- 全部账号可同时到期并进入“零运行实例”状态，不会为了保留最后一个实例而让过期账号继续可用；手工停用仍保护最后一个启用账号
- 删除采用两阶段提交：实例先停、metrics 暂存，只有用户事务与安装状态均成功后才清理；失败会恢复账号和累计用量
- 重新配置先验收新实例、再变更防火墙；菜单目标账号与 `YES` 状态不再被全局状态覆盖或泄漏
- `doctor` 逐实例检查服务、UDS、单用户配置、专属 binding、metrics API/目录、tc 与防火墙所有权清单
- 下载包 checksum 改为 fail-closed；iptables 同时维护 IPv4/IPv6；本地防火墙只撤销脚本实际新增的规则；公网 IP 探测不再回退为不可用的私网地址
- 重装保留现有用户/节点配置；升级或重装会重启专属守护进程，确保实际运行新二进制和新 unit/runner
- 菜单动作在严格子 shell 中执行；`--dry-run` 在任何服务修复和写操作之前返回

### v1.9.6 MTU 策略与在线调整

- 安装和重新配置时询问 MTU：安全默认 `1400`、自动优化或自定义 `1280-1500`
- 自动模式下 TCP 保持 `1400`；UDP / BOTH 根据默认出口网卡链路 MTU 扣除 IPv4/IPv6 开销，结果限制在 `1280-1400`
- MTU 不与 multiplexing、handshake mode 或 traffic-pattern 绑定；TCP 使用大于 `1400` 通常没有明显收益
- 主菜单新增「调整 MTU」，也可运行 `mita mtu` 或 `install-mita --mtu-config --mtu auto`
- 调整后重新应用服务端配置、重启并验收；失败自动尝试回滚，成功后立即输出带新 MTU 的节点链接与 mieru JSON
- mihomo 当前节点字段没有独立 MTU 参数，因此自动策略封顶 `1400`；自定义 `1401-1500` 仅建议用于能同步相同 MTU 的官方 mieru 客户端

### v1.9.5 低熵模式与可靠性修复

- 对 mita v3.35.0+ 增加显式低熵模式选择，默认关闭，推荐按需使用 `LOW_ENTROPY_MODE_56`
- 支持 `off / 56 / 48 / 40 / 32`，并显示对应流量开销；可用 `--low-entropy` 非交互配置
- 即使流量伪装选择“激进”，也会显式写入低熵模式，避免 `unlockAll` 随机启用高开销模式
- 启用低熵时明确提示客户端兼容风险；mihomo 尚未适配的版本请保持关闭
- 修正 `mierus://` simple URL：服务器地址不再重复端口，`port` / `protocol` 仅在 query 中成对输出；兼容 IPv6
- 客户端 JSON、Clash/mihomo YAML 对账号、密码和地址做安全转义，并保留所选 `traffic-pattern`
- 用户写操作、恢复、到期扫描和日历配额重置增加事务回滚

### v1.9.4 客户端模式与分享配置

- 安装和重新配置时可选择 multiplexing 与 handshake mode；推荐默认值为 `MULTIPLEXING_OFF` / `HANDSHAKE_NO_WAIT`
- `traffic-pattern` 可明确选择加入或不加入；加入后可选择保守或激进模式
- `mierus://` 分享链接、客户端 JSON 与 Clash/mihomo 片段同步输出所选客户端模式和 `traffic-pattern`
- Docker 冒烟测试增加客户端模式、分享链接与 Windows Git Bash 挂载兼容性验证

### v1.9.1 二次审计修复

- reconfigure 主用户：`_U_PRIMARY` 正确传入（按 install-state 用户名定位）
- `/etc/mita` 恢复为 **mita:mita 750**（守护进程可写）；敏感 JSON 仍 600
- calendar password 半失败时 re-apply 干净密码；commit 仅 stamp pending 用户
- 裸参数：`user-restore|import|export|export-clients PATH`；`help` 退出码 0
- 年月/日期与 calendar 统一本地时区；`users_all_ports` 正确识别 BOTH

### v1.9.0 中优先级补齐

- **写路径 admin 锁**：user-add/del/set-*/enable/disable/restore 与 apply/scan 互斥
- **`mita` / `mita-menu` / profile** 转发用户管理与 doctor 子命令
- **reconfigure 多用户**：主用户 + 全局协议；端口/用户名冲突检测
- **BOTH + IPv6**：UDP+1 出口/入口 filter 补齐

### v1.8.1 审计修复

- 修复菜单下 `user-scan` / `rate-restore` 无用户时 `exit` 整进程退出
- 修复 `apply_users_config` 失败时管理锁泄漏
- 裸子命令支持 `user-del bob` 等
- calendar 仅在 apply **成功后**写入 `last_quota_reset`
- `user-quota-reset` 仅 `-y` 时强制

### v1.8.0 运维优化

- **`doctor` / `verify`**：一键检查 root、mita、用户状态、tc、timer/cron、权限
- **用量**：`user-usage` 调用 `mita get users` / `mita get quotas`
- **批量导出客户端**：`user-export-clients [DIR]`
- **管理锁**可重入；敏感文件 600；logrotate
- 历史版本曾提供 `QUOTA_RESET_METHOD=password|days|metrics`（`password/days` 已在 v1.9.7 禁用）
- 历史版本的单实例按端口 tc 限速在 v1.9.7 禁用；v2.0.0 以专属实例模型安全恢复

### v1.7.0 日历月配额 + 双向限速（旧单实例实现）

- **配额模式** `--quota-mode rolling|calendar`：`calendar` 每月 1 日通过 `user-scan` 强制轮换 mita 配额窗口
- **双向带宽**：`tc` 出口 HTB（sport）+ 入口 ingress police（dport），上下行同 Mbps
- `user-quota-reset` 可手动/强制触发日历月重置

### v1.6.0 运维加固

- **用户配置备份 / 恢复 / 导出导入**：`user-backup`、`user-restore`、`user-export`、`user-import`；变更前自动备份到 `/etc/mita/backups/`（保留最近 20 份）
- 增删改用户、恢复导入与 `user-scan` 使用管理锁，降低并发写冲突
- 卸载时清理 timer/cron、用户日志和脚本拥有的 tc filter；不删除系统已有 qdisc

### v1.5.0 按端口带宽限速（旧单实例实现）

- 一用户一口 + **`tc` HTB 出口限速**（`--bandwidth` Mbps，0=不限）
- `user-set-rate` / `rate-status` / `rate-restore`；开机 `mita-tc-restore` 恢复规则
- 菜单用户管理可设置带宽并查看 tc 状态

### v1.4.0 流量套餐与到期

- 套餐：`unlimited` / `trial`(10GB/7d) / `standard`(100GB/30d) / `custom`
- 写入 mita `quotas`（默认**滚动 N 天**）；`expire_at` 到期自动停用（端口保留）
- `user-scan` 每 15 分钟（systemd timer 或 cron）

### v1.3.0 多用户与入口端口（旧单实例模型）

- `/etc/mita/users.json` 管理多用户；该历史版本仍是单实例，v2.0.0 已迁移为专属实例
- 菜单「用户管理」与 CLI：`users` / `user-add` / `user-del` / `user-show`
- 安装后自动迁移主用户；按用户导出节点链接

### v1.2.27 增强

- **端口自动分配（按 IP 尾号）**：安装 / 非交互时默认端口改为**按本机内网 IP 末位八位组推导**——端口基数 = 末位 × 100，段内随机取 `xx01-xx99`，`xx00` 保留给 SSH。例：`172.16.1.36` → `3601-3699`
- 末位过小（基数 < 1025 落入特权端口）或为 `0` / `255`（网络号 / 广播）时自动回退随机端口
- 双协议 BOTH：TCP 末两位上限取 98，避免 UDP（主端口+1）溢出到 `xx00`（SSH 位）或相邻机器段
- 多网卡 / Docker 环境优先取默认路由出口 IP；显式 `--port` 落在 IP 尾号段外时给出提示（不阻断）

### v1.2.20 修复

- 菜单模式下 `die` 不再 `exit`，操作失败自动返回菜单
- Debian 自动修复 `/usr/bin/mita` 软链；二进制缺失时提示 `apt reinstall`
- 查看节点前执行 `repair_mita_binary_paths` + 启动守护进程

### v1.2.19 修复

- **菜单循环**：操作完成后返回菜单（不再直接退出）；无效/空输入提示重试
- **Debian 修复**：不再误删 `/usr/bin/mita`；自动 `apt` 包路径修复 + wrapper 动态查找二进制
- 查看节点前自动启动守护进程；失败时提示而非退出菜单
- 安装 wrapper 后执行 `hash -r` 刷新 bash 命令缓存

### v1.2.18 修复

- 修复 Debian 选 6 卡死/CPU 拉满：`is_mita_wrapper` 误对 ELF 二进制 `head -n1` 导致 grep 扫描整个文件
- 修复 migrate 误将 wrapper 脚本当作二进制迁移到 `mita-real`
- 仅对 ELF 二进制执行布局迁移；`mita-real` 若非二进制自动清理

### v1.2.17 修复

- 修复 `mita` 快捷命令报 `install: same file` 导致 wrapper 未安装（`install-mita` 自更新时跳过同路径拷贝）
- 任意 `install-mita` 调用时自动检查并补装 `/usr/local/bin/mita` wrapper

### v1.2.16 增强

- 「查看节点链接」输出增加分区标题与说明：标注 `mierus://` 为分享链接、JSON 为客户端配置及导入方式

### v1.2.15 修复

- **`mita` 快捷命令**：`/usr/local/bin/mita` 改为管理入口（无参数打开菜单）；真实二进制迁至 `mita-real`，OpenRC/systemd 直连真实二进制
- 打开菜单时自动安装/更新 wrapper（升级提示「已是最新」时也会更新管理脚本）
- 修复「查看节点链接」失败：`describe config` 密码哈希时从 `install-state.env` 或 `/root/mieru_client_*.json` 回退读取凭据
- 安装状态文件保存用户名/密码（`chmod 600`）

### v1.2.14 增强

- 新增 **重新配置**（主菜单「重新配置」/ `--reconfigure`）：部署后可改端口、密码、协议，无需重装
- 菜单「查看节点」：随时重新展示 `mierus://` 链接、JSON、Clash 片段
- **快捷命令不区分大小写**：`install-mita STATUS`、`mita-menu`、`mita reconfigure` 等均可用
- 登录 shell 安装 `mita()` 函数：`mita` 打开菜单，管理子命令不区分大小写；`mita start` 等仍走官方二进制

### v1.2.13 修复

- OpenRC `crashed` 状态自动 `zap` + 重启（修复 `rc-service mita start` 提示 already started 无法恢复）
- OpenRC 服务增加 `respawn` 自动拉起守护进程
- `--status` / 菜单「状态」按平台显示正确命令（Alpine 不再误导为 systemctl）
- 状态检查时自动尝试恢复守护进程并输出 `/var/log/mita.err` 日志

### v1.2.12 修复

- Alpine/OpenRC：`/etc/mita` 授权 `mita:mita`（守护进程需写入 `server.conf.pb`，否则启动即退出）
- OpenRC 服务增加 `start_pre` + `checkpath`，确保运行时目录存在
- 套接字等待失败时输出 `/var/log/mita.err` 日志尾部

### v1.2.11 修复

- 修复 Alpine/BusyBox `mktemp: Invalid argument`（`XXXXXX` 必须在模板末尾）
- 新增 `mktemp_file` / `mktemp_dir` 兼容 GNU 与 BusyBox

### v1.2.10 增强

- 文档与 `--help` 补充 **Alpine 一键命令**（`apk add bash curl` + `| bash`，无需 sudo）
- 非 bash / 非 root 时给出 Alpine 专用提示

### v1.2.9 修复

- 修复 deb 安装后 `mita.sock` 未就绪导致 `mita start` 失败、脚本中断（`set -e`）
- 新增 `wait_mita_socket` / `ensure_mita_daemon`：先启 systemd 守护进程，等待 RPC 套接字后再 `apply` / `start`
- `mita start` 改为重试 + 警告，不再因单次失败退出安装

### v1.2.8 增强

- 交互菜单顶部显示 **版本号 v1.2.8** 与 **作者 ike**
- 移除未使用的 `build_client_json` 聚合函数（孤立代码）
- 卸载时显式清理 `mieru_client_tcp_*.json` / `mieru_client_udp_*.json`

### v1.2.7 修复

- 交互安装增加 **编号菜单** 选择传输协议（1=TCP / 2=UDP / 3=双协议），置于端口询问之前
- 修复 v1.2.4 默认 TCP 时跳过协议询问的 BUG

### v1.2.6 增强

- **分协议输出**：双协议（BOTH）时分别输出 TCP / UDP 节点链接与 JSON（`mieru_client_tcp_*.json`、`mieru_client_udp_*.json`）
- 单协议（TCP 或 UDP）时仅输出对应链接与配置
- Clash 片段：双协议输出 tcp / udp 两条独立代理（不再聚合为单条）

### v1.2.5 修复

- 修复双协议（BOTH）被误判为 TCP，导致卸载时 UDP 防火墙规则未清理
- 修复交互安装时无法选择 UDP/双协议（默认 TCP 跳过协议询问）
- `--client-config` / 卸载防火墙：从 `mita describe config` 精确解析 portBindings
- 移除未使用的 `--menu` 参数

### v1.2.4 修复

- **默认改回 TCP**（官方推荐；多数场景 Clash `udp: true` 即够用）
- **双协议 BOTH**：TCP 用主端口，UDP 用 **主端口+1**（对齐官方示例，避免同端口双绑定）
- 修复 `mita start` 未显式调用导致 IDLE 的问题
- 客户端提示：v2rayN 等请选 **tcp**，勿选「两个都」

### v1.2.3 增强

- **默认双协议**：同端口同时监听 TCP + UDP（`--protocol BOTH`，可改为 `TCP` / `UDP`）
- **节点链接**：对齐官方 `mierus://` 格式（当前实现中服务器地址不含端口，`port`/`protocol` 在 query 中成对出现）
- **Clash**：双协议时输出 TCP/UDP 两条代理配置
- 防火墙 / 云安全组提示同步覆盖 TCP 与 UDP

### v1.2.0 增强

- 安装包 SHA256 完整性校验
- 节点链接 URL 编码（支持特殊字符密码）
- Clash / mihomo YAML 片段输出
- deb/rpm 系统 iptables 回退放行
- ufw 端口段语法 `9000:9010/tcp`
- Alpine 启用 BBR 时自动安装 python3
- 本脚本安装标记，卸载前识别官方包

### Alpine 说明

Alpine 使用官方 `mita_*_linux_{amd64,arm64}.tar.gz`，自动安装 OpenRC 或 systemd 服务，并通过 iptables 放行端口。架构：amd64 / arm64。

常见报错与处理：

| 报错 | 原因 | 处理 |
|------|------|------|
| `sudo: not found` | Alpine 默认无 sudo | 去掉 `sudo`，直接 `\| bash`（root 环境） |
| `请使用 bash 运行` | 默认 shell 为 ash | 先 `apk add --no-cache bash curl` |
| `curl: (23) Failure writing` | 管道下游命令失败 | 同上，确保 `bash` 已安装 |
| `mktemp: Invalid argument` | BusyBox 要求 `XXXXXX` 在末尾 | v1.2.11+ 已修复，请拉最新 main |
| `status: crashed` | 守护进程异常退出，OpenRC 进入 crashed | `rc-service mita zap && rc-service mita start`，或 v1.2.13+ 菜单「状态」自动恢复 |
| `daemon is not running` + systemctl 提示 | mita 二进制默认提示 systemd | Alpine 用 `rc-service mita zap && rc-service mita start`；v1.2.13+ 脚本已适配 |

## 端口自动分配（按 IP 尾号）

为便于内网多机批量部署，安装时**默认端口不再是纯随机**，而是按本机内网 IP 的**末位八位组**推导：

- **端口基数 = IP 末位 × 100**，可用端口为段内 `xx01-xx99`（默认随机取一个）
- `xx00` 保留给 SSH，不会被占用

以本机 IP `172.16.1.36` 为例：

| 项目 | 值 |
|------|----|
| IP 末位 | 36 |
| 端口段 | 3600–3699 |
| 保留（SSH） | 3600 |
| 可用（默认随机） | 3601–3699 |

**规则与兜底：**

- 交互安装时显示 `检测到本机 IP …，按尾号规则端口段 …`，回车即用推导端口，也可手动输入覆盖
- 末位过小（基数 < 1025，落入特权端口）或为 `0` / `255`（网络号 / 广播）时，自动回退为随机端口
- 双协议（BOTH）下 UDP = 主端口 + 1；为避免溢出到 `xx00` 或相邻机器段，TCP 末两位上限取 `98`
- 如需固定端口仍可用 `--port` 指定；若不在 IP 尾号段内会给出提示（不阻断）
- 多网卡 / 装有 Docker（`172.17.0.1`）时，脚本优先取**默认路由出口 IP**；若识别有误，请用 `--port` 覆盖

> **安全提示**：端口可由 IP 规律反推，便于管理但降低隐蔽性。建议仅在内网使用；公网暴露时务必配合云安全组限制来源。

## 非交互安装

```sh
curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | \
  sudo bash -s -- --install -y \
    --port 2088 \
    --profile balanced \
    --advertise-auto \
    --mieru-channel stable \
    --user myuser \
    --password 'my-secret' \
    --enable-bbr
```

`-y` 不会替用户猜测客户端入口：必须同时提供 `--advertise-host` / `--advertise-port`，或显式写 `--advertise-auto`。

前置入口 `cm-entry.example.com:443` 转发到本机监听端口 `2088` 时，可使用：

```sh
install-mita --install -y --profile iplc \
  --port 2088 \
  --advertise-host cm-entry.example.com \
  --advertise-port 443
```

`--advertise-host` 与 `--advertise-port` 必须同时提供；host 可为 IPv4、IPv6 或域名。执行 `install-mita reconfigure -y --advertise-auto` 可恢复自动探测。双协议模式下，展示的 UDP 入口端口为自定义入口端口加一。自定义入口只负责生成客户端信息，前置服务器必须自行建立到真实监听端口的四层转发。

显式入口与探测到的公网地址、后端端口完全相同时，摘要不会重复打印映射；只有域名/IP 或端口确实不同，才会显示「客户端入口映射」以及 Client → Backend 信息。IPLC/NAT/前置转发场景只作为合法 INFO，不会被 Doctor/perf 判为警告或失败。

## 配置预设 Profile

| Profile | 完整参数摘要 | 使用场景 |
|---|---|---|
| `iplc`（IPLC / 专线性能） | TCP、MTU 1400、multiplexing off、no-wait、Traffic Pattern off、Low Entropy off | IPLC、企业专线、明确允许 Mieru 的网络；性能优先 |
| `balanced`（普通公网） | TCP、MTU 1400、multiplexing off、no-wait、conservative、Low Entropy off | 普通 VPS / 公网环境 |
| `stealth`（强化伪装） | TCP、MTU 1400、multiplexing off、no-wait、aggressive、Low Entropy off | 更强流量特征处理；Low Entropy 仍需单独确认 |
| `custom`（高级自定义） | 不套用预设，逐项开放现有参数 | 逐字段高级配置 |

Profile 不参与运行时推算。`PROTOCOL`、`MTU`、`MULTIPLEXING`、`HANDSHAKE_MODE`、`TRAFFIC_PATTERN`、`LOW_ENTROPY_MODE` 始终完整保存；预设内任一参数被单独修改后，`PROFILE` 自动变为 `custom`。

分享 URI 中的 `profile=default` 是上游 Mieru 客户端的 `profileName`（与生成 JSON 中的 `activeProfile: "default"` 对应），不是 OneClick UI 的参数预设；两者语义独立，因此不会把它改写成 `iplc|balanced|stealth|custom`。

## Mieru 版本通道

- `stable`：项目明确测试的 `3.35.0`，新安装默认使用。
- `latest`：每次安装/升级查询上游最新 release。
- `pinned`：通过 `--mieru-version X.Y.Z` 精确指定，面向高级用户。

从 v2.1.x 升级且 state 没有 `MIERU_CHANNEL` 时会记为 `latest`，保持旧版“跟随上游最新”的行为；已经选择 stable 的用户不会被自动切换到 latest。

```sh
install-mita upgrade --mieru-channel stable
install-mita upgrade --mieru-channel latest
install-mita upgrade --mieru-version 3.35.0
```

## State schema 与迁移

`/var/lib/mita-oneclick/install-state.env` 新增 `PROFILE`、`MIERU_CHANNEL`、`MIERU_VERSION`。`users.json`、配额、限速、metrics、firewall/tc 所有权清单和 `isolated-v2` 数据格式不变。

卸载保护会在首次接管前为已存在的 mita 包/系统账号写入独立的 `preserve-preexisting-*` 所有权标记；这些标记不属于 `install-state.env` 或 `users.json` schema，也不改变任何 Mieru 运行配置。

旧 state 没有 `PROFILE` 时，只在 `PROTOCOL`、`MTU`、`MULTIPLEXING`、`HANDSHAKE_MODE`、`TRAFFIC_PATTERN`、`LOW_ENTROPY_MODE` 全部存在且与预设完全一致时反推；否则写作 `custom`。此过程不会修改旧参数，也不会用公网探测覆盖 `ADVERTISE_HOST` / `ADVERTISE_PORT`。

`--mtu` 支持：

- `safe`：固定 `1400`，默认且推荐
- `auto`：TCP 使用 `1400`；UDP / BOTH 按出口链路自动计算，为兼容 mihomo 最大 `1400`
- `1280-1500`：直接指定自定义 MTU；`1401-1500` 仅建议用于可同步 MTU 的官方 mieru 客户端

已安装后可随时调整并重新输出客户端参数：

```sh
mita mtu                         # 交互选择
install-mita mtu 1452            # 直接设置
install-mita --mtu-config --mtu auto
```

## 其它命令

| 命令 | 说明 |
|------|------|
| `--reconfigure` | 修改端口/密码/协议（不重装二进制） |
| `--upgrade` | 按保存的 stable/latest/pinned 通道升级 |
| `--uninstall` | 卸载 mita、管理脚本、防火墙规则、客户端配置与日志 |
| `--status` | 查看服务与配置 |
| `--client-config` / `--show` | 查看节点链接并生成客户端 JSON |
| `--mtu-config` / `mtu` | 调整 MTU、重启验收并重新输出节点配置 |
| `--profile-config` / `profile` | 选择并应用 Profile |
| `--perf` / `perf` | 只读性能诊断，不修改内核、服务、firewall 或 tc |

快捷命令（子命令不区分大小写）：

```sh
install-mita                  # 打开菜单
install-mita reconfigure      # 重新配置
install-mita show             # 查看节点链接
install-mita mtu              # 调整 MTU
install-mita profile          # 选择 Profile
install-mita perf             # 只读性能诊断
install-mita users            # 用户列表
mita-menu status              # 同上
mita status                   # 服务状态（走 install-mita）
mita users / mita doctor      # 用户管理 / 验收（走 install-mita）
mita perf                     # 性能与瓶颈提示（只读）
mita get users                # 官方二进制（流量统计等）
```

卸载后再次管理请重新执行一键安装，或运行 `install-mita --help`（安装后位于 `/usr/local/bin/install-mita`）。

## Development

项目使用模块化源码开发：`src/` 是唯一推荐修改的开发源码，`install-mita.sh` 是由 `scripts/build.sh` 生成的单文件发布产物。修改源码后执行：

```sh
bash scripts/build.sh
```

普通用户的安装方式不变，仍直接使用 `install-mita.sh`，无需关注或下载 `src/`。完整构建与测试流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，模块说明见 [`docs/MODULARIZATION.md`](docs/MODULARIZATION.md)。

## 多用户 / 套餐（v1.3+）

安装完成后可用主菜单「用户管理」，或 CLI：

```sh
# 列表
install-mita users

# 添加用户（每个用户使用独立 mita 实例与专属端口）
install-mita user-add --user bob --password 'secret' --package trial
install-mita user-add --user carol --password 'x' --package standard --port 21005 --bandwidth 20

# 套餐与到期
install-mita user-set-quota --user bob --package custom --quota-mb 51200 --quota-days 30
# 日历月配额（每月 1 日重置计数窗口）
install-mita user-set-quota --user bob --quota-mb 102400 --quota-mode calendar
install-mita user-set-expire --user bob --expire +30d
install-mita user-set-expire --user bob --expire 0          # 永不过期
install-mita user-quota-reset -y                           # 强制本月重置 calendar 用户

# 启用 / 停用（停用保留端口，可再 enable）
install-mita user-disable bob
install-mita user-enable bob

# 专属实例双向限速（Mbps；0=不限）
install-mita user-set-rate --user bob --bandwidth 20
install-mita user-set-rate --user bob --bandwidth 0
install-mita rate-status

# 单独修改客户端展示入口（不重启服务端实例）
install-mita user-set-endpoint --user bob --advertise-host 203.0.113.10 --advertise-port 443
install-mita user-set-endpoint --user bob --advertise-auto

# 删除并释放端口
install-mita user-del bob

# 备份 / 恢复 / 导出
install-mita user-backup
install-mita user-export /root/users-export.json
install-mita user-restore /var/lib/mita-oneclick/backups/users_manual_*.json

# 用量与验收
install-mita user-usage
install-mita user-export-clients /root/mieru-clients
install-mita doctor
```

**说明与限制：**

| 项 | 说明 |
|----|------|
| 部署模型 | `isolated-v2`：每个启用账号一个 mita 实例；稳定 `instance_id` 与端口/用户名解耦 |
| 端口与凭据 | 每个实例仅配置一个账号和它的 TCP/UDP binding，构成真实隔离边界 |
| 流量套餐 rolling | mita `quotas` 滚动 N 天 / MB |
| 流量套餐 calendar | 仅支持 `QUOTA_RESET_METHOD=metrics`；每月只停止并清空到期用户自己的 `metrics.pb` |
| 到期 | 本地 `expire_at`；`user-scan` 停止/禁用该用户实例并关闭本地防火墙端口，保留状态和 metrics 以便再启用；允许全部账号同时到期 |
| 客户端展示入口 | 每个用户可独立设置 IPv4/IPv6/域名与端口；仅用于导出，不改真实监听。相同协议下两个用户不能使用同一有效展示入口，避免前置四层转发目标不明确 |
| 带宽 | `0-1000000` Mbps；默认出口网卡上的专属端口 IPv4/IPv6 ingress/egress police；只增删 `/var/lib/mita-oneclick/tc-owned.filters` 记录的 pref，不替换现有 qdisc；多出口可设置 `TC_IFACE` |
| 本地防火墙 | 所有权记录在 `/var/lib/mita-oneclick/firewall-owned.bindings`；预先存在的同端口规则不会被接管或删除 |
| 用量 | 逐实例调用 `mita get users` / `mita get quotas` |
| 状态与实例 | root 管理状态 `/var/lib/mita-oneclick/` 为 700、`users.json` 为 600；服务配置 `/etc/mita/instances/<instance_id>/server.json`；UDS `/run/mita-instances/<instance_id>.sock`；metrics `/var/lib/mita/instances/<instance_id>/metrics.pb` |
| 删除用户 | `install-mita user-del NAME` 或 `--user-del NAME` |
| 月配额重置 | `user-quota-reset` 仅影响过月 calendar 用户；`-y` 强制这些用户本月重置 |
| 数值范围 | quota MB / days 使用上游 `int32` 范围；有限配额未指定周期时按 30 天 |
| 依赖 | `python3`、`iproute2`、`util-linux`；systemd 用 tmpfiles 管理 UDS 父目录，OpenRC 用 mount namespace 隔离固定 metrics 路径 |

套餐模板：`unlimited` · `trial`（10GB/7 天）· `standard`（100GB/30 天）· `custom`。

## 与官方脚本的关系

上游官方提供 Python 安装器：

```sh
curl -fSsLO https://raw.githubusercontent.com/enfein/mieru/refs/heads/main/tools/setup.py
sudo python3 setup.py
```

本仓库的 Bash 脚本在官方能力之上补充了：

- 纯 Bash 入口，`curl \| bash` 即可
- 非交互参数（`--port` / `--user` / `--password` / `-y`）
- 防火墙自动放行
- 安装摘要与客户端配置一键导出
- 多用户、流量套餐、可验证的到期撤权与备份恢复

## 客户端

安装完成后，将服务器 IP、端口、用户名、密码填入 [mieru 客户端](https://github.com/enfein/mieru/blob/main/docs/client-install.md) 或 Clash Verge Rev 等兼容客户端。v2.0.0 的每个账号链接指向自己的 mita 实例与专属端口；其它账号凭据无法在该实例认证。

## 许可

安装脚本 MIT；mita/mieru 软件遵循上游 GPL-3.0。
