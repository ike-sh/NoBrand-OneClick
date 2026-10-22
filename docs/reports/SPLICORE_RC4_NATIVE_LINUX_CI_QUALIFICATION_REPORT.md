# NoBrand-OneClick Splicore rc.4 Native Linux & CI Qualification Report

日期：2026-10-22（Asia/Shanghai）。范围：冻结实现资格、外部 CI 准备；不含 Fix Phase。

**NATIVE LINUX & CI QUALIFICATION BLOCKED — IMPLEMENTATION DEFECT FOUND**

CI 基础设施和独立冻结回归已准备；HY2/TUIC 卸载后同名重装的确定缺陷阻止总体 READY。
维护者明确答复“暂无专用环境，先完成 CI 和资格准备”，原生服务资格继续等待环境。

## Baseline

| 项目 | 值 |
|---|---|
| Frozen Commit | `b5440ec41aeed2dd266b3a7008f75a26de63add2` |
| Sole Parent | `f98cf70e7159c07826101676a4a08394f0a203f9` |
| Qualification Branch | `codex/qualification-splicore-rc4-linux-ci` |
| HEAD / main | 均为 Frozen Commit；未新增 commit |
| Product Implementation Modified | NO |
| Primary Core | Splicore `v0.3.0-rc.4` |
| Public Core commit | `2634ea50d19623591c5db63329a288862726db74` |
| 架构合同 | Fresh install only；旧多 Core 原地迁移 NOT SUPPORTED；legacy detection fail closed |

开始时按要求只读执行 status、branch、HEAD/main、freeze fuller、parents、graph log、
remote、tags，确认 clean/index empty、基线和 sole parent 一致后才从 main 创建资格 branch。
未修改 main、历史或冻结证据。私有 preflight 和 190 个基线文件的 hash 清单留在被忽略目录。

## Environment Inventory

| 项目 | 实际发现与资格范围 |
|---|---|
| Windows host | Windows `10.0.26300.0`；只读版本/工具发现 |
| WSL | Ubuntu 24.04，x86_64，WSL2；日常环境，非专用可销毁资格主机 |
| Kernel | `6.6.87.2-microsoft-standard-WSL2` |
| PID 1 / systemd | systemd；`255 (255.4-1ubuntu8.18)` |
| nft version | `1.0.9`，仅 `--version`；未读取或修改真实规则 |
| Native Linux amd64 | NOT AVAILABLE / 未确认任何专用目标 |
| Native Linux arm64 | NOT AVAILABLE |
| OpenRC | 产品支持 YES；专用运行环境 NOT AVAILABLE |
| nftables qualification host | NOT AVAILABLE；NoBrand HY2 range 本身未暴露 |
| VM tooling | 未发现可用的专用 VM 工具/环境；未连接未知 SSH host |

本地结果准确标签为 **Linux amd64 WSL2 temporary loopback**。
WSL 的 systemd PID 1、unit 静态验证和进程 probe 都不是 native Linux service certification。
环境采集不包含 hostname/public IP/credentials。

## Qualification Matrix

| Platform | Arch | Init | Core | Scope | Status |
|---|---|---|---|---|---|
| Native Linux | amd64 | systemd | rc.4 | FULL | PENDING ENVIRONMENT；重装受 DEFECT-1 阻塞 |
| Native Linux | arm64 | systemd | rc.4 | FULL | PENDING ENVIRONMENT |
| Native Linux | amd64 | OpenRC | rc.4 | FULL，已有产品支持 | PENDING ENVIRONMENT |
| NoBrand Linux | amd64 | nftables | rc.4 | HY2 UDP port hopping/range | N/A — NOT EXPOSED |
| WSL2 Linux | amd64 | local Supervisor | rc.4 | 冻结回归/回环 | PASS；另有独立重装 FAIL |
| External CI | amd64 | hosted runner | rc.4 | regression | 本地入口 PASS；外部 PENDING UNTIL PUSH |

## Linux amd64 systemd

Environment：无安全的 dedicated native Linux host。
下表的 PENDING 均指原生宿主资格，不能用右列的替身/静态结果替代。

