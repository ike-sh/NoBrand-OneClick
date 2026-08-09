# v2.2.0 Real-World Release Acceptance

本文档是 v2.2.0 RC 的真实环境人工验收步骤和填写模板，不是已完成的测试报告。

- 当前总体状态：部分完成（§0.4 已记录真实 systemd 部署、URI 与 mihomo 客户端证据；其余完整场景按各节结果执行）
- 当前发布建议：`尚未给出（必须在真实测试完成后填写）`
- 允许的结果值：`PASS`、`FAIL`、`BLOCKED`、`NOT RUN`
- 只有执行了步骤、核对了预期并保存了证据，才可勾选对应项目。
- 未获得真实 OpenRC 主机时必须保留 `NOT RUN`，不得用无 init 容器结果代替。
- 测试发现异常时先记录和分析；不要在验收过程中顺手改默认参数、state schema、模块或业务设计。

## 0. 验收记录与证据规则

### 0.1 候选产物身份

本轮 Phase 7 冻结的生成产物 SHA-256 为：

```text
8d5dbd48a8b1b2877ee7018a4e2bcab34fcbc1d33ea739cc04e4c1dcdea47b0e  install-mita.sh
```

每台测试机均填写：

| 字段 | 记录 |
|---|---|
| 测试编号 | |
| 测试日期与时区 | |
| 执行人 | |
| 云厂商/机房 | |
| OS 与版本 | |
| 内核 | |
| init 系统与版本 | |
| 架构 | |
| Mieru 安装前版本 | |
| Mieru 安装后版本 | |
| `install-mita.sh` SHA-256 | |
| 证据目录/工单链接 | |

在开发机确认产物仍是已构建版本：

```bash
bash scripts/build.sh --check
cmp -s install-mita.sh dist/install-mita.sh
sha256sum install-mita.sh dist/install-mita.sh
```

上传后在测试机确认字节一致且语法有效：

```bash
sha256sum ./install-mita.sh
bash -n ./install-mita.sh
```

- [ ] 上传前、上传后的 SHA-256 一致
- [ ] SHA-256 与本节冻结值一致
- [ ] `bash -n` 退出码为 0

若 hash 不一致，停止测试并标记 `BLOCKED`；不要继续用另一份脚本产生验收结论。

### 0.2 证据与敏感信息

`install-state.env`、`users.json`、Mieru JSON、`mierus://` URI 均可能包含明文凭据。证据只保存在测试机 root 可读目录，不得直接贴入公开 issue、聊天或最终报告。

```bash
sudo install -d -o root -g root -m 0700 /root/mieru-acceptance-v2.2.0
sudo find /root/mieru-acceptance-v2.2.0 -type f -exec chmod 0600 {} +
```

公开报告仅记录：脱敏后的 endpoint、版本、结果、文件 hash 和证据位置。密码一致性用 SHA-256 摘要或在受保护副本中人工比较，不记录明文。

上述规则同时适用于真实客户端。mihomo YAML、Mieru JSON 和完整 URI 在客户端也须设为仅当前用户可读，不得进入录屏、公开日志或最终报告；URI 命令还要避免写入 shell history，并只使用可销毁的验收账号/环境。测试完成后清除客户端上的临时凭据和配置。

### 0.3 结果记录格式

每个场景结束时填写：

| 字段 | 记录 |
|---|---|
| Result | `PASS / FAIL / BLOCKED / NOT RUN` |
| Start / End | |
| Evidence | |
| Unexpected behavior | |
| Suspected blocker | `Yes / No` |
| Issue/link | |
| Operator | |

### 0.4 已接收的部分真机记录：RW-20260809-RACKNERD-01

本节是对执行人提供的终端记录所作的脱敏摘要。原记录包含自动生成的密码、完整 URI 和客户端配置，不得提交到仓库、公开 issue 或正式报告；本节不保存这些值。

| 字段 | 记录 |
|---|---|
| 测试日期 | 2026-08-09；VPS 时区未记录 |
| 环境 | RackNerd、Debian 系发行版、systemd；OS 精确版本、内核和架构未记录 |
| 脚本来源 | 从 GitHub `main` 的 raw URL 直接管道执行 |
| 候选身份 | 仓库侧确认 `origin/main` 与 `v2.2.0` 的 `install-mita.sh` 无差异，冻结 SHA-256 仍为 §0.1 的值；但 VPS 未保存脚本、未执行 `sha256sum`/`bash -n`，因此本次运行本身的产物身份证据不完整 |
| Mieru | 3.35.0 |
| 安装配置 | IPLC，TCP，MTU 1400，MULTIPLEXING_OFF，HANDSHAKE_NO_WAIT，Traffic Pattern 关闭，Low Entropy 关闭 |
| Endpoint | 安装时主动填写了独立客户端入口；advertised endpoint 与 backend 不同，因此没有测试默认 endpoint |
| 证据 | 执行人提供的终端记录；因含凭据仅保存在仓库外 |

已观察到：

- 未安装菜单包含预期状态字段及 `0` 至 `10` 的完整入口。
- 交互安装结束且未回滚；部署迁移到 `isolated-v2`，专属实例报告运行正常，BBR/FQ 已启用。
- `mita show`、URI、JSON、mihomo 片段和 `mita perf` 均使用自定义 advertised endpoint，并把它与实际 backend 分开显示。
- 新增用户获得专属端口和实例；删除后报告端口已释放。
- `mita perf` 完成只读诊断，无 WARN/FAIL；`mita doctor` 为 `PASS=23 WARN=0 FAIL=0`。
- 菜单“升级”只确认当前脚本为 v2.2.0、Mieru 已满足 stable 目标；这不是 v2.1.x 到 v2.2.0 的升级测试。
- 卸载流程报告 package purge、管理脚本和 crontab 清理以及 `mita` 用户删除，并正常结束。
- 执行人随后确认该部署已经实际用于代理，独立入口可以端到端连接和传输；生成的节点链接及 mihomo 配置均已实际使用且工作正常。按本文上下文，“节点链接”记录为 `mierus://` URI 验证，不扩展为尚未明确确认的官方 JSON 验证。

这份记录不能证明：

- 默认 endpoint；本次安装明确使用了独立入口。
- Endpoint-only fast path；独立入口在首次安装时填写，没有 PID、启动时间、backend、firewall 和 tc 的 before/after 对比。
- 真实 IPLC 场景的完整服务端控制面核对；端到端连通已经由执行人确认，但仍没有入口转发配置、`ss`、backend JSON、firewall 和 tc 的原始证据。
- `server.json` 只含 backend、实际监听端口以及 firewall/tc 不受 advertised endpoint 影响；没有保存相应原始快照。
- 官方 Mieru JSON 的真实导入和连接。
- v2.1.x 原地升级、backup/restore、OpenRC、性能 A/B。
- clean-host ownership 的完整结果；虽然卸载命令正常完成，但缺少 §8.0 规定的 before/managed/after 快照以及 package、group、服务、进程、state、firewall、tc 的卸载后核对。

发现一个非阻塞交互问题：用户管理中新增用户并在第一次密码提示直接回车时，会再次显示一次“密码（回车随机）”提示。源码确认菜单层和动作层都会在空值时提示，v2.1.4 中已存在相同路径，因此不是模块化引入的回归；本次操作最终成功，Phase 8 不修改代码，留待后续补丁版本单独处理。

本记录未确认任何 release blocker。mihomo 实际使用与官方 Mieru URI 节点链接可标记 `PASS`；由于客户端版本、逐命令输出和脱敏流量记录未保存，证据质量限制保留在对应结果中。其余发布阻塞场景仍不足以给出 `READY`。

