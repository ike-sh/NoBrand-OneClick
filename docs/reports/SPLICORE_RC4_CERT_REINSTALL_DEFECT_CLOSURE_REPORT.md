# NoBrand-OneClick Certificate Reinstall Defect Closure Report

日期：2026-10-22（Asia/Shanghai）。阶段：HY2/TUIC certificate lifecycle 定向修复；不含发布或原生主机资格。

## Baseline

| 项目 | 值 |
|---|---|
| Frozen Commit | `b5440ec41aeed2dd266b3a7008f75a26de63add2` |
| Sole Parent | `f98cf70e7159c07826101676a4a08394f0a203f9` |
| Qualification Result | **BLOCKED — IMPLEMENTATION DEFECT FOUND**，保留为历史事实 |
| Fix Branch | `codex/fix-cert-reinstall-lifecycle` |
| HEAD / main | 仍为 Frozen Commit；修复仅在其后的未提交工作树中 |
| Splicore | `v0.3.0-rc.4`，public commit `2634ea50d19623591c5db63329a288862726db74` |

执行环境：Ubuntu 24.04 WSL2、x86_64、kernel `6.6.87.2-microsoft-standard-WSL2`。
未发现专用 native 主机，本轮继续只执行临时回环和隔离测试。

开始时完成 status、branch、HEAD/main、graph log、stat、name-status、diff-check 和 sole-parent 核对。
原资格分支的十个未提交文件全部保留，保存起始文件 hash 后创建同 HEAD 的 fix branch，
未 reset/clean/restore/stash/rebase，未改变历史。

历史证据不重写：

- [原资格报告](SPLICORE_RC4_NATIVE_LINUX_CI_QUALIFICATION_REPORT.md) 仍为 BLOCKED。
- [原资格 JSON](SPLICORE_RC4_NATIVE_LINUX_CI_EVIDENCE.json)、原 `qualify_splicore_reinstall.py`、原资格规程保持字节不变。
- 冻结时 21 份报告（含原 16 份历史报告及 freeze report）字节不变。
- 本阶段新增 [闭环脱敏证据](SPLICORE_RC4_CERT_REINSTALL_DEFECT_CLOSURE_EVIDENCE.json)，不覆盖原失败证据。

## Defect

Protocols：HY2 / TUIC。
Trigger：`install -> uninstall -> same-name reinstall`。
Original failing cases：**4**；均是 NoBrand 生成的 private CA + non-CA leaf 模式，实例名 `fresh`。
四例按卸载路径区分，不是证书模式 A/B：

| ID | 协议 | 卸载路径 | 证书保留路径（相对配置根） |
|---|---|---|---|
| CASE-1 | HY2 | `protocol --operation uninstall` | `splicore/tls/<deterministic-node-id>/` |
| CASE-2 | HY2 | `runtime uninstall`，保留 state | 同上 |
| CASE-3 | TUIC | `protocol --operation uninstall` | 同上 |
| CASE-4 | TUIC | `runtime uninstall`，保留 state | 同上 |

修改 functional code **之前**重新执行原 helper，2026-10-21 16:45:34–16:45:43 UTC
（2026-10-22 00:45:34–00:45:43 +08:00），exit **1**，四例再次失败：

- 首次安装 committed；协议卸载 committed，runtime 卸载 uninstalled；节点数归零。
- 每例保留 `certificate.pem`、`private.key`、`ca.pem` 三个文件。
- 同名重装 `CONFIG_INVALID`：`certificate directory already exists; explicit certificate reuse required`。
- 使用已验证的公开 rc.4 amd64 binary；fixture 只替代宿主服务调用，Core/证书/CLI dispatcher 真实运行。

## Root Cause

这是 **卸载保留合同与安装状态判断不一致**，发生在共享 `Runtime.certificate()`：

1. 节点 ID 由 protocol + logical label 确定，同名重装自然选择同一 TLS 目录。
2. protocol remove 删除 desired node；`uninstall(purge=False)` 删除 current pointer 并停止/移除服务。
   两者都故意保留 persistent TLS，供状态保留和 rollback 使用；`purge=True` 才删除。