| 项目 | Native 结果 | 本地证据/限制 |
|---|---|---|
| Fresh Install | PENDING ENVIRONMENT | 公开二进制+真实新装 builder 的临时回环 PASS；未执行 native Bash/service 安装 |
| Artifact | native installed identity PENDING | 公开下载、checksum、archive/ELF/digest、amd64 version identity PASS |
| Filesystem/ownership | PENDING | private fixture 权限及 key/backup 测试 PASS；不是宿主路径证明 |
| Service Install | PENDING | actual generated unit 的 `systemd-analyze verify` exit 0 |
| Enable / Start | PENDING | fixture enable/start PASS，不是 systemctl 运行证据 |
| Restart | PENDING | local Supervisor restart 后五协议流量 PASS |
| SIGTERM | PENDING | probe 正常停止进程不等同 systemd 优雅 shutdown 资格 |
| SIGKILL Recovery | PENDING | local Supervisor 手工恢复后五协议流量 PASS；未证明 init 自动恢复 |
| Reboot | NOT EXECUTED | 无可安全 reboot/reconnect 的专用环境 |
| Start/config failure | PENDING | native validation 与 candidate rejection/rollback 测试 PASS |
| Config Rollback | PENDING | 实际 Core synthetic health failure 后 generation 和 REALITY/HY2 流量恢复 PASS |
| Binary Rollback | PENDING | corrupt/wrong identity gate、candidate failure fixtures PASS；未访问未发布版本 |
| Same-version Update | PENDING | 实际 rc.4 VERIFY/NO-OP，不重复启动，PASS |
| Doctor / Status | PENDING | 冻结 Python/Bash fixtures PASS；无 native active/listeners 证据 |
| Low-port / privilege | PENDING | 冻结 unit 使用 root:root，无本轮低端口实测 |
| Journal / resources | PENDING | 未采集宿主 journal；本地进程正常清理，不替代 unit 生命周期检查 |
| Uninstall | PENDING | 实际 Core 的临时 uninstall+purge PASS |
| Reinstall | native NOT EXECUTED；对应产品用例 FAIL | DEFECT-1：HY2/TUIC 删除后或保留 state 卸载后，同名安装失败 |
| Purge / host cleanup | PENDING | 临时 owned state 清理 PASS；没有安装宿主服务/规则 |
| Result | PENDING ENVIRONMENT | Overall campaign BLOCKED by DEFECT-1 |

冻结 systemd 设计已审计：

- unit `/etc/systemd/system/nobrand-splicore.service`；`ExecStart=<python3> <current>/launch.py`，launcher 最终 exec Core；`WorkingDirectory=<current>`。
- root:root、UMask0077、Restart=on-failure、RestartSec=3、LimitNOFILE=1048576。
- After/Wants=network-online.target；WantedBy=multi-user.target；无显式 Environment。
- NoNewPrivileges、PrivateTmp、ProtectSystem=strict、ProtectHome=read-only、ReadWritePaths=owned Splicore home。
- generation/binary 私有；master key/TLS private key 0600、TLS parent 0700；备份 0600。
- root 是冻结实现的现有策略，提供低端口绑定和私有状态访问能力；本轮没有证明各权限的必要性，也没有为资格修改用户或 capabilities。

详细未来 campaign、显式 opt-in 门和清理规程见 [Native Linux Qualification](../NATIVE-LINUX-QUALIFICATION.md)。

## Runtime Traffic

本节 PASS 仅限公开 rc.4 + 固定 Mihomo v1.19.30 客户端在 WSL2 的临时回环进程。
一台 primary daemon、5 个 managed inbounds、1 个 native loopback guard；不是原生服务结果。

| 协议 | 新装/native validation | 初始真实 traffic | restart 后 | SIGKILL+local recovery 后 |
|---|---|---|---|---|
| VLESS + REALITY + Vision | PASS | PASS | PASS | PASS |
| HY2 + Salamander + 新 TLS trust | PASS | PASS，TCP/UDP | PASS | PASS |
| Mieru TCP | PASS | PASS | PASS | PASS |
| TUIC v5 | PASS | PASS，TCP/UDP | PASS | PASS |
| Snell v5 server / rc.4 documented v4 client wire | PASS | PASS，TCP/UDP | PASS | PASS |

Mieru UDP/BOTH、Snell 其它版本组合未新增真实流量资格；fixture/config 覆盖不能扩大为 runtime PASS。
Sudoku/SSH/Forward 保留当前配置/事务回归，真实 host/network campaign 未执行。
可选真实 Sudoku Xray validation 明确 SKIP；没有下载普通旧 Core，也未计入 42 项。