## 1. 场景 A：普通 systemd VPS fresh install

目标环境：一台干净、可销毁的真实 Debian 12 或 Ubuntu 24.04 systemd VPS。不要在承担生产业务的主机执行。

### 1.1 环境记录

```bash
cat /etc/os-release
uname -a
systemctl --version
ip -brief address
ip route
```

| 字段 | 记录 |
|---|---|
| VPS/快照 ID | |
| 公网 IPv4/IPv6 | |
| 默认接口 | |
| 初始防火墙工具 | `ufw / firewalld / iptables / other` |
| 初始 `mita` 包/用户/组 | |

确认主机没有 OneClick 安装痕迹：

```bash
command -v install-mita || true
command -v mita || true
sudo test ! -e /var/lib/mita-oneclick/.installed
```

### 1.2 未安装菜单

从终端直接运行当前上传的产物，不加动作参数：

```bash
sudo bash ./install-mita.sh
```

在选择任何操作前确认菜单完整显示：

- [ ] `状态: 未安装`
- [ ] `用户: -`
- [ ] `Profile: -`
- [ ] `Mieru Version: 未安装`
- [ ] `1) 新装 / 安装`
- [ ] 菜单连续包含 `2)` 至 `9)`
- [ ] `10) 卸载`
- [ ] `0) 退出`

保存未安装菜单终端记录：____________________

### 1.3 交互安装

重新进入菜单并选择 `1) 新装 / 安装`：

- Profile 选择 `IPLC / 专线性能`。
- Backend 使用测试机上的真实监听端口。
- 客户端入口直接接受自动探测默认值，不填写独立入口。
- 为避免 `mita perf` 出现与 endpoint 无关的 BBR/FQ 警告，本验收机应在安装提示中启用 BBR + FQ；若主机不支持，单独记录环境限制。
- 记录所有选择，但不要把密码写入公开报告。

| 安装字段 | 记录 |
|---|---|
| Backend protocol/port | |
| 自动探测地址 | |
| Advertised endpoint | |
| Profile | |
| MTU | |
| Multiplexing | |
| Handshake | |
| Traffic Pattern | |
| Low Entropy | |
| Mieru channel/version | |

验收条件：

- [ ] 安装成功结束，未触发回滚
- [ ] backend endpoint 与 advertised endpoint 等价
- [ ] `/var/lib/mita-oneclick/install-state.env` 权限为 `0600`、owner 为 root
- [ ] `/var/lib/mita-oneclick/users.json` 权限为 `0600`、owner 为 root
- [ ] `/etc/mita/instances/*/server.json` 中只包含真实 backend listener
- [ ] `Profile` 显示 IPLC / 专线性能，参数仍为冻结的 IPLC 组合

### 1.4 安装后检查

依次执行并保存完整输出与退出码：

```bash
mita
mita show
mita perf
mita doctor
sudo systemctl list-units --type=service --all 'mita*' --no-pager
sudo systemctl status 'mita-oneclick@*.service' --no-pager
sudo ss -lntp
```

检查：

- [ ] 至少一个 `mita-oneclick@*.service` 为 `active (running)`
- [ ] `mita doctor` 返回成功且没有 FAIL
- [ ] `mita perf` 不显示“独立客户端入口”
- [ ] `mita show` 不显示 `Client -> Backend` 映射
- [ ] `mita show`、Mieru JSON、URI 与 mihomo 片段使用自动探测地址和真实监听端口
- [ ] `mita show` 的 Mieru Version 与实际二进制一致
- [ ] `mita show` 的 Profile 为 IPLC / 专线性能
- [ ] `ss -lntp` 可见真实 backend port，由预期的 `mita-real` 实例监听

### 1.5 场景 A 结果

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| Evidence | |
| Notes | 2026-08-09 的部分运行使用了自定义入口，且缺少候选 hash、`bash -n`、`systemctl status`、`ss` 和 state/backend 原始证据；见 §0.4。完整场景仍为 `NOT RUN`。 |

## 2. Endpoint-only fast path

在场景 A 已成功安装且服务稳定后执行。此测试只修改主用户的 `advertise_host` 与 `advertise_port`，不得同时传入 Profile、MTU、协议、端口、用户名或密码参数。

### 2.1 修改前快照

建立受保护的 before 目录：

```bash
sudo install -d -o root -g root -m 0700 /root/mieru-acceptance-v2.2.0/endpoint-before
sudo pgrep -a mita | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/pids.txt
sudo systemctl list-units --type=service --all --no-legend 'mita-oneclick@*.service' \
  | awk '{print $1}' \
  | while read -r unit; do
      systemctl show "$unit" \
        -p Id -p MainPID -p ActiveEnterTimestampMonotonic \
        -p ExecMainStartTimestampMonotonic;
    done \
  | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/systemd.txt
sudo find /etc/mita/instances -type f -name server.json -print0 \
  | sort -z | sudo xargs -0 sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/backend.sha256
sudo sha256sum \
  /var/lib/mita-oneclick/firewall-owned.bindings \
  /var/lib/mita-oneclick/tc-owned.filters \
  2>/dev/null \
  | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/owned-state.sha256
sudo sh -c 'command -v iptables-save >/dev/null && iptables-save > /root/mieru-acceptance-v2.2.0/endpoint-before/iptables-save.txt || true'
sudo sh -c 'command -v ip6tables-save >/dev/null && ip6tables-save > /root/mieru-acceptance-v2.2.0/endpoint-before/ip6tables-save.txt || true'
sudo sh -c 'command -v nft >/dev/null && nft list ruleset | sed -E "s/counter packets [0-9]+ bytes [0-9]+/counter/g" > /root/mieru-acceptance-v2.2.0/endpoint-before/nft.txt || true'
sudo sh -c 'tc qdisc show; iface=$(awk -F"|" '\''$1=="iface"{print $2; exit}'\'' /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true); [ -n "$iface" ] || iface=$(ip -o route show default | awk "NR==1{print \$5}"); printf "owned iface: %s\n" "$iface"; [ -z "$iface" ] || { tc qdisc show dev "$iface"; tc filter show dev "$iface" ingress; tc filter show dev "$iface" egress; }' \
  | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/tc.txt
sudo cp -a /var/lib/mita-oneclick/install-state.env /var/lib/mita-oneclick/users.json \
  /root/mieru-acceptance-v2.2.0/endpoint-before/
sudo find /root/mieru-clients/current -maxdepth 1 -type f -print0 \
  | sort -z | sudo xargs -0 sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/endpoint-before/client-exports.sha256
```

不存在的 ownership 文件允许被跳过；须在 Notes 说明原因。快照之间不要主动产生用户、端口、限速或 firewall 变更。

### 2.2 只更新客户端入口

```bash
sudo install-mita reconfigure -y \
  --advertise-host cm-entry.example.com \
  --advertise-port 10086
```

保存命令完整输出。预期包含“仅客户端参数已更新”以及“服务未重启”的等价提示。

### 2.3 修改后快照与比较

用 2.1 的同一组命令写入 `/root/mieru-acceptance-v2.2.0/endpoint-after/`，然后比较：

```bash
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/pids.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/pids.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/systemd.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/systemd.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/backend.sha256 \
  /root/mieru-acceptance-v2.2.0/endpoint-after/backend.sha256
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/owned-state.sha256 \
  /root/mieru-acceptance-v2.2.0/endpoint-after/owned-state.sha256
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/iptables-save.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/iptables-save.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/ip6tables-save.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/ip6tables-save.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/nft.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/nft.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/tc.txt \
  /root/mieru-acceptance-v2.2.0/endpoint-after/tc.txt
```

只比较主机实际存在的 firewall 后端文件。所有上述 diff 必须为空。