3. 安装只允许 TLS 目录不存在，既不验证有效保留证书，也不依据 native canonical state 证明归属。
4. 原生成目录没有独立 TLS ownership marker；即使有合法 native generation 记录，安装也没有采用路径。
5. 原安装失败清理默认认为本次 TLS 是新建材料；引入复用时必须同时区分 created 和 retained，
   否则失败重装可能误删已保留的证书。

因此修复不把 uninstall 改成 purge，也不在安装开始删除目录或无意义轮换身份。

## Intended Lifecycle

### Certificate Lifecycle Contract

| 状态/操作 | 正式处理 |
|---|---|
| Truly clean install | NoBrand 生成私有 CA 和 non-CA leaf；丢弃 CA signing key；持久化 chain、server key、CA cert 和独立 ownership metadata |
| Active same-name instance | 保持原拒绝，要求显式 reconfigure；不覆盖节点、证书或凭据 |
| Protocol remove | 移除该 node 的 desired state，保留 TLS；共享 daemon 可能继续运行其它节点 |
| Runtime uninstall | 停止/disable/remove owned unit，移除 current pointer，保留 generations/TLS；重复执行安全 |
| Valid managed reinstall | 证明目录属于同一逻辑实例并验证有效性后复用原文件，路径、leaf/CA identity、fingerprint、权限不变 |
| Pre-marker native rc.4 state | 只接受 owned generation 对同一 deterministic instance、完整 TLS paths/SNI/CA 内容的精确 canonical 引用；验证成功后增加 marker |
| No marker and no exact native proof | FAIL CLOSED；不按路径猜 ownership，不覆盖或删除第三方数据 |
| Incomplete, corrupt, expired or wrong-identity state | FAIL CLOSED；给出检查/恢复或显式 purge owned state 的提示；不启动、不自动重签 |
| Purge | 删除前证明每个 TLS 子目录的 ownership；正常 owned TLS 删除后，下次 clean install 生成新身份；遇到外来或危险路径则在破坏性步骤前拒绝 |

普通 HY2/TUIC fresh CLI 当前使用自动生成证书，没有新增 import/ACME 模式。
显式 canonical `runtime apply` 可引用用户自备 cert/key/CA；本修复不接管 owned TLS 根之外的用户材料，
也不删除、重新签发或覆盖其文件。外部路径卸载/purge 不变测试通过。

复用前验证：真实目录、普通文件、无 symlink/hardlink、owner/group 与运行管理者一致、
目录 0700、文件 0600；marker 的 owner/node ID/SNI/三个文件 SHA256 完全匹配。
然后执行真实 OpenSSL chain/CA、有效期、SAN/name、server purpose、non-CA leaf、
DigitalSignature、serverAuth EKU、cert/key public-key matching 检查。
不因“文件存在”而视为有效，也不通过放宽权限完成重装。

TLS 身份保存不承诺旧完整 client profile 永久有效：节点 reinstall 仍按原 fresh builder 生成新的
协议 UUID/password/Salamander secret；本阶段未改变该认证凭据合同。CA trust 和 leaf pin 保持一致。

## Fix

### Shared lifecycle

Functional source 仅修改 `runtime/splicore.py` 的六个直接相关方法：

- `certificate_material()`：读取私有 owned material，检查类型、权限、uid/gid 和链接安全。
- `certificate_provenance()`：查找 pre-marker native generation 的同实例精确证书引用。
- `certificate_owner()`：校验独立 owner marker，或在无 marker 时要求 canonical proof。
- `certificate()`：保留原 fresh 签发逻辑，为新材料写 marker；对合法 retained material 验证后复用。
- `protocol()`：HY2/TUIC 共用 TLS 准备；失败回滚只清理由本次创建的 TLS，保留 reused TLS。
- `uninstall()`：保持 uninstall/purge 区别；purge 在停止/删除前检查 TLS ownership。

`owner.json` 记录 `nobrand-splicore-tls-v1`、node ID、server_name 和三个文件 digest，0600。
独立 marker 不依赖旧 generation 永久保留；旧 canonical generation 被正常 prune 后仍可安全重装。
只读复用不重写有效证书、key、CA 或 marker。新 metadata 不进入客户端配置或日志。

