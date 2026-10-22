# Native Linux qualification — Splicore rc.4

日期：2026-10-22。冻结实现：`b5440ec41aeed2dd266b3a7008f75a26de63add2`；
sole parent：`f98cf70e7159c07826101676a4a08394f0a203f9`。
本文件描述资格基础设施和未来专用主机的操作规程，不授予当前机器资格。

**当前 campaign 因 DEFECT-1 阻塞：HY2/TUIC 卸载后同名重装失败。**
本轮只保存证据，停止受影响资格，不修冻结业务代码。独立回归仍可执行。
详见 [资格报告](reports/SPLICORE_RC4_NATIVE_LINUX_CI_QUALIFICATION_REPORT.md)。

## 支持范围与状态

| 平台 | 架构 | Init/范围 | 状态 |
|---|---|---|---|
| 原生 Linux | amd64 | systemd 完整安装、服务、流量 | PENDING ENVIRONMENT；重装另有 DEFECT-1 |
| 原生 Linux | arm64 | systemd 完整运行 | PENDING ENVIRONMENT；公开制品静态验证 PASS |
| 原生 Linux | amd64 | OpenRC | 产品已支持；运行 PENDING ENVIRONMENT |
| Ubuntu WSL2 | amd64 | 临时回环进程、fixture supervisor | 本地回归 PASS；不是原生服务资格 |
| NoBrand HY2 | amd64 | nftables UDP port hopping/range | N/A — NoBrand NOT EXPOSED |
| GitHub Actions | amd64 | 冻结回归和回环探针 | 本地入口 PASS；外部 PENDING UNTIL PUSH |

冻结代码已有 systemd 和 OpenRC adapter。`process` 是临时探针，`fixture` 是显式测试替身，
不代表新增 init 支持。普通协议为 Mieru、Snell、HY2、TUIC、VLESS REALITY；
现有 Sudoku 专用 Xray 例外、SSH、Forward 的真实主机运行资格单独保留。
Core 的 Gecko/UDP hopping/range 能力不能视为 NoBrand 已暴露功能。

## 可立即执行的安全入口

要求 Linux amd64、Python 3.10+、PyYAML、Bash、Git、curl、OpenSSL、jq、
tar/coreutils、iproute2、util-linux、OpenSSH client、ShellCheck、systemd-analyze、
actionlint v1.7.7。完整入口要求 ShellCheck、actionlint、systemd-analyze 均可用；
单独 `static` 在缺工具时明确 SKIP，不能据此宣称 CI 入口全通过。
依赖安装由操作者在专用环境预先完成；helper 不安装宿主包。

在仓库根目录运行，每次使用**新的**私有 evidence 目录：

```bash
umask 077
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/qualify-splicore.py inventory
python3 scripts/qualify-splicore.py static --evidence .lab/native-ci/static-01
python3 scripts/qualify-splicore.py assets --evidence .lab/native-ci/assets-01
python3 scripts/qualify-splicore.py ci --evidence .lab/native-ci/ci-01
```

`ci` 默认重新通过 HTTPS 获取公开的 rc.4 双架构 archives、SHA256SUMS 和固定的
Mihomo v1.19.30 gzip。执行前检查 manifest 固定 digest、checksum、archive 安全、
ELF 架构、binary digest、原生 amd64 的 `version --json`。arm64 不在 amd64 上执行。
下载使用冻结实现的有限超时和有限重试，外层回归有 1800 秒超时，workflow 有 35 分钟上限。

如显式复用公开缓存，仍重新验证完整安全链：

```bash
python3 scripts/qualify-splicore.py ci \
  --artifacts .lab/native-ci/assets-01/assets \
  --mihomo-gzip .lab/native-ci/assets-01/assets/mihomo-linux-amd64-v1.19.30.gz \
  --evidence .lab/native-ci/ci-02
```

`ci` 执行 `bash scripts/test.sh --runtime`，保留冻结的 28 个 Bash 入口、37 个
Python 测试、42 项公开 rc.4 回环检查，另加资格基础设施测试。它验证冻结回归，
**不执行 DEFECT-1 独立复现，也不判断整个 native campaign READY**。
探针的 restart/SIGKILL 恢复由本地 Supervisor 驱动，未证明真实 init 自动恢复。
实际生成的 systemd unit 仅写入临时目录供 `systemd-analyze verify`，OpenRC 仅 `sh -n`。
不会安装 unit、调用宿主服务、修改 firewall/nftables、账户或网络栈。