客户端导出 hash 则必须产生与 endpoint 对应的预期差异：

```bash
sudo diff -u /root/mieru-acceptance-v2.2.0/endpoint-before/client-exports.sha256 \
  /root/mieru-acceptance-v2.2.0/endpoint-after/client-exports.sha256
```

该命令预期返回有差异；逐个确认差异文件属于当前主用户的 Mieru client JSON。URI 和 mihomo YAML 以随后 `mita show` 的受保护终端记录为准。

检查预期变化：

```bash
sudo grep -E '^(ADVERTISE_HOST|ADVERTISE_PORT)=' /var/lib/mita-oneclick/install-state.env
sudo python3 - \
  /root/mieru-acceptance-v2.2.0/endpoint-before/users.json \
  /root/mieru-acceptance-v2.2.0/endpoint-after/users.json <<'PY'
import json, sys
before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
assert {k: v for k, v in before.items() if k != "users"} == {
    k: v for k, v in after.items() if k != "users"
}
before_users = {u["name"]: u for u in before.get("users", [])}
after_users = {u["name"]: u for u in after.get("users", [])}
assert before_users.keys() == after_users.keys()
allowed = {"advertise_host", "advertise_port", "updated_at"}
changed = {}
for name in before_users:
    keys = {
        key for key in before_users[name].keys() | after_users[name].keys()
        if before_users[name].get(key) != after_users[name].get(key)
    }
    if keys:
        assert {"advertise_host", "advertise_port"} <= keys, (name, keys)
        assert keys <= allowed, (name, keys)
        changed[name] = sorted(keys)
assert len(changed) == 1, changed
name = next(iter(changed))
assert after_users[name]["advertise_host"] == "cm-entry.example.com"
assert after_users[name]["advertise_port"] == 10086
print("changed user and allowed keys:", name, changed[name])
PY
sudo python3 - <<'PY'
import json
p = "/var/lib/mita-oneclick/users.json"
d = json.load(open(p, encoding="utf-8"))
for u in d.get("users", []):
    print(u.get("name"), u.get("advertise_host"), u.get("advertise_port"))
PY
mita show
mita perf
mita doctor
```

验收条件：

- [ ] 所有 mita instance PID 完全不变
- [ ] `MainPID`、`ActiveEnterTimestampMonotonic`、`ExecMainStartTimestampMonotonic` 完全不变
- [ ] 所有 `/etc/mita/instances/*/server.json` hash 完全不变
- [ ] firewall 规则与 ownership manifest 完全不变
- [ ] tc qdisc/filter 与 ownership manifest 完全不变
- [ ] `install-state.env` 只发生预期的客户端 endpoint 变化
- [ ] `users.json` 仅主用户的 `advertise_host`、`advertise_port` 与审计字段 `updated_at` 变化，其它字段和用户完全不变
- [ ] `mierus://`、Mieru JSON、mihomo YAML 均改为 `cm-entry.example.com:10086`
- [ ] `mita show` 现在显示 `Client -> Backend` 映射
- [ ] `mita perf` 将独立入口标记为 `[INFO]`，不是 WARN/FAIL
- [ ] `mita perf` 本次完整输出没有 WARN/FAIL；若有与 endpoint 无关的环境警告，也须记录和处理后再判本项
- [ ] `mita perf` 的 Client 为 `cm-entry.example.com:10086`
- [ ] `mita perf` 的 Backend 仍为实际公网地址和原监听端口
- [ ] `mita doctor` 仍成功

注意：日志时间、命令审计记录和网络统计计数不是本项的配置比较对象；不得用这个例外忽略规则、PID、启动时间或 backend 配置变化。

### 2.4 Endpoint-only 结果

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| Before evidence | |
| After evidence | |
| Diff evidence | |
| Notes | 2026-08-09 的部分运行只在首次安装时填写独立入口，没有执行本节的 endpoint-only 更新或 before/after 比较；见 §0.4。 |

## 3. 场景 B：真实 v2.1.x 到 v2.2.0 原地升级

这是发布阻塞级测试。必须从一台由真实 v2.1.x 发布产物安装并实际运行的主机或快照开始；仅手工伪造旧 state 文件不能替代本场景。

### 3.1 旧环境准备

| 字段 | 记录 |
|---|---|
| v2.1.x 版本/来源 | |
| v2.1.x 脚本 SHA-256 | |
| OS/init/arch | |
| 已运行时长 | |
| 用户数 | |
| Backend protocol/port | |

在旧版本使用其支持的命令把 MTU 设置为非预设值，例如：

```bash
sudo install-mita mtu 1388
```

在继续前通过旧版 `mita show`、state 和实际配置确认 MTU 已经是 `1388`。不要通过只改文本文件来伪造这个状态。

本用例还要求旧 `install-state.env` 不包含 `MIERU_CHANNEL`。在同一个 Bash 终端中先唯一解析旧 state 路径，并让后续命令继续使用这两个变量：

```bash
set -e
set -o pipefail
if sudo test -f /var/lib/mita-oneclick/install-state.env; then
  OLD_STATE=/var/lib/mita-oneclick/install-state.env
elif sudo test -f /etc/mita/install-state.env; then
  OLD_STATE=/etc/mita/install-state.env
else
  echo "旧 install-state.env 不存在" >&2
  false
fi
if sudo test -f /var/lib/mita-oneclick/users.json; then
  OLD_USERS=/var/lib/mita-oneclick/users.json
elif sudo test -f /etc/mita/users.json; then
  OLD_USERS=/etc/mita/users.json
else
  echo "旧 users.json 不存在" >&2
  false
fi
sudo test -f "$OLD_STATE"
sudo test -f "$OLD_USERS"
if sudo grep -q '^MIERU_CHANNEL=' "$OLD_STATE"; then
  echo "旧 state 已包含 MIERU_CHANNEL，不符合本用例前置条件" >&2
  false
else
  printf 'confirmed missing MIERU_CHANNEL: %s\n' "$OLD_STATE"
fi
printf 'legacy users: %s\n' "$OLD_USERS"
```

如果真实 v2.1.x 已经写入该字段，另建一个确实缺字段的真实旧安装用例，不要删除字段后把它描述为原始现场。

### 3.2 升级前证据与备份

```bash
sudo install -d -o root -g root -m 0700 /root/mieru-acceptance-v2.2.0/upgrade-before
if sudo install-mita --help 2>&1 | grep -q -- 'user-backup'; then
  sudo install-mita user-backup
else
  echo '旧版没有 user-backup 命令；继续使用下面的受保护文件级备份'
fi
printf 'OLD_STATE=%s\nOLD_USERS=%s\n' "$OLD_STATE" "$OLD_USERS" \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/source-paths.txt
sudo cp -a "$OLD_STATE" /root/mieru-acceptance-v2.2.0/upgrade-before/install-state.env
sudo cp -a "$OLD_USERS" /root/mieru-acceptance-v2.2.0/upgrade-before/users.json
{
  for root in /etc/mita /var/lib/mita-oneclick /etc/mita/instances; do
    if sudo test -e "$root"; then
      sudo find "$root" -maxdepth 3 -type f -print0
    fi
  done
} \
  | sort -z | sudo xargs -0 sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/files.sha256
sudo pgrep -a mita | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/pids.txt
sudo ss -lntup | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/listeners.txt
sudo systemctl list-units --type=service --all 'mita*' --no-pager \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/systemd.txt
sudo sh -c 'command -v iptables-save >/dev/null && iptables-save > /root/mieru-acceptance-v2.2.0/upgrade-before/iptables-save.txt || true'
sudo sh -c 'command -v ip6tables-save >/dev/null && ip6tables-save > /root/mieru-acceptance-v2.2.0/upgrade-before/ip6tables-save.txt || true'
sudo sh -c 'command -v nft >/dev/null && nft list ruleset | sed -E "s/counter packets [0-9]+ bytes [0-9]+/counter/g" > /root/mieru-acceptance-v2.2.0/upgrade-before/nft.txt || true'
sudo sh -c 'tc qdisc show; iface=$(awk -F"|" '\''$1=="iface"{print $2; exit}'\'' /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true); [ -n "$iface" ] || iface=$(awk -F"|" '\''$1=="iface"{print $2; exit}'\'' /etc/mita/tc-owned.filters 2>/dev/null || true); [ -n "$iface" ] || iface=$(ip -o route show default | awk "NR==1{print \$5}"); printf "owned iface: %s\n" "$iface"; [ -z "$iface" ] || { tc filter show dev "$iface" ingress; tc filter show dev "$iface" egress; }' \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/tc.txt
```