### REALITY Probe Matrix

| Probe | 回环结果 |
|---|---|
| 正确新客户端 / native Local Tunnel Guard / pre-cutover validation | PASS |
| wrong UUID / short-id / client SNI | PASS：无可用代理流量 |
| approved plain TLS | PASS：只到固定 cover |
| unapproved TLS SNI | PASS：拒绝 |
| HTTP / random TCP / malformed TLS / missing or unusable SNI | PASS：public 和直接 guard 均 fail closed |
| arbitrary sniffed SNI forwarding / open proxy / unexpected fallback | 本次安全探针未观察到；固定目标拒绝用例 PASS |

### HY2、网络与证书

- 新 CA + 非 CA server leaf、OpenSSL extension/trust gate：已有 10 项 fresh Python suite 及实际握手 PASS；未使用旧证书。
- Salamander、wrong auth、wrong obfs、wrong certificate pin 拒绝：PASS；TCP/UDP payload 与 profile 信任一致。
- IPv4：loopback listener/TCP/适用 UDP PASS；UDP payload 64/512 bytes。原生外网 IPv4资格 PENDING。
- IPv6：本 campaign 未建立具备真实 IPv6 的测试端点，**NOT AVAILABLE IN TEST ENVIRONMENT**；未列实现 FAIL。
- DNS/domain target：42 项现有探针不提供独立 native Core resolver/failure 或全部 domain-target 合同证明，**NOT EXECUTED / PENDING**。
- 原生 fresh certificate 的完整 ownership、public-key matching、service 可读性及重启后流量，仍需专用 host。

## OpenRC

Product Support：**YES**，已存在 `Service`/unit generator，不是本轮新增功能。

生成脚本 `/etc/init.d/nobrand-splicore` 使用 root:root、supervise-daemon、
respawn_delay=3、respawn_max=0、umask0077、need net；default runlevel 由 rc-update 管理。
本地临时生成后 `sh -n` exit 0。install/enable/start/status/restart/crash/boot/uninstall/purge
均未在真实 OpenRC 环境执行。

Qualification：**PENDING ENVIRONMENT**。

## arm64

| 项目 | 结果 |
|---|---|
| Architecture mapping | frozen `aarch64/arm64` mapping 及拒绝非法架构 fixtures PASS |
| Artifact | 官方 rc.4 arm64 archive/checksum、成员安全/ELF、binary digest PASS |
| Executed arm64 version | NOT EXECUTED；未在 amd64 冒充执行 |
| Real Hardware/VM | NO |
| Runtime / REALITY / HY2 / Restart | PENDING ENVIRONMENT |
| Result | PENDING ENVIRONMENT；BUILD/ARTIFACT ONLY，runtime NOT CERTIFIED |

| Platform | Archive SHA256 | Binary SHA256 |
|---|---|---|
| linux-amd64 | `9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161` | `0a347f06f0d1a17ef37edd779826ad79739217b65f80bf39dc6077f115ac175f` |
| linux-arm64 | `5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64` | `85ec863d21707ac309a4c7a64b3b7228eb34bb0405379db6b569d8d550032a4c` |

amd64 执行 identity：product=Splicore、version=v0.3.0-rc.4、准确 commit、
platform=linux/amd64、dirty=false；channel=`development` 是公开 release 本身的字段，未改写成 stable。

## nftables Port Range

| 项目 | 结果 |
|---|---|
| NoBrand Feature Exposed | **NO**：冻结 manifest 为 NOT EXPOSED |
| Core capability | 支持，但不构成 NoBrand runtime PASS |
| Environment | 专用 nftables host NOT AVAILABLE |
| Rule Ownership / Idempotency / Traffic / Cleanup | NOT EXECUTED；没有创建任何 range rule |
| Result | **N/A — NOT A CURRENT NOBRAND FEATURE** |

现有探针原始字段 `PENDING / NOT RUN` 仅记录当时未跑 Core range；本报告按实际 NoBrand
暴露范围将本产品项判为 N/A，不修改既有原始证据，不新增 UI、规则或特性。

## External CI

Existing CI：仅 `.github/workflows/ci.yml`；冻结版本使用容器矩阵、历史 Mieru/旧 runtime campaigns，
与当前 fresh-only 和本轮环境约束不匹配。已替换该测试 workflow，不改变 release pipeline。