Protocol-specific changes：**无两份独立修复**；HY2/TUIC 共享上述路径，保留原协议配置差异。
两份 installer 仅通过 `bash scripts/build.sh` 重新生成，未手工编辑；其它 product source 未改。

资格 guard 调整仅为适应已授权的 Fix Phase：

- 严格 `frozen_integrity()` 仍会拒绝产品差异；原 baseline manifest 未改。
- 新 `review_integrity()` 明确报告三份 authorized changed product files，保护其它 41 份产品文件。
- AST 比较限制 functional diff 在上述六个方法内，build-check 检验两份生成物一致性。
- 新 scope fixture 保护原资格报告、JSON、规程和原 reproducer 的起始 hash。
- 新 cert-lifecycle wrapper 纳入当前全量测试，完整性守卫仍要求原 28 Bash、37 Python、42 runtime 全在场。
- CI workflow 沿用上一阶段版本，未重设计或触发外部执行。

## HY2

| Gate | 结果 |
|---|---|
| Fresh | PASS；新 CA/non-CA leaf、Salamander profile |
| Protocol/runtime uninstall | PASS；证书保留；runtime uninstall twice 安全 |
| Reinstall | PASS；原 CASE-1、CASE-2 |
| Second reinstall | PASS；两条卸载路径各完成两轮 |
| Certificate identity | PASS；leaf fingerprint 和 CA digest 恒定，文件内容/权限/owner/group 不变 |
| Runtime validation | PASS；fresh + 两轮 reinstall 的真实 rc.4 native validation |
| Runtime smoke | PASS；fresh + 两轮 reinstall 的真实 TCP/UDP traffic |

## TUIC

| Gate | 结果 |
|---|---|
| Fresh | PASS；v5、新 TLS trust |
| Protocol/runtime uninstall | PASS；证书保留；runtime uninstall twice 安全 |
| Reinstall | PASS；原 CASE-3、CASE-4 |
| Second reinstall | PASS；两条卸载路径各完成两轮 |
| Certificate identity | PASS；leaf fingerprint 和 CA digest 恒定，文件内容/权限/owner/group 不变 |
| Runtime validation | PASS；fresh + 两轮 reinstall 的真实 rc.4 native validation |
| Runtime smoke | PASS；fresh + 两轮 reinstall 的真实 TCP/UDP traffic |

公开二进制验证时间：2026-10-21 16:52:07–16:52:43 UTC（次日 00:52:07–00:52:43 +08:00），exit **0**。
四组 extended smoke 共 **12 次 native config validation + 12 次 TCP/UDP traffic**，不是 12 次宿主服务资格。
每组 purge 完成，temporary state 和进程清理；使用 private synthetic material，raw logs 不提交。

## Safety

| Gate | 结果/证据 |
|---|---|
| Third-party certificate | UNTOUCHED；目录冲突不能采用，purge 在删除前拒绝；sentinel 保持 |
| User-supplied external cert/key | UNTOUCHED；canonical reference 的 uninstall/purge 不改外部文件 |
| Active-instance collision | SAFE；重复 install 拒绝，state/TLS/service events 不变 |
| Partial managed state | SAFE / FAIL CLOSED；缺 cert/key/CA、无归属证据、截断 material/metadata 都拒绝 |
| Bad cert/key or CA | FAIL CLOSED；即便测试更新 owned digest，也由真实密码学验证拒绝 mismatch/wrong CA |
| Expiry | FAIL CLOSED；真实 OpenSSL `verify -attime` 在超出 CA 生命周期的测试时间拒绝；未改宿主时钟 |
| SAN/KU/EKU/BasicConstraints | FAIL CLOSED；synthetic 签发的缺失/错误扩展用例拒绝 |
| Symlink/path safety | PASS；目录/四文件链接、hardlink、空 ID/traversal、symlink parent、宽松权限均拒绝 |
| Failed reinstall rollback | PASS；复用 TLS 不删除，retry 可成功 |
| Purge then fresh | PASS；owned material 删除，clean install 的 CA identity 改变 |
| Private key leak | NONE；secret scan 通过，报告/JSON 不包含 cert/key 内容或 client credentials |

生产、客户主机、未知 SSH、Docker/Redis/TeleLedger 均未查询或操作。
没有安装或修改宿主 systemd/OpenRC、firewall/nftables、网络栈、账户或包。
此次运行只使用隔离 fixture、临时回环 Core/client/echo 和已验证公开缓存。