在受保护记录中逐用户记录下列语义值。密码只记录摘要：

- username 与 password SHA-256
- enabled
- backend port 与 protocol
- advertise_host 与 advertise_port
- MTU
- multiplexing
- handshake mode
- traffic pattern 与 seed
- low entropy
- quota、quota mode、quota window/reset
- expiration
- bandwidth/rate limit

可用以下命令生成脱敏的 `users.json` 摘要：

```bash
sudo python3 - "$OLD_USERS" <<'PY' \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/users-semantic.json
import hashlib, json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
fields = (
    "name", "enabled", "port", "advertise_host", "advertise_port",
    "quota_mb", "quota_days", "quota_mode", "last_quota_reset",
    "expire_at", "package", "bandwidth_mbps",
)
out = []
for user in sorted(d.get("users", []), key=lambda x: x.get("name", "")):
    row = {key: user.get(key) for key in fields}
    row["password_sha256"] = hashlib.sha256(
        str(user.get("password", "")).encode()
    ).hexdigest()
    out.append(row)
print(json.dumps(out, ensure_ascii=False, sort_keys=True, indent=2))
PY
```

另外保存 `install-state.env` 中非密码关键字段和密码行摘要：

```bash
sudo grep -E '^(PORT|PORT_RANGE|PROTOCOL|ADVERTISE_HOST|ADVERTISE_PORT|MTU|USERNAME|TRAFFIC_PATTERN|TRAFFIC_SEED|LOW_ENTROPY_MODE|MULTIPLEXING|HANDSHAKE_MODE)=' \
  "$OLD_STATE" \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/install-state-semantic.txt
sudo grep '^PASSWORD=' "$OLD_STATE" | sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-before/password.sha256
```

上述管道依赖本节开头的 `set -o pipefail`；任何源文件读取或解析失败都必须中止，不能接受由 `tee` 生成的空“证据”。

### 3.3 执行原地升级

上传并验证本文件第 0 节的同一 RC 产物，然后只执行升级动作；不要同时传入任何配置覆盖参数：

```bash
sudo bash ./install-mita.sh --upgrade
```

保存完整终端输出、退出码以及升级前自动备份的位置。

### 3.4 升级后验证

不要重跑或手工替换 3.2 中写死的 before 命令。使用迁移后的固定路径和独立 after 目录：

```bash
NEW_STATE=/var/lib/mita-oneclick/install-state.env
NEW_USERS=/var/lib/mita-oneclick/users.json
sudo test -f "$NEW_STATE"
sudo test -f "$NEW_USERS"
sudo install -d -o root -g root -m 0700 /root/mieru-acceptance-v2.2.0/upgrade-after
sudo cp -a "$NEW_STATE" /root/mieru-acceptance-v2.2.0/upgrade-after/install-state.env
sudo cp -a "$NEW_USERS" /root/mieru-acceptance-v2.2.0/upgrade-after/users.json
{
  for root in /etc/mita /var/lib/mita-oneclick /etc/mita/instances; do
    if sudo test -e "$root"; then
      sudo find "$root" -maxdepth 3 -type f -print0
    fi
  done
} \
  | sort -z | sudo xargs -0 sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/files.sha256
sudo pgrep -a mita | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/pids.txt
sudo ss -lntup | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/listeners.txt
sudo systemctl list-units --type=service --all 'mita*' --no-pager \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/systemd.txt
sudo sh -c 'command -v iptables-save >/dev/null && iptables-save > /root/mieru-acceptance-v2.2.0/upgrade-after/iptables-save.txt || true'
sudo sh -c 'command -v ip6tables-save >/dev/null && ip6tables-save > /root/mieru-acceptance-v2.2.0/upgrade-after/ip6tables-save.txt || true'
sudo sh -c 'command -v nft >/dev/null && nft list ruleset | sed -E "s/counter packets [0-9]+ bytes [0-9]+/counter/g" > /root/mieru-acceptance-v2.2.0/upgrade-after/nft.txt || true'
sudo sh -c 'tc qdisc show; iface=$(awk -F"|" '\''$1=="iface"{print $2; exit}'\'' /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true); [ -n "$iface" ] || iface=$(ip -o route show default | awk "NR==1{print \$5}"); printf "owned iface: %s\n" "$iface"; [ -z "$iface" ] || { tc filter show dev "$iface" ingress; tc filter show dev "$iface" egress; }' \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/tc.txt
```

生成与 before 完全同字段的脱敏语义摘要：

```bash
sudo python3 - "$NEW_USERS" <<'PY' \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/users-semantic.json
import hashlib, json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
fields = (
    "name", "enabled", "port", "advertise_host", "advertise_port",
    "quota_mb", "quota_days", "quota_mode", "last_quota_reset",
    "expire_at", "package", "bandwidth_mbps",
)
out = []
for user in sorted(d.get("users", []), key=lambda x: x.get("name", "")):
    row = {key: user.get(key) for key in fields}
    row["password_sha256"] = hashlib.sha256(
        str(user.get("password", "")).encode()
    ).hexdigest()
    out.append(row)
print(json.dumps(out, ensure_ascii=False, sort_keys=True, indent=2))
PY
sudo grep -E '^(PORT|PORT_RANGE|PROTOCOL|ADVERTISE_HOST|ADVERTISE_PORT|MTU|USERNAME|TRAFFIC_PATTERN|TRAFFIC_SEED|LOW_ENTROPY_MODE|MULTIPLEXING|HANDSHAKE_MODE)=' \
  "$NEW_STATE" \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/install-state-semantic.txt
sudo grep '^PASSWORD=' "$NEW_STATE" | sha256sum \
  | sudo tee /root/mieru-acceptance-v2.2.0/upgrade-after/password.sha256
sudo diff -u \
  /root/mieru-acceptance-v2.2.0/upgrade-before/users-semantic.json \
  /root/mieru-acceptance-v2.2.0/upgrade-after/users-semantic.json
sudo diff -u \
  /root/mieru-acceptance-v2.2.0/upgrade-before/install-state-semantic.txt \
  /root/mieru-acceptance-v2.2.0/upgrade-after/install-state-semantic.txt
sudo diff -u \
  /root/mieru-acceptance-v2.2.0/upgrade-before/password.sha256 \
  /root/mieru-acceptance-v2.2.0/upgrade-after/password.sha256
```

这三个语义 diff 必须为空。raw hash 可因安全迁移、schema 补全、实例化配置或 Mieru 版本更新而变化；逐项审阅 `files.sha256`，不得把 raw hash 变化直接当成配置变化，也不得用它忽略语义 diff。

再比较升级前后的 firewall/tc 快照；只运行主机实际存在的 firewall 后端对应命令，预期 diff 为空：