| 项目 | 结果 |
|---|---|
| New/Modified Workflows | 修改现有 ci.yml，一个 ubuntu-24.04 regression job |
| Permissions | `contents: read`；无写权限、部署环境、真实 secrets |
| Checkout | 官方 action 固定 `11bd71901bbe5b1630ceea73d27597364c9af683`（v4.2.2），fetch-depth=0、persist-credentials=false |
| Tooling | actionlint v1.7.7；仅未来 ephemeral runner 安装测试包 |
| Pinned Splicore / SHA256 | PASS：精确 rc.4、公开双架构制品、执行前验证 |
| Syntax | YAML parser + actionlint PASS |
| Local Workflow Contract | PASS；拒绝额外 privilege/services、可变 actions/artifact、宿主服务和发布命令 |
| Local CI Entrypoint | PASS；完整冻结回归 + 资格基础设施测试 + 42 项回环探针 |
| Generated Files | 构建一致性 PASS；外部 workflow 最后运行 `git diff --exit-code` |
| External GitHub Actions Run | **PENDING UNTIL PUSH**；没有相同改动的外部 run ID/URL |

无容器、自管 runner、schedule、自动发布/tag/push，不为触发 Actions 发布 branch。
CI helper 的 PASS 只表示上述冻结回归范围，**不包含独立 DEFECT-1 复现，不解除总体 BLOCKED**。

## Regression

首次 fresh-download campaign 已完成：2026-10-21 16:30:10–16:33:53 UTC
（2026-10-22 00:30:10–00:33:53 +08:00），exit 0。
当时为 29 Bash / 49 Python（27+10+12）/ 42 runtime / 112 shell syntax 全通过。
随后补强日志完整性守卫，增加 1 个测试，以重新验证的公开缓存完成最终同入口回归：
2026-10-21 16:37:02–16:40:37 UTC（2026-10-22 00:37:02–00:40:37 +08:00），exit 0。

| Gate | 最终实际结果 |
|---|---|
| Bash | **29 PASS**；保留全部 28 个冻结入口，新增 1 个资格 wrapper |
| Python | **50 PASS** = 27 native + 10 fresh + 13 qualification |
| Public rc.4 Runtime | **42 PASS**；与冻结报告的完整 check 集逐项核对 |
| Shell Syntax | **112 PASS**；111 冻结文件 + 1 新 wrapper |
| ShellCheck | PASS；无跳过 |
| Build Consistency | PASS；两份 installer 与冻结 source/embedded runtime 一致 |
| Secret Scan | PASS；private key/credential/binary/bundle/infra literal 命中均为 0 |
| Workflow | actionlint v1.7.7 + YAML/权限合同 PASS |
| systemd / OpenRC static | `systemd-analyze verify` / `sh -n` 均 exit 0 |
| Optional real Sudoku Xray validation | SKIP；明确不属本 rc.4 runtime campaign |
| Independent reinstall reproduction | **4 FAIL**；独立命令 exit 1，DEFECT-1；未混入回归 PASS 计数 |

可复现命令（PATH 需包含固定 actionlint，设置 `PYTHONDONTWRITEBYTECODE=1`）：

```bash
python3 scripts/qualify-splicore.py ci \
  --evidence .lab/splicore-rc4-native-ci/campaign-final
python3 scripts/qualify-splicore.py ci \
  --artifacts .lab/splicore-rc4-native-ci/public-download/assets \
  --mihomo-gzip .lab/splicore-rc4-native-ci/public-download/assets/mihomo-linux-amd64-v1.19.30.gz \
  --evidence .lab/splicore-rc4-native-ci/campaign-reviewed
```

每次重跑更换新的 evidence 路径，既有目录会拒绝覆盖。
静态 gate 命令、实际执行时间、退出码、公开 artifact identity 和全部探针名见
[脱敏 JSON](SPLICORE_RC4_NATIVE_LINUX_CI_EVIDENCE.json)，不提交原始私有日志。

## Frozen Product Integrity