## Original Qualification Cases

| Case | 修复前 | 修复后（原 `case()` 原字节函数） |
|---|---|---|
| CASE-1 HY2 protocol uninstall | FAIL / CONFIG_INVALID | **PASS** |
| CASE-2 HY2 runtime uninstall | FAIL / CONFIG_INVALID | **PASS** |
| CASE-3 TUIC protocol uninstall | FAIL / CONFIG_INVALID | **PASS** |
| CASE-4 TUIC runtime uninstall | FAIL / CONFIG_INVALID | **PASS** |

独立复现与闭环命令（均使用新的私有 evidence 目录）：

```bash
# 仅在修复前运行的原命令；原脚本保留严格冻结 guard，修复工作树上会拒绝产品差异。
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/qualify_splicore_reinstall.py \
  --artifacts .lab/splicore-rc4-native-ci/public-download/assets \
  --evidence .lab/cert-reinstall-fix/before-public

# 修复后：先约束 Fix Phase diff，然后调用原 case()，另做两轮重装验证和流量。
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/qualify_splicore_cert_fix.py \
  --artifacts .lab/splicore-rc4-native-ci/public-download/assets \
  --mihomo-gzip .lab/splicore-rc4-native-ci/public-download/assets/mihomo-linux-amd64-v1.19.30.gz \
  --evidence .lab/cert-reinstall-fix/after-public
```

这些结果标签为 **Linux amd64 WSL2/local loopback**，不宣称完整 Bash 安装或真实 init 资格。

## Regression

全量回归：2026-10-21 16:52:07–16:56:09 UTC（2026-10-22 00:52:07–00:56:09 +08:00），exit **0**。

| Gate | 实际结果 |
|---|---|
| Bash acceptance | **30 PASS**：原 29 + cert lifecycle wrapper |
| Python | **72 PASS**：27 runtime + 10 fresh + 22 cert lifecycle + 13 qualification |
| Public rc.4 runtime | **42 PASS**；保留全部原 probe，含 REALITY Local Tunnel Guard 安全矩阵 |
| Shell syntax | **113 PASS**：原 112 + 新 wrapper |
| ShellCheck | PASS |
| Build consistency | PASS；两份 installer 与 source/embedded runtime 一致 |
| Secret/redaction scan | PASS；private key、credential、runtime binary、bundle、真实基础设施 literal 命中均为 0 |
| Legacy refusal | PASS；旧安装拒绝发生在变更前，字节不变 |
| Exact Core artifact | PASS；双架构公开缓存复核，amd64 version identity 执行；没有升级 Core |
| Fix scope guard | PASS；三份 authorized product changes，0 unapproved changes |
| Original four cases | **4 PASS**，另一个真实公开二进制 campaign |
| Extended public smoke | **12 native validations + 12 TCP/UDP traffic PASS**；四组各两轮重装 |
| Optional real Sudoku Xray validation | SKIP；原来就不属于 rc.4 runtime campaign，未计为 PASS |

新增专用证书测试覆盖 clean install、两轮 reinstall、active collision、uninstall twice、
purge/fresh、pre-marker adoption、generation pruning、partial/mismatch/foreign/link/permission、
expiry/extensions、failed-reinstall retry 和外部用户证书。

完整回归命令（PATH 包含私有 actionlint v1.7.7）：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/qualify-splicore.py ci \
  --artifacts .lab/splicore-rc4-native-ci/public-download/assets \
  --mihomo-gzip .lab/splicore-rc4-native-ci/public-download/assets/mihomo-linux-amd64-v1.19.30.gz \
  --evidence .lab/cert-reinstall-fix/regression