```bash
sudo diff -u /root/mieru-acceptance-v2.2.0/upgrade-before/iptables-save.txt \
  /root/mieru-acceptance-v2.2.0/upgrade-after/iptables-save.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/upgrade-before/ip6tables-save.txt \
  /root/mieru-acceptance-v2.2.0/upgrade-after/ip6tables-save.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/upgrade-before/nft.txt \
  /root/mieru-acceptance-v2.2.0/upgrade-after/nft.txt
sudo diff -u /root/mieru-acceptance-v2.2.0/upgrade-before/tc.txt \
  /root/mieru-acceptance-v2.2.0/upgrade-after/tc.txt
```

最后执行运行态检查：

```bash
mita show
mita perf
mita doctor
sudo systemctl list-units --type=service --all 'mita*' --no-pager
sudo ss -lntup
sudo grep -E '^(PROFILE|MIERU_CHANNEL|MTU)=' /var/lib/mita-oneclick/install-state.env
```

验收条件：

- [ ] 所有旧用户名与 password 摘要不变
- [ ] enabled 状态不变
- [ ] 所有 backend port 与 protocol 不变
- [ ] advertise_host 与 advertise_port 不变
- [ ] MTU 仍为 `1388`
- [ ] `PROFILE=custom`
- [ ] multiplexing、handshake mode、traffic pattern/seed、low entropy 均不变
- [ ] quota、expiration、bandwidth/rate limit 均不变
- [ ] 缺少旧字段时迁移后为 `MIERU_CHANNEL=latest`
- [ ] 升级没有为匹配任何 Profile 覆盖旧参数
- [ ] 所有实例 active，真实监听与升级前一致
- [ ] firewall/tc 仍与真实 backend/用户实例一致
- [ ] `mita doctor` 成功
- [ ] 客户端导出可重新生成且使用原 endpoint

任何真实参数被静默改变均为 release blocker。

### 3.5 升级结果

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| v2.1.x evidence | |
| Before/after semantic diff | |
| Migration notes | |
| Notes | |

## 4. 场景 C：真实沪日 IPLC

必须在真实可用的沪日 IPLC/前置转发拓扑执行，而不是只在本地 hosts、mock NAT 或同机端口转发中模拟。

### 4.1 拓扑记录

| 字段 | 记录 |
|---|---|
| 日本 VPS/公网出口 `JP_PUBLIC_IP` | |
| Mieru backend | `JP_PUBLIC_IP:30000/TCP` |
| 中国移动入口 `CM_ENTRY_IP` | |
| Advertised endpoint | `CM_ENTRY_IP:10086` |
| 商家/线路 | |
| 前置转发配置证据 | |
| 测试客户端网络 | |

已安装主机重新配置时明确设置：

```bash
sudo install-mita reconfigure -y \
  --profile iplc \
  --protocol TCP \
  --port 30000 \
  --advertise-host CM_ENTRY_IP \
  --advertise-port 10086
```

若使用干净主机，当前还不存在 `install-mita` 命令。应直接运行已校验的 RC 产物：

```bash
sudo bash ./install-mita.sh
```

在交互菜单选择新装，并明确填写 Profile `IPLC`、protocol `TCP`、backend port `30000`、advertised host `CM_ENTRY_IP`、advertised port `10086`。这种方式避免把真实密码放入命令行；不要把密码写入测试报告。

### 4.2 服务端、firewall 与 tc

```bash
sudo ss -lntp
sudo find /etc/mita/instances -type f -name server.json -print
sudo grep -n -E '(^|[|])10086([|]|$)' \
  /var/lib/mita-oneclick/firewall-owned.bindings \
  /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true
sudo cat /var/lib/mita-oneclick/firewall-owned.bindings 2>/dev/null || true
sudo cat /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true
sudo iptables-save 2>/dev/null || true
sudo nft list ruleset 2>/dev/null || true
sudo sh -c 'tc qdisc show; iface=$(awk -F"|" '\''$1=="iface"{print $2; exit}'\'' /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true); [ -n "$iface" ] || iface=$(ip -o route show default | awk "NR==1{print \$5}"); printf "owned iface: %s\n" "$iface"; [ -z "$iface" ] || { tc qdisc show dev "$iface"; tc filter show dev "$iface" ingress; tc filter show dev "$iface" egress; }'
```

直接解析所有 backend JSON，确认前置入口没有进入服务端配置：

```bash
sudo python3 - <<'PY'
import glob, json
for path in glob.glob("/etc/mita/instances/*/server.json"):
    data = json.load(open(path, encoding="utf-8"))
    def keys(value):
        if isinstance(value, dict):
            for key, child in value.items():
                yield key
                yield from keys(child)
        elif isinstance(value, list):
            for child in value:
                yield from keys(child)
    forbidden = {"advertise_host", "advertise_port", "advertisedHost", "advertisedPort"}
    assert forbidden.isdisjoint(set(keys(data))), path
    bindings = data.get("portBindings", [])
    assert bindings == [{"port": 30000, "protocol": "TCP"}], (path, bindings)
    print("PASS", path, bindings)
PY
```

将代码中的 `CM_ENTRY_IP` 替换为真实值。验收条件：

- [ ] `ss` 只显示真实 backend `30000/TCP`，不监听 advertised `10086`
- [ ] 所有 `server.json` 只写 `30000/TCP`
- [ ] firewall 只管理 backend listener，manifest/规则没有 `10086`
- [ ] tc 只关联真实用户实例/backend，manifest/规则没有 `10086`
- [ ] CM 入口确实把 `CM_ENTRY_IP:10086` 转发到 `JP_PUBLIC_IP:30000`

### 4.3 导出、状态与真实连通性

```bash
mita show
mita perf
mita doctor
sudo find /root/mieru-clients/current -maxdepth 1 -type f -print
```

逐一检查终端中的 `mierus://`、官方 Mieru JSON 和完整 mihomo YAML 片段：

- [x] 三种导出均使用客户端 advertised endpoint
- [x] 三种导出均不泄漏实际 backend 作为客户端连接入口
- [x] `mita show` 显示 `Client -> Backend` 映射
- [x] `mita perf` 显示 `[INFO] 当前使用独立客户端入口`
- [x] Client 显示实际 advertised endpoint
- [x] Backend 显示实际公网地址和监听端口
- [x] `mita perf` 本次完整输出没有 WARN/FAIL
- [x] `mita doctor` 成功
- [x] 真实客户端可经独立入口建立连接并传输数据（执行人后续确认）

### 4.4 IPLC 结果

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| Server evidence | 终端记录中的 `mita show`、`mita perf`、`mita doctor`；缺少 §4.2 的原始快照 |
| CM forwarding evidence | 执行人确认部署后的独立入口可以正常代理；未保存脱敏的商家转发配置 |
| Client connectivity evidence | 执行人确认节点链接和 mihomo 配置均可正常代理 |
| Notes | 客户端功能面已通过；由于 §4.2 的 `ss`、backend JSON、firewall/tc 核对未执行，完整场景仍为 `NOT RUN`。 |

## 5. 实际 mihomo 导入

使用场景 C 的真实导出。把 `mita show` 中完整的 `Clash / mihomo` YAML 片段合并到测试客户端的有效配置中，保留原缩进；不要因某个 GUI 的字段展示方式而修改服务端脚本。配置含密码，保存后立即设为仅当前用户可读，例如 `chmod 0600 /path/to/test-config.yaml`，并关闭会记录配置内容的同步、录屏和诊断上传。

| 字段 | 记录 |
|---|---|
| 客户端名称/OS | |
| mihomo core version | |
| GUI version（若有） | |
| 配置文件 hash（脱敏后） | |
| TCP 测试目标 | |
| UDP 测试方法/目标 | |