JSON `summary.json` 记录命令、退出码、UTC 时间、脱敏 OS/内核/架构/init 版本。
不记录主机名、IP、密钥或客户端配置。私有 regression/process logs 可能包含合成测试材料，
仅保存在被忽略的 `.lab` 或仓库外私有目录；不提交、不自动上传。
成功退出 0，失败退出 1；输出目录已存在也拒绝覆盖。删除这些 evidence 仅删除该次明确目录，
先停止仍在运行的 campaign；helper 的临时状态和正常结束的进程由 context/finally 清理。

## DEFECT-1 的独立复现

此入口只使用临时回环进程，以冻结 runtime CLI parser/dispatcher 执行真实安装、卸载和重装。
它替换服务调用，使用校验后的公开二进制，生成临时证书，退出时停止进程并清除临时状态。
它不执行完整 Bash 安装界面或真实 systemd。已确认的失败不改成 xfail/PASS。

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/qualify_splicore_reinstall.py \
  --artifacts .lab/native-ci/assets-01/assets \
  --evidence .lab/native-ci/reinstall-01
```

返回 1 = `IMPLEMENTATION_DEFECT`；返回 2 = 复现基础设施未完成；返回 0 = 此项未再复现失败，
仍需独立复核和原生资格。冻结版本中四种组合均失败：HY2/TUIC × protocol uninstall/runtime uninstall。
`nobrand uninstall` 的全局路径会调用 purge，未据此认定全局卸载也有同样缺陷。
本轮不再扩展受影响重装测试，等待维护者单独开启 Fix Phase。

## 外部 CI

`.github/workflows/ci.yml` 使用一个 `ubuntu-24.04` ephemeral hosted runner，
`contents: read`；checkout 固定 SHA、完整取回基线、禁用凭据持久化。
actionlint 固定 v1.7.7；不访问未发布 Core，不使用 latest、容器、业务服务器、
self-hosted label、真实 secrets、schedule、发布/tag/push。
仅未来的 ephemeral runner 安装测试依赖；`git diff --exit-code` 拒绝 tracked 文件漂移。

本地 actionlint/YAML/权限合同通过不等于外部 Actions 通过。
外部执行需维护者后续单独授权 push；本轮没有执行 push、dispatch 或远程写操作。
未来保留 run URL、实际 commit、runner、开始/结束时间、退出状态和 sanitized summary，
不自动上传私有 raw logs。冻结回归绿灯也不能解除本报告中的实现缺陷。

## 未来原生主机规程：仅专用可销毁环境

当前维护者已确认没有专用环境。下列为**未执行**的手工规程。
要求空白 VM/专用测试主机、无业务数据、控制台/恢复能力、专用测试端口和合成凭据；
不得在日常 WSL、生产或客户 VPS 执行。WSL 即使 PID 1 为 systemd，标签仍须写 WSL。

生命周期操作会安装包/manager/unit，启停服务、写入配置并打开/关闭防火墙端口。
每次进入测试 shell，先定义统一 opt-in 门；三个变量须由操作者明确设置，文档不代填：

```bash
nbq_run() {
  [ "${NBQ_QUALIFICATION_HOST:-}" = disposable ] &&
    [ "${NBQ_ALLOW_SYSTEM_SERVICE_CHANGES:-}" = yes ] &&
    [ "${NBQ_ALLOW_FIREWALL_CHANGES:-}" = yes ] &&
    [ "$(id -u)" -eq 0 ] || {
      printf 'Refused: disposable host and explicit service/firewall opt-ins required\n' >&2
      return 2
    }
  "$@"
}
```

所有下述**变更**命令均通过 `nbq_run`，只在对应主机确认完成后运行。
若未来新增自动 native/package/nft helper，必须提供同等显式 opt-in；不能隐式复用本地 CI 模式。
本轮不执行任何 nft rule 操作；未来若功能获准暴露，另需 `--allow-nftables` 级别 opt-in。

### 1. 环境和 clean preflight

记录 OS/VERSION_ID、kernel、`uname -m`、PID 1、systemd/OpenRC 和必要的 nft 版本、
NoBrand commit、Core identity、UTC 时间。使用 `inventory` 作版本采集，不输出 hostname/IP。
只在已确认专用主机检查实际 ownership 路径、已安装包、监听端口及 service 冲突；
legacy marker 存在则 fail closed，不自动清除。绝不以查询其他业务组件作为 preflight。
保存最小化权限/文件清单和 owned firewall bindings 基线，供清理比较。

### 2. Fresh install 与布局

只运行本次 checkout 生成的 `install-nobrand.sh`，不下载另一个 latest installer。
按 `help` 和主机实际接口建立测试 Ingress；显式提供专用 port、display host 和证书 SNI。
示例（`NBQ_TEST_HOST`、`NBQ_TEST_PORT` 由操作者选择；安装输出私存，含新客户端凭据）：

```bash
: "${NBQ_TEST_HOST:?set dedicated test display host}"
: "${NBQ_TEST_PORT:?set vacant test UDP port}"
nbq_run bash install-nobrand.sh hy2 install --port "$NBQ_TEST_PORT" \
  --advertise-host "$NBQ_TEST_HOST" --sni probe.example -y