```

使用的是上一阶段官方 HTTPS 获取的公开缓存；本阶段重新校验 archive/SHA256SUMS/ELF/binary
digest/amd64 identity/reference-client digest 后才执行。每次复跑更换新的 evidence 目录。

## Frozen Architecture

| 项目 | 结果 |
|---|---|
| Splicore | `v0.3.0-rc.4` exact pin、SHA256、binary identity 不变 |
| Architecture | UNCHANGED；NoBrand orchestrator + one ordinary Splicore daemon |
| Legacy migration policy | UNCHANGED；旧多 Core拒绝、无原地迁移 |
| REALITY | UNCHANGED；native Vision/Local Tunnel Guard 代码和合同未改 |
| Other protocols / menus / init adapters | UNCHANGED |
| Functional product paths changed | `runtime/splicore.py`、`install-nobrand.sh`、`dist/install-nobrand.sh` |
| Original freeze commit / historical reports | UNCHANGED；未 rewrite，也未把原 BLOCKED 报告改 PASS |

## Qualification Debt

| 项目 | 状态 |
|---|---|
| Native Linux amd64 systemd | **PENDING ENVIRONMENT** |
| OpenRC | **PENDING ENVIRONMENT**；已有产品支持，未执行 |
| arm64 | **PENDING ENVIRONMENT**；没有真实运行环境 |
| nftables HY2 range | **N/A — NoBrand NOT EXPOSED** |
| External Actions | **PENDING UNTIL PUSH** |

本修复解除重装缺陷，不把上述项目改成 PASS，不继续 native qualification。

## Git

Stage：NONE。Commit：NONE。Push：NONE。Tag：NONE。Release：NONE。Index：EMPTY。
Branch：`codex/fix-cert-reinstall-lifecycle`；HEAD/main 均仍指向原 frozen commit。
工作树保留上一阶段 qualification infra，加本次限定 certificate lifecycle fix、tests 和新闭环证据。

本阶段相对开始时新增或调整的完整清单：

| 文件 | 原因 |
|---|---|
| `runtime/splicore.py` | 共享 TLS 归属、验证/复用、created/retained 区分、purge 归属检查 |
| `install-nobrand.sh` | 生成物；嵌入同一 runtime 修复 |
| `dist/install-nobrand.sh` | 同上，与根 installer 一致 |
| `scripts/test.sh` | 新增 certificate lifecycle 验收 wrapper |
| `scripts/qualify-splicore.py` | 明确约束授权 fix 差异，适配新增测试数量，保留 strict frozen guard |
| `tests/helpers/test_splicore_qualification.py` | 调整 phase integrity 和完整计数断言 |
| `tests/fixtures/splicore-rc4-cert-fix.json` | 新增；允许范围及原资格证据 hash |
| `tests/helpers/test_splicore_cert_lifecycle.py` | 新增；22 个定向回归测试 |
| `tests/test_splicore_cert_lifecycle.sh` | 新增；测试 wrapper |
| `tests/helpers/qualify_splicore_cert_fix.py` | 新增；原四例+公开 rc.4 两轮重装/流量检查 |
| `docs/reports/SPLICORE_RC4_CERT_REINSTALL_DEFECT_CLOSURE_REPORT.md` | 新增；本报告 |
| `docs/reports/SPLICORE_RC4_CERT_REINSTALL_DEFECT_CLOSURE_EVIDENCE.json` | 新增；脱敏前后对照和验证证据 |

完整候选树含上一阶段保留文件共 19 项：5 个 tracked modified、14 个 untracked；
无 staged/deleted 文件。其余七个上一阶段候选文件保持起始字节。
原 frozen commit、sole parent、main 均未改写；产品其它 41 个文件不变；
原 23 份已有报告（冻结时 21 + 资格阶段 2）以及资格规程和原复现脚本均通过起始 hash 比对。

最终 static gate 于 2026-10-21 16:58:36–16:58:39 UTC 再次 exit 0。
候选文件完整 allowlist、hash/AST scope、文档链接、空白、build-check 和脱敏扫描均 PASS；
`git status --short`、`git diff --stat`、`git diff --name-status`、`git diff --check`
及 index/HEAD/main/sole-parent 核对符合上述范围。未暂存、提交、推送、打 tag 或发布。

## Final Result

**CERTIFICATE REINSTALL DEFECT CLOSED**

**READY FOR REVIEW**

仅指本报告定义的缺陷闭环；未 Freeze、未提交、未发布。

## Remaining Blockers

**None for this scoped defect.** 环境资格和外部 Actions 债务如上，保持 PENDING/N/A。
报告完成后停止，等待维护者 review，不继续 native qualification。