先用该 core 自带的配置检查，再实际启动：

```bash
mihomo -v
mihomo -t -f /path/to/test-config.yaml
```

若该版本命令行参数不同，记录实际等价命令和输出，不要把“GUI 接受文本”当作 core 已解析成功。

- [ ] core 配置检查退出码为 0
- [ ] 节点 server/address 为 advertised endpoint
- [ ] 节点 port 为 advertised port
- [ ] 用户名和密码经受保护对照确认正确
- [ ] `udp: true` 被 core 接受
- [ ] TCP 经代理真实传输成功
- [ ] UDP 基础场景经代理真实传输成功
- [ ] 服务端可观察到对应连接/流量
- [ ] 取证完成后已从可销毁客户端清除含凭据的临时 YAML

| 字段 | 记录 |
|---|---|
| Result | `PASS` |
| Evidence | 执行人确认生成的 mihomo 配置已实际部署并可正常代理 |
| Notes | 客户端/core 版本及逐命令、TCP/UDP 分项输出未保留；不得据此宣称官方 Mieru JSON 已验证。 |

## 6. 官方 Mieru 客户端导入

在与服务端分离的真实、可销毁客户端上，使用场景 C 的 URI 和 JSON 各测试一次。不得在服务端对 server JSON 执行 client apply。正式报告不得保存完整 URI 或 JSON。

### 6.1 `mierus://` URI

```bash
mieru version
set +o history
IFS= read -r -s -p 'mierus URI: ' MIERU_ACCEPT_URI
printf '\n'
mieru import config "$MIERU_ACCEPT_URI"
unset MIERU_ACCEPT_URI
set -o history
```

这避免 URI 写入 shell history，但 CLI 设计仍会使它短暂出现在进程参数中；只在单用户、可销毁且无进程采集器的验收客户端执行。

- [ ] URI 导入命令成功
- [ ] address/advertise host 正确
- [ ] advertise port 正确
- [ ] MTU 正确
- [ ] multiplexing 正确
- [ ] handshake mode 正确
- [ ] 用户名/密码正确
- [ ] 可建立连接并真实传输数据

### 6.2 官方 JSON

```bash
chmod 0600 /path/to/generated-client.json
mieru apply config /path/to/generated-client.json
```

- [ ] JSON apply 命令成功
- [ ] address/advertise host 正确
- [ ] advertise port 正确
- [ ] MTU 正确
- [ ] multiplexing 正确
- [ ] handshake mode 正确
- [ ] 用户名/密码正确
- [ ] 可建立连接并真实传输数据

### 6.3 `profile=default` 语义

- [ ] URI 的 `profile=default` 与 JSON 的 `activeProfile: "default"` 对应
- [ ] 它表示上游 Mieru client `profileName`
- [ ] 它没有被解释或改写为 OneClick 的 `iplc|balanced|stealth|custom`
- [ ] 取证完成后已清除客户端上的临时 URI、JSON 和生成配置

| 字段 | 记录 |
|---|---|
| Client OS | |
| Mieru client version | |
| URI result | `PASS` |
| JSON result | `NOT RUN` |
| Evidence | 执行人确认生成的节点链接已实际部署并可正常代理 |
| Notes | 按上下文将“节点链接”记录为 `mierus://` URI；未提供客户端版本或逐命令输出，且未确认 JSON apply。 |

## 7. Backup/restore 真实状态恢复

在可销毁的 systemd 测试机上创建至少两个测试用户后执行。备份文件仍含密码，必须按第 0.2 节保护。

```bash
sudo install-mita user-backup
sudo sh -c 'ls -1t /var/lib/mita-oneclick/backups/users_*.json | head -n 1'
```

将输出的备份路径记为：____________________，并记录：

```bash
sudo sha256sum /path/to/users_backup.json
sudo cp -a /var/lib/mita-oneclick/users.json \
  /root/mieru-acceptance-v2.2.0/users-before-restore.json
```

然后对一个专用测试用户做可观察、可逆的变更，例如：

```bash
sudo install-mita user-disable acceptance-secondary
```

确认 state 和对应实例确实变化，再恢复：

```bash
sudo install-mita user-restore /path/to/users_backup.json
sudo sha256sum /var/lib/mita-oneclick/users.json /path/to/users_backup.json
EXPORT_DIR="$(sudo install-mita user-export-clients /root/mieru-clients)"
sudo test -d "$EXPORT_DIR"
sudo find "$EXPORT_DIR" -maxdepth 1 -type f -exec chmod 0600 {} +
printf 'restore export dir: %s\n' "$EXPORT_DIR"
mita users
mita doctor
sudo systemctl list-units --type=service --all 'mita-oneclick@*.service' --no-pager
```

- [ ] 备份创建成功、权限为 `0600`
- [ ] 变更后 state/实例发生预期变化
- [ ] restore 前自动创建了保护备份
- [ ] restore 后 `users.json` 与所选备份语义一致
- [ ] 用户名、密码、enabled、endpoint、quota、expiration、rate limit 均恢复
- [ ] backend configs、firewall、tc 与恢复后的用户状态一致
- [ ] 所有应启用实例 active
- [ ] `mita doctor` 成功
- [ ] 已把恢复后重新生成的客户端 JSON/URI 安全传到独立客户端
- [ ] 恢复后的客户端导出可建立真实连接

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| Backup SHA-256 | |
| Restore evidence | |
| Notes | |

## 8. 卸载 ownership 真机测试

三个用例必须分别从独立干净快照开始。不要在同一台已经被前一个用例污染的主机上连续得出三个 PASS。

每次安装前记录独立 ownership：

```bash
dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' mita 2>/dev/null || true
rpm -q mita 2>/dev/null || true
getent passwd mita || true
getent group mita || true
sudo ls -la /var/lib/mita-oneclick 2>/dev/null || true
```

每次 OneClick 接管后、卸载前，分别记录以下 marker 是否存在：

```bash
sudo test -e /var/lib/mita-oneclick/preserve-preexisting-package; echo "package marker rc=$?"
sudo test -e /var/lib/mita-oneclick/preserve-preexisting-user; echo "user marker rc=$?"
sudo test -e /var/lib/mita-oneclick/preserve-preexisting-group; echo "group marker rc=$?"
```

### 8.0 三阶段固定证据

每个独立用例都在 OneClick 运行前、接管后、卸载后各执行一次下列只读快照。分别把 `CASE_ID` 设为 `A`、`B`、`C`，把 `PHASE` 设为 `before`、`managed`、`after`：