```

确认真实 HTTPS 下载和 `SHA256SUMS`、archive/binary digest、ELF architecture、
执行后的 rc.4 identity，而不是把已缓存版本号当成新下载证据。
默认 state `/var/lib/nobrand-oneclick/splicore`，TLS `/etc/nobrand-oneclick/splicore/tls`，
manager lib `/usr/local/lib/nobrand-oneclick`，lifecycle `/var/lib/nobrand-oneclick-lifecycle`；
以实际 env override 和 generation 为准。检查 binary/launch 0700、generation 0700、
master key/TLS key 0600、TLS parent 0700、root ownership、备份 0600；日志不含 secrets。
保留目录/权限证据，不收集文件中的密钥或完整 client profiles。

### 3. Unit、启动和故障恢复

systemd unit 为 `/etc/systemd/system/nobrand-splicore.service`。
检查 `systemctl cat/show`：`ExecStart=<python3> <current>/launch.py`、
`WorkingDirectory=<current>`、`User=root`、`Group=root`、`UMask=0077`、
`Restart=on-failure`、`RestartSec=3`、`LimitNOFILE=1048576`、
network-online.target 的 After/Wants、NoNewPrivileges、PrivateTmp、ProtectSystem=strict、
ProtectHome=read-only、ReadWritePaths。冻结 unit 无显式 Environment/CapabilityBoundingSet。
root 是现有设计：管理 API/本地私有状态和包括低端口在内的监听权限；未证明每项 root 权限都必需。
不得临时改用户/Capabilities 来通过测试。

```bash
nbq_run systemctl daemon-reload
systemctl is-enabled nobrand-splicore.service
systemctl is-active nobrand-splicore.service
nbq_run systemctl restart nobrand-splicore.service
nbq_run systemctl stop nobrand-splicore.service
nbq_run systemctl start nobrand-splicore.service
nbq_run systemctl kill --signal=SIGKILL --kill-whom=main nobrand-splicore.service
```

安装应自行 enable/start，先验证它的效果再做手工 lifecycle，避免掩盖产品缺陷。
每步记录 PID、unit result、listener、协议流量、单一进程和 bounded 恢复时间；SIGKILL 后
应由 init 自动恢复，不能手工 start 后宣称自动恢复。正常 stop 检查 SIGTERM 后端口释放、
state 完整、再次 start 正常；检查 stale PID/socket/lock、重复进程和临时文件。
可执行低端口绑定用例时使用专用端口 <1024，记录实际 UID/capability，不增添权限。
原始 journal 私存，只公开按该次合成凭据扫描得到的计数和脱敏错误。

reboot 只有控制台/重连可保证、明确允许销毁的主机才执行；另要求
`NBQ_ALLOW_REBOOT=yes` 后通过门控运行。重连后验证 enable、state、listeners、真实 traffic。
不满足则 **REBOOT = NOT EXECUTED**。

### 4. 事务、状态和流量用例

| 用例 | 操作及证据要求 |
|---|---|
| invalid config | 私有 candidate file 故意无效；`runtime apply --file` 应在 publish/start 前拒绝；live generation、key 和 traffic 不变 |
| runtime failure rollback | 在专用 host 用独立的可恢复 synthetic fixture 制造候选健康失败；保留 last-known-good，验证 pointer、service、traffic 恢复；无法安全制造则 NOT EXECUTED |
| bad binary | corrupt/wrong identity 的本地测试 archive；校验拒绝，live digest/key/PID 不变；不访问未发布版本 |
| same-version | `runtime apply --file` 提交相同 canonical graph；VERIFY/NO-OP，PID、credential、certificate 均不变 |
| status/doctor | `runtime status`、`runtime doctor` 和协议入口；区分 architecture marker `splicore-native` 与 CPU arch 字段；Core=Splicore、精确 rc.4、真实 active、协议清单 |
| legacy refusal | 独立 synthetic system/state root 的旧 ownership marker；拒绝发生在 lock/package/download/service 前；字节不变 |
| false positive | 不属于 NoBrand 的同名第三方 binary；不认领、不改动；不安装真实旧 Core |

这些 product 命令同样通过 `nbq_run`；candidate graph 和 profile 只保留在私有目录。
临时回环 probe 可以重复验证 Core，但证明 host unit 的流量测试必须连接**该 unit 管理的 daemon**。
将 client、TCP/UDP echo、固定 cover target 限于独立测试主机/回环，不扫描外部节点。

| 协议/网络 | 最小 native 验证 |
|---|---|
| REALITY | 新 valid client、Vision、Local Tunnel Guard；wrong UUID/short-id/SNI；plain TLS、HTTP、random TCP、malformed TLS、no usable SNI；仅 approved SNI 到固定 cover，无 arbitrary SNI forwarding/open proxy |
| HY2 | 新 private CA/non-CA leaf、显式 trust、Salamander、TCP/UDP/domain target、restart/crash recovery；wrong auth/obfs/pin 拒绝 |
| Mieru | TCP/UDP/BOTH 各自 native validation/start/basic traffic；当前回环仅 TCP，不扩称全 transport PASS |
| Snell | v4/v5 按已暴露范围；QUIC off；真实 TCP/UDP，记录客户端 wire version |
| TUIC | v5 validation/start/basic TCP/UDP、trust 和用户配置 |
| IPv4/IPv6 | 分别验证 listener、connection、TCP/UDP 和 domain resolution；没有真实 IPv6 写 NOT AVAILABLE IN TEST ENVIRONMENT |
| DNS | 记录 NoBrand 实际生成的 resolver 配置；domain success/controlled resolver failure；不能用偶然的 system resolver 成功代替 Core DNS 合同 |
| TLS | OpenSSL inspection：BasicConstraints、KeyUsage、EKU、SAN、issuer/subject、validity、public-key matching；不打印 private key |

### 5. 卸载、重装和清理

区分 protocol remove（删除 node）、`runtime uninstall`（保留 state/TLS）、
`runtime purge`（删除 owned state/TLS）和全局 `nobrand uninstall`（还涉及保留模块）。
**DEFECT-1 对应前两条路径的 HY2/TUIC 同名重装，本轮已停止，等待独立 Fix Phase。**
其它清理检查只删除该 campaign 明确认领的资源，不把全局卸载用于未知主机。

在专用 host 通过门控执行 `nobrand runtime uninstall` / `nobrand runtime purge`；
确认 stop、disable、unit removal、当前 binary/config/state 保留或删除语义、第三方 sentinel 完整。
purge 后检查无 owned service/process/listener/foreign socket，owned firewall bindings 归零；
不得 flush 全局规则，不得删除整个父目录或使用空变量路径。测试端口释放；临时文件清理。
证据目录保留至 review，原始秘密不进入提交。优先销毁专用 VM 恢复初始状态，再验证可重跑。

### 6. OpenRC 与 arm64

OpenRC 已正式存在：`/etc/init.d/nobrand-splicore`、root:root、supervise-daemon、
respawn_delay=3、respawn_max=0、umask0077、need net；检查 default runlevel。
在专用 OpenRC 主机通过相同 opt-in 执行 rc-service 生命周期/rc-update，检查启动、流量、
crash recovery、boot persistence、uninstall/purge；`sh -n` 不能代替这些运行结果。

arm64 必须真实 aarch64/arm64 VM 或硬件，记录架构映射、arm64 archive/hash/identity，
执行 fresh install、systemd、REALITY/HY2 traffic/restart/cleanup。当前 helper 的 CI 模式仅 amd64，
需未来在 arm64 环境运行独立 campaign，不能在此伪装支持交叉执行。

## 结果、失败分类和停止条件

每条 case 记录 command、exit code、UTC 时间、环境和最小脱敏输出；PASS/FAIL/PENDING/N/A
必须附范围。分类限以下六种：

| Classification | 使用条件 |
|---|---|
| IMPLEMENTATION_DEFECT | 冻结产品在有效环境/输入下的可复现缺陷；保留证据、停止该项、禁止本轮修复 |
| QUALIFICATION_ENVIRONMENT | 缺少专用 host/工具/权限/IPv6 等；相应项保持 PENDING 或明确不可用 |
| INFRASTRUCTURE | 公网下载、外部 runner、有限超时等失败；不据此定罪产品 |
| TEST_HARNESS | fixture、日志完整性、workflow 合同或测试驱动异常；允许修基础设施后复跑 |
| UNSUPPORTED_PLATFORM | helper/产品明确未支持的架构或 init，不能伪造资格 |
| EXPECTED_LIMITATION | 合同内默认关闭/未暴露能力，例如 NoBrand HY2 range N/A |

若真实缺陷有全局安全影响，停止整个 campaign；否则继续独立资格。
本轮不 stage/commit/push/tag/release，不改历史/freeze 报告，不开始 Fix Phase。