| Gate | 结果 |
|---|---|
| Frozen product files changed | **0 / 44** |
| Existing protected reports changed | **0 / 21** |
| Historical reports changed | **0 / 16**（21 的子集） |
| Freeze report changed | **NO** |
| Frozen Git baseline/sole parent | PASS |
| Frozen manifest trust | hashes 与不可变 `git cat-file` 原始 blob 比较；不只相信可编辑 fixture |
| Product diff | `src/`、`runtime/`、两份 installer、`scripts/build.sh` 相对基线为空 |
| All baseline files | 190 个中 188 字节不变；仅 ci.yml 和 scripts/test.sh 发生允许的基础设施修改 |

本轮允许的完整文件清单：

| 文件 | 变更 |
|---|---|
| `.github/workflows/ci.yml` | 修改；精确 rc.4 冻结回归 workflow |
| `scripts/test.sh` | 修改；仅增加资格测试 Bash wrapper |
| `scripts/qualify-splicore.py` | 新增；安全 inventory/static/assets/ci 入口 |
| `tests/fixtures/splicore-rc4-frozen.json` | 新增；44 产品/21 报告/16 历史 hash manifest |
| `tests/helpers/test_splicore_qualification.py` | 新增；资格工具安全和完整性测试 |
| `tests/test_splicore_qualification.sh` | 新增；Bash 验收 wrapper |
| `tests/helpers/qualify_splicore_reinstall.py` | 新增；独立缺陷复现，保留非零失败 |
| `docs/NATIVE-LINUX-QUALIFICATION.md` | 新增；专用主机规程、门控、范围和清理 |
| `docs/reports/SPLICORE_RC4_NATIVE_LINUX_CI_QUALIFICATION_REPORT.md` | 新增；本报告 |
| `docs/reports/SPLICORE_RC4_NATIVE_LINUX_CI_EVIDENCE.json` | 新增；白名单字段的脱敏汇总 |

## Safety

| 边界 | 结果 |
|---|---|
| Production/customer hosts touched | NO；未请求生产 SSH、未连接未知 host |
| Docker | UNTOUCHED；未查询/调用其 engine、服务或数据 |
| Redis | UNTOUCHED |
| TeleLedger | UNTOUCHED |
| Host systemd/OpenRC mutation | NONE；只有临时 unit 文件静态解析 |
| Firewall / nftables / network stack | UNCHANGED；只有 nft 版本查询 |
| Host package/account mutation | NONE；依赖准备无 apt/apk/账户操作；actionlint 仅私有工具目录 |
| Secrets | 合成测试材料；无真实 secrets、私钥、client bundles、binary/archive 进入候选提交树 |

临时实际 Core/client/cover 服务只绑定回环；正常结束停止进程并清除其临时 state。
raw private logs、公开下载 archives 和工具 binary 都在 ignored `.lab`，不加入公开报告。
专用 host 的任何未来 service/firewall/package 变更需明确 opt-in；本轮未执行。

## Defects Found

### DEFECT-1 — retained TLS blocks same-name fresh reinstall

**IMPLEMENTATION DEFECT FOUND**

Classification：`IMPLEMENTATION_DEFECT`。

Environment：Ubuntu 24.04 WSL2 amd64；冻结 NoBrand runtime CLI parser/dispatcher；
校验后的公开 rc.4 binary，SHA256 如上；服务调用用已有 local Supervisor 替代，
实际 Core launch、certificate generation、native config application 和 teardown 均真实执行。
先用原有 isolated Python fixture 复现，再用公开二进制重复四种组合。
没有据此声称完整 Bash 安装或真实 systemd 已运行。

Reproduction：在仓库根运行（先用 `assets` 准备已验证公开缓存）：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/qualify_splicore_reinstall.py \
  --artifacts .lab/splicore-rc4-native-ci/public-download/assets \
  --evidence .lab/splicore-rc4-native-ci/reinstall-review