```bash
CASE_ID=A
PHASE=before
sudo sh -s -- "$CASE_ID" "$PHASE" <<'SH'
case_id=$1
phase=$2
out="/root/mieru-acceptance-v2.2.0/ownership-${case_id}-${phase}"
install -d -m 0700 "$out"
{
  echo '=== package ==='
  dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' mita 2>/dev/null || true
  rpm -q mita 2>/dev/null || true
  echo '=== account ==='
  getent passwd mita || true
  getent group mita || true
  echo '=== ownership markers ==='
  for marker in \
    preserve-preexisting-package \
    preserve-preexisting-user \
    preserve-preexisting-group; do
    if test -e "/var/lib/mita-oneclick/$marker"; then
      echo "$marker=present"
    else
      echo "$marker=absent"
    fi
  done
  echo '=== process and service ==='
  pgrep -a mita || true
  systemctl list-unit-files 'mita*' --no-pager 2>/dev/null || true
  systemctl list-units --type=service --all 'mita*' --no-pager 2>/dev/null || true
  echo '=== OneClick paths ==='
  find /var/lib/mita-oneclick /etc/mita/instances /root/mieru-clients \
    -maxdepth 3 -print 2>/dev/null || true
  find /etc/systemd/system -maxdepth 1 \
    \( -name 'mita*' -o -name 'mita-users*' \) -print 2>/dev/null || true
  echo '=== firewall ==='
  iptables-save 2>/dev/null | grep -F 'mieru-oneclick' || true
  ip6tables-save 2>/dev/null | grep -F 'mieru-oneclick' || true
  nft list ruleset 2>/dev/null | grep -F 'mieru-oneclick' || true
  ufw status verbose 2>/dev/null || true
  firewall-cmd --list-all 2>/dev/null || true
  echo '=== tc ==='
  cat /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true
  iface_record="/root/mieru-acceptance-v2.2.0/ownership-${case_id}-tc-iface.txt"
  iface=$(awk -F'|' '$1=="iface"{print $2; exit}' \
    /var/lib/mita-oneclick/tc-owned.filters 2>/dev/null || true)
  if [ "$phase" = managed ] && [ -n "$iface" ]; then
    printf '%s\n' "$iface" >"$iface_record"
    chmod 0600 "$iface_record"
  elif [ -z "$iface" ] && [ -s "$iface_record" ]; then
    IFS= read -r iface <"$iface_record"
  fi
  [ -n "$iface" ] || iface=$(ip -o route show default 2>/dev/null | awk 'NR==1{print $5}')
  printf 'inspected iface=%s\n' "$iface"
  tc qdisc show 2>/dev/null || true
  [ -z "$iface" ] || tc filter show dev "$iface" ingress 2>/dev/null || true
  [ -z "$iface" ] || tc filter show dev "$iface" egress 2>/dev/null || true
} >"$out/snapshot.txt" 2>&1
chmod 0600 "$out/snapshot.txt"
printf 'wrote %s\n' "$out/snapshot.txt"
SH
```

`managed` 快照必须在卸载前完成，才能保留真实 marker 与 tc iface。对三份快照做人工 diff，并把 package、user、group 分开判定；不得用“其它资源看起来已清理”代替 `dpkg-query/rpm/getent` 的明确结果。

### 8.1 A：clean host

1. 确认 `mita` package、user、group 均不存在。
2. 用当前 RC 安装。
3. 确认 package、user、group 和 OneClick state/config 均由安装产生。
4. 执行：

```bash
sudo install-mita --uninstall -y
```

预期：

- [ ] OneClick 安装的 mita package 被删除
- [ ] OneClick 创建的 mita user 被删除
- [ ] OneClick 创建的 mita group 被删除
- [ ] `/var/lib/mita-oneclick`、`/etc/mita/instances`、实例服务、客户端导出和 owned firewall/tc 均清理
- [ ] 非 OneClick 资源未被删除

Result：`NOT RUN`　Evidence：2026-08-09 的部分运行仅记录到卸载命令正常结束，缺少 §8.0 的三阶段证据和卸载后独立核对；见 §0.4。

### 8.2 B：preinstalled mita package

1. 在 OneClick 运行前，用上游官方包管理流程安装 `mita` package。
2. 记录安装命令、包版本、包校验和、package/user/group 状态。
3. 再用当前 RC 安装并运行。
4. 执行 OneClick 卸载。

预期：

- [ ] `preserve-preexisting-package` marker 存在
- [ ] 卸载后 mita package 仍处于已安装状态，没有被 OneClick uninstall 删除
- [ ] 已记录接管前、接管后和卸载后的包版本/来源；允许 OneClick 安装阶段按既有升级行为更新版本，不要求卸载时恢复旧版本
- [ ] package 所有权没有错误影响 user/group 的独立判定
- [ ] 仅 OneClick 自己拥有的 state/config/service/firewall/tc 被清理
- [ ] 预存包在卸载后仍可由包管理器查询

Result：`NOT RUN`　Evidence：____________________

### 8.3 C：preexisting mita user/group，无预装 package

1. 确认没有 mita package。
2. 按目标系统规范预先创建 `mita` system group 与 system user，并记录 UID/GID、home、shell：

```bash
sudo groupadd --system mita
sudo useradd --system --gid mita --home-dir /var/lib/mita --shell /usr/sbin/nologin mita
getent passwd mita
getent group mita
```

3. 用当前 RC 安装；确认 package 是 OneClick 安装的。
4. 执行 OneClick 卸载。

预期：

- [ ] `preserve-preexisting-user` marker 存在
- [ ] `preserve-preexisting-group` marker 存在
- [ ] `preserve-preexisting-package` marker 不存在
- [ ] OneClick 安装的 package 被删除
- [ ] 预存 mita user 保留且 UID/属性不变
- [ ] 预存 mita group 保留且 GID/属性不变
- [ ] 三类 ownership marker 互不串扰

若目标系统的上游包卸载脚本自行删除预存账号，也必须记录为失败并分析，不能因为行为来自包脚本而自动豁免。

Result：`NOT RUN`　Evidence：____________________

### 8.4 Ownership 汇总

| Test | Resource | Before | Managed marker | After uninstall | Expected | Result |
|---|---|---|---|---|---|---|
| Clean host | Package | | | | absent | `NOT RUN` |
| Clean host | User | | | | absent | `NOT RUN` |
| Clean host | Group | | | | absent | `NOT RUN` |
| Preinstalled package | Package | | | | installed | `NOT RUN` |
| Preinstalled package | User | | | | independently owned | `NOT RUN` |
| Preinstalled package | Group | | | | independently owned | `NOT RUN` |
| Preexisting user/group | Package | | | | absent | `NOT RUN` |
| Preexisting user/group | User | | | | preserved | `NOT RUN` |
| Preexisting user/group | Group | | | | preserved | `NOT RUN` |

每个用例还必须确认 `after` 快照中没有残留 OneClick 实例服务/进程、配置目录、firewall comment 或 tc owned filter；预存外部资源除外。

## 9. 真实 OpenRC 验收

必须使用真实启动了 OpenRC 的 Alpine 主机/VM；Docker 中没有 PID 1/init 的兼容 smoke 不满足本项。

### 9.1 环境

```bash
cat /etc/alpine-release
uname -a
rc-status
rc-update show
apk info -vv bash curl util-linux
```

| 字段 | 记录 |
|---|---|
| Host/VM | |
| Alpine version | |
| OpenRC version | |
| Architecture | |
| Reboot completed | `Yes / No` |

### 9.2 流程

1. 从干净快照 fresh install，选择一个真实可连接的配置。
2. 记录实例服务：

   ```bash
   find /etc/init.d -maxdepth 1 -name 'mita-oneclick-*' -print
   rc-status --all
   rc-update show default
   ls -ld /run/mita-instances /var/lib/mita/instances /etc/mita/instances
   ```

3. 对每个 `/etc/init.d/mita-oneclick-*` 执行 `rc-service <name> status`。
4. 执行 `mita restart`，再次检查 PID、监听和连接。
5. 重启主机，确认实例确实随 default runlevel 自动启动；仅查看 `rc-update` 配置不能替代本步骤。
6. 执行 `mita doctor`。
7. 创建用户备份，修改专用测试用户，再用 `user-restore` 恢复并核对。
8. 执行 OneClick 卸载，检查服务、runlevel、runtime 目录、配置、owned firewall/tc 清理。

验收条件：

- [ ] fresh install 成功
- [ ] `mita-oneclick-<instance-id>` OpenRC 服务 active
- [ ] 服务加入 default runlevel
- [ ] `/run/mita-instances` 等 runtime 目录 owner/mode 正确
- [ ] `mita restart` 正常且恢复连接
- [ ] 实际 reboot 后自动启动正常且客户端重新连接成功
- [ ] `mita doctor` 成功
- [ ] backup/restore 保持用户状态且重新 apply/tc 成功
- [ ] uninstall 删除 OneClick 拥有的 OpenRC 服务、runlevel 项和 runtime/state
- [ ] uninstall 保留所有预存资源

无法执行 reboot 时，本场景不能标记 PASS；保持 `NOT RUN`/incomplete，并交由维护者按下一节作 blocking 决策。

### 9.3 无完整 OpenRC 环境时

- 没有真实 OpenRC 主机或无法完成 reboot 时，Result 必须为 `NOT RUN`。
- [ ] `docs/RELEASE-CHECKLIST-v2.2.0.md` 中 `Real OpenRC verification` 保持未勾选。
- 由项目维护者明确决定其发布属性，不得由执行人默认为 non-blocking。

### 9.4 OpenRC 结果

| 字段 | 记录 |
|---|---|
| Result | `NOT RUN` |
| Maintainer decision | `BLOCKING / NON-BLOCKING / 未决定` |
| Decision owner/date | |
| Rationale | |
| Evidence | |

## 10. 真实沪日 IPLC 性能 A/B

性能数据与功能验收分开记录。除非发现相对旧版或已知基线的明显 regression，否则参数优劣不阻塞 v2.2.0，也不得据此修改 v2.2.0 默认 Profile；数据留给 v2.2.1 分析。

### 10.1 固定条件

四组测试必须保持相同的：

- 服务端、客户端、CM 入口与路由
- Mieru 版本和测试时段（或记录时段差异）
- 测试文件/数据量、单连接持续时间、多连接并发数
- BBR/qdisc、CPU 配额、限速与其它系统负载
- 测量工具与版本
- 每组预热方式、重复次数和取值方法

| 固定条件 | 记录 |
|---|---|
| Raw-line tool/command | |
| Proxy download/upload tool | |
| Test object/size | |
| Single connection duration | |
| Multi connection count | |
| Repetitions | |
| RTT target | |
| Server/client CPU method | |
| Retransmit method | |
| Interface-byte method | |

建议在每组开始和结束记录默认接口计数、TCP 重传和进程资源；若系统缺少相应工具，记录替代方法：

```bash
iface=$(ip -o route show default | awk 'NR==1{print $5}')
date -Ins
cat /sys/class/net/"$iface"/statistics/rx_bytes
cat /sys/class/net/"$iface"/statistics/tx_bytes
nstat -az TcpRetransSegs 2>/dev/null || true
ss -ti
ps -C mita-real -o pid,pcpu,rss,etime,args
```

### 10.2 A-D 参数矩阵

| Case | Protocol | MTU | MUX | Handshake | Traffic Pattern | Low Entropy |
|---|---:|---:|---|---|---|---|
| A | TCP | 1400 | OFF | NO_WAIT | OFF | OFF |
| B | TCP | 1400 | OFF | NO_WAIT | conservative | OFF |
| C | TCP | 1400 | LOW | NO_WAIT | OFF | OFF |
| D | TCP | 1360 | OFF | NO_WAIT | OFF | OFF |

每组应用参数后运行 `mita show` 保存实际值，等待相同稳定时间，再开始测量。使用现有 IPLC advertised endpoint，不改变 backend/advertise 拓扑。

可参考以下配置命令；将 endpoint 占位符替换为场景 C 的真实值，以避免误触自动入口：

```bash
# A
sudo install-mita reconfigure -y --protocol TCP --mtu 1400 \
  --multiplexing off --handshake-mode no-wait \
  --traffic-pattern off --low-entropy off \
  --advertise-host CM_ENTRY_IP --advertise-port 10086

# B
sudo install-mita reconfigure -y --protocol TCP --mtu 1400 \
  --multiplexing off --handshake-mode no-wait \
  --traffic-pattern conservative --low-entropy off \
  --advertise-host CM_ENTRY_IP --advertise-port 10086

# C
sudo install-mita reconfigure -y --protocol TCP --mtu 1400 \
  --multiplexing low --handshake-mode no-wait \
  --traffic-pattern off --low-entropy off \
  --advertise-host CM_ENTRY_IP --advertise-port 10086

# D
sudo install-mita reconfigure -y --protocol TCP --mtu 1360 \
  --multiplexing off --handshake-mode no-wait \
  --traffic-pattern off --low-entropy off \
  --advertise-host CM_ENTRY_IP --advertise-port 10086
```

### 10.3 数据表

原始线路 throughput 应绕过 Mieru 测量；其余项目经同一个 Mieru 客户端入口测量。每个数字注明单位和汇总方法（median/mean/best）。

| Metric | A | B | C | D | Method/Notes |
|---|---:|---:|---:|---:|---|
| Raw-line throughput | | | | | |
| Single-connection download | | | | | |
| Multi-connection download | | | | | |
| Upload | | | | | |
| RTT | | | | | |
| Server CPU | | | | | |
| Client CPU | | | | | |
| TCP retransmit delta | | | | | |
| Server interface RX bytes | | | | | |
| Server interface TX bytes | | | | | |

| 字段 | 记录 |
|---|---|
| Functional regression found | `Yes / No / NOT RUN` |
| Performance-only finding | |
| Result | `NOT RUN` |
| Evidence | |

## 11. Release blocker 判定

以下任一项确认失败，发布建议必须为 `BLOCKED`：

- fresh install 失败
- systemd 实例无法启动或保持运行
- `mita doctor` FAIL
- v2.1.x 原地升级修改旧用户的真实配置
- Profile 推导把 MTU 1388 等旧参数改成预设值
- advertised endpoint 写入 backend server config/listener
- endpoint-only 更新导致实例重启、PID/start timestamp、backend config、firewall 或 tc 变化
- 生成的 mihomo 配置无法被真实 core 使用
- 官方 Mieru URI 或 JSON 无法导入/连接
- uninstall 删除预存 package、user、group 或其它外部资源
- backup/restore 损坏或丢失用户状态

以下通常不阻塞，但必须记录：

- `mita perf` 中不影响判定的 INFO 文案
- 没有达到性能预期，但没有相对基线的明显 regression
- cosmetic 输出问题
- 当前没有真实 OpenRC 主机；此项只有在维护者明确书面决定 `NON-BLOCKING` 后才不阻塞

“疑似 bug”不能直接写 PASS。先保存证据，复现并判断是否为：真实产品 bug、测试环境问题、客户端 UI 差异或操作错误。只有确认真实 bug 后，才另行授权最小修复并重跑受影响及相关回归场景。

## 12. 最终 Release Acceptance 报告

真实测试完成后再创建 `docs/RELEASE-ACCEPTANCE-v2.2.0.md`。在此之前不要创建带有 READY/BLOCKED 结论的正式报告，也不要把本清单中的 `NOT RUN` 改成 PASS。

正式报告至少包含：

| Test | Environment | Result | Notes |
|---|---|---|---|
| Fresh install | | | |
| v2.1 upgrade | | | |
| Default endpoint | | | |
| IPLC endpoint | | | |
| Endpoint-only update | | | |
| mihomo | | | |
| Mieru URI | | | |
| Mieru JSON | | | |
| Backup/restore | | | |
| Uninstall clean host | | | |
| Uninstall preinstalled package | | | |
| Uninstall preexisting user/group | | | |
| Doctor | | | |
| Perf | | | |
| OpenRC | | | |

最终只能给出一个结论：

```text
Release recommendation: READY
```

或：

```text
Release recommendation: BLOCKED
```

若为 `BLOCKED`，只列真正 blocker；non-blocking 和性能观察放在单独小节。若关键真实场景尚未执行或 OpenRC blocking 决策尚未作出，则不得给出 `READY`。