```

脚本对 HY2/TUIC 各自在新临时目录运行以下 runtime CLI 语义：

1. `protocol --protocol <protocol> --operation install --selector fresh --artifacts <verified-public-assets>`，监听回环随机 UDP 端口，合成 SNI `probe.example`；首次 committed。
2. `protocol --protocol <protocol> --operation uninstall --selector fresh`，或另一独立 case 执行 `uninstall`；nodes=0，TLS 三个文件保留。
3. 与第 1 步完全相同的 install；失败发生在发布新 generation 或服务启动前。

每次 CLI 调用显式使用 `--adapter fixture --fixture-driver <private-temporary-driver>`；
通过 frozen `main()` parser/dispatcher 执行，stdout 中的合成 client secrets 丢弃，仅公开失败白名单。
HY2 普通 Bash 路由固定 selector=hy2，TUIC 使用 `--name`；审计确认这些路径最终调用同一
`Runtime.protocol()`，没有额外删除/复用 TLS 的逻辑。

Expected：协议卸载后或保留 state 的 runtime 卸载后，同名 fresh install 可完成；
没有旧残留阻塞重装，符合本次请求 §39。

Actual：四种组合均返回 `CONFIG_INVALID`：
`certificate directory already exists; explicit certificate reuse required`。
复现命令 exit **1**，JSON `classification=IMPLEMENTATION_DEFECT`。
失败后 generation、TLS 和服务启动计数不变；证据未显示本项有全局安全影响。

Affected Area：`runtime/splicore.py` 的 deterministic node ID、`certificate()` 拒绝既有目录、
protocol remove/uninstall 保留 TLS、`uninstall(purge=False)` 保留 state/TLS 的组合；
HY2/TUIC 普通安装界面没有显式复用该证书的参数。
`nobrand uninstall` 全局路径会 purge，**未证明它也受此缺陷影响**。

Evidence：2026-10-21 16:33:48–16:33:55 UTC（次日 00:33:48–00:33:55 +08:00）；
四个 case 的脱敏结果见 [machine evidence](SPLICORE_RC4_NATIVE_LINUX_CI_EVIDENCE.json)。
raw process 日志留私有 ignored evidence；临时证书/密钥不保留进公开树。

Fix Applied：**NO**。已停止对应重装资格，未删除业务代码中的 TLS、未新增兼容或绕过校验。
独立冻结回归/CI 准备继续；等待维护者另开 Fix Phase。

## Qualification Debt

1. DEFECT-1 的独立 Fix Phase 与修复后的重装资格；本轮禁止修复。
2. 专用 native amd64 systemd：真实 Bash fresh download/install、ownership、enable/start/restart、SIGTERM、自动 SIGKILL recovery、journal/resource/low-port、doctor/status、事务回滚、uninstall/reinstall/purge/cleanup。
3. reboot：NOT EXECUTED，待安全控制台和可重连专用 host。
4. 原生 REALITY 全探针、HY2 Salamander、全部暴露版本/transport 的实际 traffic、domain target/Core DNS failure 和真实 IPv6。
5. 真实 OpenRC 生命周期、boot persistence、traffic 和清理。
6. 真实 arm64 VM/hardware 上的 identity、服务、REALITY/HY2、restart 与清理。
7. External GitHub Actions：PENDING UNTIL PUSH；本轮不发布 branch。runner 包/网络及 user namespace 的实际可用性仍需该外部执行证明。
8. NoBrand HY2 range 未暴露，N/A；任何将来 Core-level range 资格和产品暴露需独立范围授权，不能以本轮替代。

## Git

| 项目 | 结果 |
|---|---|
| Stage | NONE |
| Commit | NONE；HEAD 仍 frozen baseline |
| Push | NONE |
| Tag | NONE |
| Release | NONE |
| Index | EMPTY |
| Branch | codex/qualification-splicore-rc4-linux-ci |
| Working Tree | 仅上列资格/CI/tests/docs 未暂存改动 |

结束前已执行 `git status --short`、`git diff --check`、`git diff --stat`、
`git diff --name-status`、相对 frozen baseline 的完整产品路径 diff，全部符合边界。
实际清单为 2 个 modified + 8 个 untracked（共 10 个上列文件），无 staged/deleted 文件。
`git diff --stat` 只显示两个 tracked 修改；八个新增文件由独立完整 allowlist 核对。
最终 static gate 于 2026-10-21 16:41:52–16:41:54 UTC 再次 exit 0；
候选树脱敏、全部新文件空白、文档链接、HEAD/main/sole parent、44/21/16 hash gate 全部 PASS。

本报告完成后停止，等待 review；不 Freeze、不提交、不推送、不开始 Fix Phase。

## Final Result

**NATIVE LINUX & CI QUALIFICATION BLOCKED — IMPLEMENTATION DEFECT FOUND**

本地 CI 适配与独立回归通过，不消除 DEFECT-1。
专用环境缺失另记 PENDING；没有将环境缺失归类成实现失败，也没有声称 native certified。
