# Splicore Final Migration Blocker Ownership Audit

审计日期：2026-10-18。结论：**SPLICORE MIGRATION BLOCKERS REMAIN；Freeze = NO。**

| Blocker | Owner | 判断 |
| --- | --- | --- |
| REALITY defender / secure routing | **SPLICORE** | 公开 rc.3 缺少服务端策略执行及受 SNI 限制的 fallback；已有 client/network routing 无法组合补齐 |
| HY2 legacy certificate | **MIXED** | Splicore 的 PKI-only 服务端证书契约存在迁移兼容缺口；旧默认客户端存在身份验证安全债；NoBrand 需要显式、可回滚的兼容/换证选择 |

NoBrand 当前拒绝迁移的保护是正确的。本轮没有发现通过改字段映射即可消除两个 blocker 的依据，没有实施修复或换证。

## Evidence and Scope

- 正式运行对象仅为公开 **v0.3.0-rc.3 / `72166d2fcda95b943cbae584bdd59876df7d0ed8`**；不是本地 Splicore HEAD。
- Linux amd64 正式可执行文件 SHA256：`737d5b2b22daafd36940c12192185922b53711e0dc24946327be4119304f1a61`。
- 旧运行时为正式 Xray **26.3.27**，SHA256：`8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`；配套 ZIP 中原始 geoip/geosite 数据。
- 客户端为正式 Mihomo **1.19.30**；压缩包 SHA256：`cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84`。
- 新增 [Python 审计夹具](../../tests/helpers/splicore_ownership_audit.py) 和 [Go TLS/backend 夹具](../../tests/helpers/splicore_ownership_tls.go)。后者链接**公开 rc.3 源码**中的原始 HY2 backend 和 Snapshot 函数，构造独立测试程序；没有构建替代 Splicore daemon，没有更改任何校验器。
- [脱敏运行证据](SPLICORE_FINAL_BLOCKER_OWNERSHIP_PROBE.json) 记录实际结果、证书公开元数据、正式二进制身份及内层校验错误；不含证书 PEM、私钥、真实用户配置。
- 所有连接发生在 `unshare --net` 创建的独立网络命名空间。仅启用该命名空间的 lo，并将 `1.1.1.254/32` 放在其 lo 上充当不命中 geoip:private 的测试目的地；没有外部路由，未接触该公网地址的真实机器，未修改宿主网络、hosts、nftables 或 iptables。
- REALITY camouflage 使用合成 `localhost`、自有 TLS 1.3 目标和随机非 443 端口，保留公共入口→defender→固定目标的拓扑。旧生成配置仅作 hostname/端口夹具代换，并加入 Xray **进程内** `dns.hosts` 与 freedom `UseIPv4`，避免回环解析歧义。它绕过生产的公网目标准入，仅用于行为对照；没有把本地目标认定为合格生产 camouflage。
- 同一合成客户端配置用于两种服务端；仅 SOCKS 入口端口随测试变动。目标服务记录收到的第一类字节及 SNI，避免把“客户端没收到响应”误认为“没有向目标转发”。
- 测试覆盖本地协议语义，不替代真实生产客户端、原生 init、arm64 或 nft 资格验证。HY2 UDP 完整性仅覆盖 64/512 字节。

## LEGACY_BEHAVIOR_CONTRACT

### REALITY call/config chain

`src/05-constants.sh` → `src/59-vless-reality.sh` 的目标选择/验证 → `reality_generate_server_config()` → `reality_generate_state()` / 三类客户端 exporter → `src/25-platform-vless-reality.sh` → 私有正式 Xray `run -c <instance>/config.json`，并设置配套 `XRAY_LOCATION_ASSET`。

`reality_config_matches_state()` 同时检查状态、配置和私钥派生公钥的一致性。一个 Xray 进程拥有该实例的公共 TCP 入口和回环 defender；每个实例有独立 service/config/state。

### HY2 call/config chain

`src/57-hysteria2.sh:generate_hysteria2_cert()` → `hysteria2_generate_config()` → Xray `hysteria` v2 inbound → TLS 证书文件直接加载；H3/QUIC + Salamander → freedom outbound。这里没有另行生成 CA 和签发 leaf 的调用链。

`hysteria2_generate_state()` → `hysteria2_build_share_link()` / `hysteria2_export_mihomo()` / `hysteria2_export_singbox()`。证书信任参数来自这些真实 exporter，而不是根据协议名称推断。

## REALITY Defender

### Legacy purpose

defender 是**未认证连接的 SNI 过滤和固定目标转发层**。它允许预期 SNI 的普通 TLS 访问 camouflage；拒绝不匹配 SNI、明文 HTTP 和无可识别 TLS SNI 的探测。它不是替换 UUID/short ID 验证的第二套认证。

同一个 Xray routing 表还为认证后的代理流量提供私网、危险 TCP 端口和 BitTorrent 拒绝规则。这些规则不应被缩减为“defender 的几个内部字段”。

### Exact generated fields and defaults

| 位置 | 配置/默认值 | 消费者与作用 |
| --- | --- | --- |
| camouflage | mode=`auto`，port=`443`；也接受经过验证的 custom host/port | NoBrand 选择目标；要求公网解析、TLS 1.3、主机名/证书验证成功 |
| defender port | 默认分配范围 `20000–29999`，避开冲突 | 本实例 Xray 回环 TCP listener |
| public inbound | VLESS；UUID；decryption=`none`；flow=`xtls-rprx-vision` | Xray VLESS/Vision |
| stream | raw TCP，security=`reality` | Xray REALITY |
| REALITY target | `127.0.0.1:<defender_port>` | REALITY 握手及失败/fallback 的下一跳；不是认证后代理目的地 |
| REALITY parameters | show=false，xver=0，minClientVer=`0.0.0`，serverNames=[选定 SNI]，privateKey，shortIds=[原 short ID] | REALITY transport；最低版本默认不构成额外限制 |
| public sniffing | enabled=true，destOverride=[http,tls,quic] | Xray 的协议识别与目的域名处理 |
| defender | tag=`nobrand-vless-reality-<ID>-defender`，listen=`127.0.0.1`，protocol=`dokodemo-door` | 同进程内的独立入口 |
| defender destination | address=`nobrand.invalid`，port=选定 camouflage port，network=tcp | 不可信连接的初始逻辑目的地；禁止把探测提供的 SNI 当任意转发目的地 |
| defender sniffing | enabled=true，routeOnly=true，destOverride=[tls] | SNI 只参与路由；最终固定目标由 outbound redirect 决定 |
| outbounds | PUBLIC_DIRECT=freedom；DIRECT=freedom redirect=`<server_name>:<target_port>`；BLOCK=blackhole | 分离认证后目的地与 camouflage 固定目标 |
| client defaults | fingerprint=`chrome`，spiderX=`/`，原 UUID/public key/short ID/SNI | 客户端可见参数；defender port/tag 不导出给客户端 |

状态还保存 `defender_enabled=true`、protocol/listen/port/tag/dispatch_host、`defender_target_mode=fixed-outbound-redirect`、camouflage_mode、target_host/target_port。不能只删除这些字段便认定语义已迁移。

### Ordered legacy routing

1. `geoip:private` → BLOCK。
2. TCP `25,135,137,138,139,445,465,587` → BLOCK。
3. 协议识别为 BitTorrent → BLOCK。
4. defender inbound + `full:<server_name>` → DIRECT 的固定 redirect。
5. 其余 defender inbound → BLOCK。
6. public inbound → PUBLIC_DIRECT，按认证用户请求的目的地转发。

这些顺序也是契约的一部分。`geoip:private` 的实际覆盖取决于配套数据库及 Xray routing/sniffing 的地址阶段；本报告没有把它夸大为覆盖所有 DNS 重绑定或域名解析后的私网地址的完整 SSRF 防护。

### Legacy observable behavior / Probe matrix

下表为真实 Xray+生成拓扑与正式 rc.3 的对照，正向对照均 PASS。BLOCKED 表示没有完成应用流量或指定 TLS 握手，不意味着所有失败都发生在同一协议层。

| Probe | Legacy Xray | Public rc.3 | 解释 |
| --- | --- | --- | --- |
| A. 正确 REALITY/Vision → 自有正常目的地 | PASS | PASS | 同一原 UUID、密钥、short ID、SNI |
| B. 错 UUID | BLOCKED | BLOCKED | REALITY 参数正确，VLESS 用户认证失败；不把该连接当已授权代理 |
| C. 错 short ID | BLOCKED | BLOCKED | 无代理流量；REALITY 失败可进入 camouflage 路径，客户端拒绝其普通证书 |
| D. 错客户端 server-name/SNI | BLOCKED | BLOCKED | 两者都无代理流量；rc.3 的普通 TLS fallback 仍会到目标，见下一行 |
| E1. 普通 TLS、预期 SNI | TLS handshake | TLS handshake | camouflage 的允许路径确实存在 |
| E2. 普通 TLS、错误 SNI | BLOCKED，目标未收到 TLS | **TLS handshake，目标收到错误 SNI** | **安全行为差异**；REALITY 认证 SNI 校验不等于 fallback SNI 过滤 |
| F. 明文 HTTP | BLOCKED，目标未收到 HTTP | 客户端无响应，**目标收到 HTTP 字节** | **转发差异**；不能因两端无响应便判等价 |
| G. 本夹具随机 TCP bytes | 无响应，目标未记录数据 | 无响应，目标未记录数据 | 仅证明这个输入，不能推导全部畸形 TCP 等价 |
| H. 预期 SNI 的普通 TLS + HTTP request | HTTP_RESPONSE | HTTP_RESPONSE | 正常 camouflage/fallback 可用 |
| 正确客户端 → `127.0.0.1` echo | BLOCKED | **PASS** | 私网路由反例 |
| 正确客户端 → 隔离正常地址 TCP/25 echo | BLOCKED | **PASS** | 危险端口规则反例，未被私网规则掩盖 |
| 正确客户端 → 正常端口，BitTorrent handshake bytes | BLOCKED | **PASS** | 识别/阻断能力反例 |
| 直接连接回环 defender、预期/错误 SNI | 通过 / 阻断 | 无独立 defender | 外部语义可以用内置实现提供，不要求复制旧 listener |

### Splicore equivalent and composition audit

正式源码调用链：

`internal/splicore/engine/native/vless.go:Compile()` → `underlay.DialerFrom(ServerTarget)` → `protocol/vless/backend.RealityServer()` → `github.com/metacubex/utls v1.8.7:RealityServer()`。

握手失败时，uTLS 会把客户端字节镜像/转发到配置的固定 target。`ServerNames` 参与 REALITY **认证**，不承担旧 defender 的“所有 fallback 必须匹配 SNI”职责。backend 还对目标连接施加 5 秒边界；没有据此认定完整 fallback 生命周期与旧版等价。

认证后：`wire.ReadRequest()` → flow/UUID/admission 检查 → `h.protected.DialContext()` 直接连接用户目的地，TCP/UDP 路径没有进入 clientruntime 的 `selectRoute()`。underlay 的职责是 socket/TUN 防回环保护，不执行业务的 reject/direct/proxy 策略。

**实际组合实验**：通过公开 `network plan/apply` 成功设置 `route.final={kind:reject}`；公开 `route explain` 对回环目的地返回 reject，随后相同服务端 REALITY 客户端仍成功完成回环 echo。说明网络配置已生效于其所属路由域，却不覆盖 native VLESS server egress。

检查了 networkpolicy 的 domain/CIDR/port/network/local-inbound/rule-set matcher、clientruntime 的 SOCKS/HTTP/Mixed/TUN 路径、policy group fallback 和 native registry。它们无法充当未认证裸 TLS 的 SNI-gated 固定转发器，也没有将 server VLESS 请求绑定到这些 matcher 的公开入口。policy group 的健康探测 fallback 与 REALITY 握手 fallback 是两种行为。把 REALITY target 指向 SOCKS/HTTP 入口也不会产生其所需代理握手。

| 旧行为 | 分类 | 结论 |
| --- | --- | --- |
| 原凭据、SNI、short ID、TCP、Vision 及正确客户端流量 | **EXACTLY SUPPORTED** | 本矩阵范围内通过；不是整个迁移验收通过 |
| 错 UUID/short ID/SNI 不能获得代理服务 | **EXACTLY SUPPORTED** | 已实际测试；不能延伸为 fallback 相同 |
| 显式目标 host/port、允许 SNI 的即时 camouflage TLS/HTTP | **EXACTLY SUPPORTED** | 测试覆盖非 443 端口；未宣称超时/长连接完全相同 |
| tags、dokodemo-door 名称、`nobrand.invalid`、内部端口、两个 freedom outbound 的具体实现 | **LEGACY CORE IMPLEMENTATION DETAIL** | 名称/进程内部结构可变；过滤和目的地边界必须保留 |
| minClientVer=`0.0.0`、show=false、xver=0 | **LEGACY CORE IMPLEMENTATION DETAIL** | 默认无最低版本限制/无 Proxy Protocol；不据此索取同名新字段 |
| fallback 仅允许精确 SNI，其余阻断 | **NO EQUIVALENT CAPABILITY** | 错 SNI 普通 TLS 反例；不能由已有路由组合覆盖 |
| private IP / 危险端口 / BitTorrent 拒绝 | **NO EQUIVALENT CAPABILITY** | 三个实际反例 + final reject 组合反例 |
| Xray sniffing 的域名提取/目的地覆盖 | **NO EQUIVALENT CAPABILITY** | server handler 无对应业务处理；BitTorrent 已有行为证据，其他细节按源码缺口记录，未逐个协议实测 |
| 任意外部 iptables/socat/sidecar 补丁 | **UNSAFE / OBSOLETE（作为迁移方案）** | 无法形成所要求的单核心、同一事务契约；本轮未使用 |
| 已有 network rules/CIDR/ports 组合 | **CAN BE COMPOSED FROM EXISTING SPLICORE FEATURES，仅限 client local ingress** | 该组合能力确实存在，但不能覆盖本 blocker 的 server egress；不计为解决 |

没有足够证据将 defender 的安全语义标记为 **NO LONGER REQUIRED**。可以不保留旧内部端口/字段，不能丢弃其可观察的策略。

### Client impact

原 REALITY 客户端凭据与 Vision 在 rc.3 可以互通，迁移丢失的安全规则不要求修改客户端就能表现出来。允许迁移会扩大服务端可访问目的地和 camouflage 可转发输入，因此当前 NoBrand fail-closed gate 必须保留。

### Owner

**SPLICORE — FEATURE GAP。** NoBrand 不能通过字段重命名、global route 配置或删掉 defender 状态解决。

### Required Fix / ready-to-send Splicore issue

**Title: Add native REALITY fallback admission and server egress policy parity for NoBrand migration.**

Scope / acceptance contract:

1. 为 native server inbound 提供受版本控制的策略契约，绑定到**实际** VLESS TCP/UDP 请求的授权与 dial 路径；按顺序表达 private CIDR、TCP 端口集合、协议识别拒绝及最终 direct。明确 DNS/sniffing/目的地覆盖阶段，避免声明实现不存在的私网解析保护。
2. REALITY fallback 的 ClientHello/SNI 准入位于任何不可信载荷转发到 camouflage 目标**之前**：允许精确配置的 SNI；错误/缺失 SNI、明文 HTTP、随机/畸形 TLS 拒绝；最终 target 固定，不由探测请求选择。应保留正常 REALITY、普通允许 SNI TLS 和允许 fallback HTTP。
3. 可复用现有核心内部 matcher；必须接通 server runtime，而不是仅让 `route explain` 看起来正确。无需暴露 Xray 的 tag/dokodemo 字段或新增外部进程。
4. 兼容原 UUID/keypair/short ID/SNI/Vision、public/advertise port 和客户端配置。文档说明 timeout/lifecycle 边界及取消/关闭归属。
5. 发布测试包括本报告 A–H、private IP、TCP/25（其余危险端口参数化）、BitTorrent、global final reject 生效对照；目标端记录零转发；错误 UUID 与错误 REALITY 分层验证。加入失败申请/回滚、监听冲突、重启后策略保持和单进程所有权测试。
6. 能力出现在新的**公开发布**、schema/capabilities 和正式产物后，再由 NoBrand 实现显式映射和复跑验收。rc.3 继续声明不支持此迁移，不以本地构建解锁。

## HY2 Legacy Certificate

### Actual generator / Legacy CA / Legacy leaf

真实旧生成器执行 P-256 keygen，再运行：

```text
openssl req -new -x509 -days 3650 -key <synthetic-key> -out <synthetic-cert> -subj /CN=probe.example
```

未传 SAN、KU、EKU 或显式 extension config。实际扩展受系统 OpenSSL 配置影响。本次是 OpenSSL 3.0.13；系统 `[req]` 的 `x509_extensions=v3_ca`，该节配置 `basicConstraints=critical,CA:true`。不能保证所有历史 OS 生成相同扩展；必须检查每份既有材料。

| 属性 | 本次按实际 generator 生成的合成旧材料 |
| --- | --- |
| CA certificate | **同一个自签证书**，没有独立 CA 文件/生成步骤 |
| 被当作 TLS leaf 的证书 | **同一个证书**，链中第一个也唯一一个对象 |
| subject / issuer | `CN=probe.example` / `CN=probe.example` |
| BasicConstraints | 存在，critical，`CA:TRUE`，没有单独的 CA:FALSE leaf |
| KeyUsage | **扩展缺失**；不是显式禁止签名 |
| EKU | **扩展缺失**；不是显式 clientAuth-only |
| SAN | DNS/IP SAN 均缺失；仅有 CN |
| 其他扩展 | SubjectKeyIdentifier / AuthorityKeyIdentifier，均 non-critical |
| validity | `2026-10-18T12:05:23Z` 至 `2036-10-15T12:05:23Z`；3650 天 |
| key / signature | EC prime256v1 / P-256；ECDSA-SHA256；私钥与证书匹配 |
| self signature / explicit-root verification without hostname | PASS / PASS |
| chain order | 单个 PEM certificate；无需猜测 CA/leaf 交换次序，原始失败与排序无关 |
| 文件 | cert 0644、key 0600、直接父目录 0700；key-first atomic replacement + rollback |

整个实验中原始合成证书/私钥字节保持一致。控制组签发到不同路径；没有替换真实配置或用户证书。

### Client trust model

**A. insecure TLS。** 旧 URI 明确含 `insecure=1`；Mihomo exporter 为 `skip-cert-verify: true`；sing-box exporter 为 `tls.insecure=true`。都没有导出 CA trust、证书 pin/fingerprint 或普通 hostname/SAN 校验。

因此证书变更对这些**实际默认配置**不会触发证书身份校验。该结论由源码和真实旧 Mihomo 配置实验同时支持。手工加固过的客户端不在这个保证内，不能自动当作默认配置处理。

### rc.3 reject point / exact category

| 阶段 | 原证书结果 | 精确含义 |
| --- | --- | --- |
| NoBrand `legacy_tls()` | 能从唯一 CA:TRUE 对象取得显式 anchor | 不生成任何证书 |
| NoBrand `tls_check()` | `CAPABILITY_UNSUPPORTED: rc.3 requires a non-CA TLS leaf; existing certificate unchanged` | OpenSSL 的 CN fallback 验证先通过，随后 NoBrand 的显式 CA-leaf gate 拒绝 |
| public `inbound validate` | **成功** | 仅验证结构、路径/CA 参数形状，未证明文件可被 runtime 准入 |
| public `inbound plan` | **成功** | 本夹具的实际记录；并不表示材料已被 runtime 接受 |
| public `inbound apply` | **失败**，公开 CLI：`invalid: command rejected` | 公共 error category 为 `invalid`；没有向 CLI 暴露内部所有细节 |
| 原始公开 `tlsconfig.Snapshot()`，独立夹具直接调用 | `invalid: TLS certificate identity or trust invalid` | 精确内层拒绝路径，由公开未修改函数测得 |
| 对应 Go x509 校验 | `x509: certificate relies on legacy Common Name field, use SANs instead` | `leaf.Verify(DNSName=server_name, explicit roots, intermediates)` 先失败；**默认证书尚未执行到后面的 IsCA gate** |

Snapshot 的完整顺序：安全文件快照/权限归属 → `tls.X509KeyPair` → parse first cert → explicit root/intermediate pool → `leaf.Verify()` → 显式 `leaf.IsCA` 拒绝 → 成功后附加 CA。原材料 parse、key match、文件权限、签名、有效期均通过；不是“证书损坏”，也不是缺少 EKU 或链顺序导致首次失败。

### Independent TLS / HY2 runtime capability

| 控制材料 | Go pair load | Go chain+hostname | rc.3 material apply | 原公开 Snapshot |
| --- | --- | --- | --- | --- |
| 原始 CA:TRUE、仅 CN | PASS | 缺 SAN，拒绝 | 拒绝 | identity or trust invalid |
| 自签 CA:TRUE，SAN 正确，digitalSignature+keyCertSign，serverAuth | PASS | PASS（信任该自身 anchor） | 拒绝 | server certificate must be a leaf |
| 原 CA 签发的新 CA:FALSE/SAN leaf | PASS | PASS（旧 anchor） | PASS | PASS |
| 新 CA + 合格 leaf | PASS | PASS（新 anchor） | PASS | PASS |
| SAN leaf，没有 KU/EKU 扩展 | PASS | PASS | PASS | PASS |
| 过期 leaf | PASS | 拒绝 | 拒绝 | identity or trust invalid |
| EKU 仅 clientAuth | PASS | 拒绝 | 拒绝 | identity or trust invalid |
| KU 仅 keyEncipherment，**无 digitalSignature** | PASS | **PASS** | **PASS** | **PASS** |
| certificate/key mismatch | 失败 | 不进入校验 | 拒绝 | invalid TLS certificate or private key |

Go 版本 **1.26.3**，与公开 rc.3 构建身份一致。Go TLS 1.3 实际握手与 echo：

- 原证书 + insecure client：PASS。
- 原证书 + 显式旧 CA + hostname 校验：缺 SAN，拒绝。
- 原证书 + 自定义**精确 DER SHA256 pin**校验：PASS；TLS 证明对应私钥持有。这是一个可安全绑定既有身份的受控模型，不是旧 NoBrand 默认导出的配置。
- SAN 的 CA:TRUE 对照 + 自身 anchor + hostname：PASS，说明 CA bit 本身不是 TLS 加密/签名必然失败的原因。
- 过期/错误 EKU 对照也能与 insecure client 握手；所以“insecure 握手成功”不能当作有效性或身份安全证明。

实际 HY2 控制：

| Server / client | Handshake + HY2 auth + TCP echo + UDP 64/512 |
| --- | --- |
| 正式旧 Xray、原证书、实际旧导出 Mihomo | PASS |
| 公开 rc.3 原始 HY2 backend 独立夹具、原证书、同一旧 profile | PASS |
| 同一 backend、同 CA 新 leaf、旧 profile **不改** | PASS |
| 同一 backend、新 CA+leaf、旧 profile **不改** | PASS |
| 原证书、错误 HY2 auth | BLOCKED |
| 原证书、把旧客户端改为正常证书验证 | BLOCKED（不受信；即使信任旧 root，Go 对照仍因 SAN 失败） |

backend 夹具直接调用公开 `backend.NewServer()`，使用原 HY2 H3/QUIC、Salamander 和认证实现，替换的只有审计目标 echo 回调。它从 `tls.LoadX509KeyPair()` 直接得到 `tls.Config`，**没有调用/修改正式 Snapshot**。这证明缺口位于材料准入契约，不是 HY2 runtime 无法承载旧证书。

### Server certificate replacement impact

| 客户端信任策略 | 新 leaf、原 CA | 换 CA+leaf | fingerprint 变化 |
| --- | --- | --- | --- |
| 实际旧默认 NoBrand profile，insecure | **YES，真实 HY2 实验** | **YES，真实 HY2 实验** | **YES，未配置 pin** |
| 信任旧 CA，并正常 hostname 校验 | 合格 SAN leaf **YES，Go TLS 实验** | **NO，旧 anchor 下 unknown authority** | leaf 指纹变化无关；CA anchor 变化有关 |
| 精确 leaf DER fingerprint pin | **NO，Go 自定义 pin 实验** | **NO，同一实验** | **NO，fingerprint mismatch** |
| 正常系统 PKI、无旧 CA/pin | 原默认材料本来不能通过 | DEPENDS，新材料是否受信且匹配 hostname | 由 CA/hostname 验证决定 |
| CA pin、SPKI pin、混合手工策略 | DEPENDS | DEPENDS | 本轮未声称覆盖全部客户端 pin 实现 |

因此“所有老客户端换证都不用改”不成立；“默认老客户端换证一定中断”也不成立。Go 的精确 leaf pin 模型与某些客户端自动识别 non-leaf CA pin 的行为不同，不能混为一谈。

### Security assessment and validator assessment

旧合成证书是**技术上特殊但可用于 TLS 签名/加密的材料**：当前有效、P-256、匹配私钥、自签名正确。CA:TRUE、缺 KU/EKU 不等价于密码学损坏。缺 SAN 使它不满足现代 hostname 认证；CA 私钥直接用于在线 TLS 也把签发权限与在线身份混在一起。

**旧默认客户端的安全模型不提供服务端身份认证。** 成功加密、HY2 password auth 和 Salamander 不补足这个缺口；不能把运行成功写成默认连接已抵抗主动中间人。Go 对照 pin 模式在额外可信分发前提下提供身份绑定，不能无声替用户新增 pin。

标准/运行时依据：

- [RFC 5280 §4.2.1.9 / §4.2.1.12](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.2.1.9) 定义 CA bit 和 KU/EKU 处理。若存在用途限制，就必须遵守；“没有 EKU”和“显式错误 EKU”不能等价处理。
- [RFC 8446 §4.4.2.2](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.4.2.2) 要求 TLS 1.3 签名证书在 KU 存在时允许 digitalSignature。本轮 KU-only-keyEncipherment 控制违反这一条件。
- [Go 1.26.3 x509 VerifyHostname](https://pkg.go.dev/crypto/x509@go1.26.3#Certificate.VerifyHostname) 忽略 legacy CN；本次实际得到缺 SAN 错误。
- [Go 1.26.3 TLS Config](https://pkg.go.dev/crypto/tls@go1.26.3#Config) 明确 insecure 跳过链和 hostname，需另行验证才能抵抗主动中间人；本轮自定义 pin 是该类受控校验。

判断需要分层，不能用一个“invalid”概括：

| 部分 | 评价 |
| --- | --- |
| rc.3 当前 verified PKI / 非 CA leaf 导出契约下拒绝缺 SAN、过期、错误 EKU、key mismatch | **CORRECT**；不能全局取消 hostname、chain 或用途验证 |
| 把所有服务端材料都强制套入上述新导出契约 | **INCOMPLETE for migration**；没有表达“保留既有自签服务端身份”的独立策略 |
| CA:TRUE 一律拒绝 | 对其文档化的非 CA leaf 产品契约是有意策略；相对于 TLS runtime 和原材料保留目标则 **TOO STRICT**。不是 CA:TRUE 使密码学无效，不能据此宣称标准强制换证 |
| 接受存在 KU 但不允许 digitalSignature 的 ECDSA TLS 1.3 证书 | **INCOMPLETE / BUGGY**；正式 apply 与原 Snapshot 都实际接受；Go runtime 能握手也不能使其符合 RFC 8446 |

**SPLICORE BACKWARD-COMPATIBILITY GAP/DEFECT**：无法表达原证书保留，尽管原公开 HY2 backend 能互通、受控 pin 能验证既有身份。这个判断不要求把不安全客户端当成安全，也不要求放宽 verified PKI 模式。旧默认 insecure 模型的修复属于另一项显式安全迁移。

### NoBrand migration options

| Option | 老客户端兼容性 | 安全性 | 自动化可行性 | 回滚 |
| --- | --- | --- | --- | --- |
| **A. 原证书/私钥/链完全保留** | 默认客户端与既有精确 pin 都可保留 | 保留当前安全水平；不会修复默认 insecure；需拒绝过期、坏 key、明确用途冲突 | **rc.3 不可行**；需独立 legacy identity policy，不能改 NoBrand 映射假装支持 | 最直接，字节/路径无需变化 |
| **B. 原 CA 签发合格新 leaf** | 默认旧 profile 实测 YES；旧 CA trust 可继续；旧 leaf pin 会断 | 可保持信任 anchor；使用 SAN、CA:FALSE、digitalSignature、serverAuth；旧默认 insecure 仍不自动得到身份认证 | 仅对检查过的可签发 CA/key、明确授权换证的实例；本次合成原 CA 可签发且 rc.3 接受 | 保留原 cert/key/state/profile 与服务归属，事务失败恢复旧材料和旧服务；不能覆盖原 key 后再称可回滚 |
| **C. 换整套 CA+leaf** | 默认旧 profile 实测 YES；旧 CA trust / pins 需更新 | 分离 CA 与 leaf，但未更新的 insecure 客户端仍不认证服务端 | rc.3 可接受合格材料；影响超出必要，不能作为静默默认 | 保存完整旧 CA/key/leaf/配置及信任信息；回滚服务和材料一体恢复 |
| **D. 显式不兼容迁移并更新客户端** | **NO**，按计划更新 trust/pin/profile | 可以消除旧 insecure 债；必须可靠分发新信任 | 需要用户安排客户端更新；非本轮零客户端变更目标的默认方案 | 客户端与服务端信任都要有双向回退窗口 |

优先级仍为 A → 经明确批准、确认客户端 trust 的 B → 必要时 C/D。**B 已证明是默认旧 profile 的 server-only 可行方案，不代表获准执行，也不覆盖手工 pin 客户端。** 本轮没有隐式换证。

### Owner

**MIXED**，具体责任：

- **SPLICORE**：服务端证书保留/导出信任策略未分离的兼容缺口；另有 KU 约束验证缺陷。
- **LEGACY CONFIG**：仅 CN 的材料无法满足现代 hostname 验证；默认 insecure 客户端有真实的身份安全债。这不等于旧证书坏 key/坏签名，也不证明必须立刻换 CA。
- **NOBRAND**：后续需要显式选择 A/B/C/D、识别 trust 影响、备份和事务回滚；当前 fail-closed 是正确行为。不是“把原 CA 当新 leaf 字段填入”即可修复的 mapping defect。

### Required Fix / ready-to-send Splicore issues

**Issue 1 — Separate server TLS material admission from verified client-profile trust; add explicit legacy self-signed identity preservation.**

1. 默认 verified PKI/non-CA leaf 行为保持严格；新增独立、显式选择的既有自签身份保留策略，精确定义支持的材料，不能自动启用、静默签发或删除 CA bit。
2. 服务端 admission 不能因为自动导出客户端需要 SAN/CA chain 而把所有可用服务端身份混成同一契约。已有外部 profile 应可按原样继续；verified/system/CA-pinned/fingerprint-pinned/insecure 导出各自声明实际 trust，不把无 SAN 的旧材料导出为“hostname verified”。
3. 保留 private file 安全检查、PEM/key parsing、pair match、有效期、签名/anchor 和显式 KU/EKU 限制；兼容模式也不得接受过期、key mismatch、被用途明确禁止的 TLS server key。SAN 缺失仅可作为明确策略下的 identity 模型差异处理，不可全局忽略。
4. 对 CA:TRUE 与缺 SAN 给分层、稳定、脱敏的错误 category/reason；结构 validate、material plan/apply 及 runtime 的边界写清楚，禁止把 validate PASS 误作可启动证明。
5. 验收：本报告真实旧 generator 夹具在明确兼容模式下原 bytes/profile 完成 HY2 auth/TCP/UDP；默认严格模式仍拒绝不合格 PKI；同 CA 换 leaf、换 CA、精确 pin 的兼容矩阵；坏 key、过期、错误 EKU/KU、异常文件/链顺序的负向测试；事务/回滚不改变既有身份。

**Issue 2 — Enforce present KeyUsage.digitalSignature for TLS 1.3 server certificates.**

- 最小复现：有效 ECDSA P-256 leaf、SAN 正确、可信 CA、EKU=serverAuth、critical KU=keyEncipherment 且没有 digitalSignature。公开 rc.3 `inbound apply`、原 Snapshot 和 Go handshake 当前都接受。
- 预期：在共享服务端 TLS 材料准入拒绝，返回用途冲突；KU 扩展不存在时不与显式禁止签名混淆；不同 TLS 使用场景按协议定义，不机械要求所有证书都有 KU。
- 此修复独立于放宽兼容性；不得以“Go 接受”替代标准用途约束。

NoBrand 后续只有在公开能力可验收时实现 A；若用户明确选择 B，则单独设计“同 CA 签发 leaf、保留原身份备份、客户端影响预览、失败回滚”的迁移事务。两条路径都不在本轮实施。

## Can NoBrand Freeze Now?

**NO**

REALITY 存在已证明的服务端策略缺失。HY2 原证书保留仍被 rc.3 拒绝，且没有获准的显式换证迁移。测试夹具成功或默认 insecure 客户端接受新证书均不等于 blocker 已消除。

## Next Action

1. 将上述 REALITY issue 和两项 TLS issue/spec 交给 Splicore 开发对话；本轮只产出规格，不访问/修改 `D:\code\Splicore`，不发送外部消息。
2. 在新的公开版本中完成能力与材料策略验收，再回 NoBrand 做映射/事务实现。保留目前两个 fail-closed gate。
3. 若优先选择 server-only B 路径，先显式确认该实例的客户端信任模型、换 leaf 授权和回滚契约；不为 Freeze 自动选方案。

## Reproduction and Validation

依赖：既有已核验 rc.3 source/archive/binary、Xray ZIP/binary、Mihomo gzip、Go 1.26.3、OpenSSL、root 创建独立 netns 的能力。所有 cache 在忽略的 `.lab` 中；公共树没有 runtime binary 或 key。

Go fixture 使用独立模块 `github.com/ike-sh/Splicore/auditfixture`，`require github.com/ike-sh/Splicore v0.0.0`，`replace` 到已核验的公开 commit 解包目录，复制其 go.sum；只编译本报告 Go helper。这样可以访问原公开 internal validator/backend，不增加或改动 Splicore 源文件。构建产物为 `.lab/splicore-ownership-audit/tls-fixture`，不是 `splicore`。

先构建独立夹具，再以 root 运行审计：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/splicore_ownership_audit.py --build-fixture
PYTHONDONTWRITEBYTECODE=1 NOBRAND_OWNERSHIP_NETNS=1 \
  unshare --net python3 tests/helpers/splicore_ownership_audit.py
```

审计程序验证自身与 PID 1 不在同一 netns 才设置 lo；原始输出先写忽略目录，再将脱敏 JSON 复制到本报告旁。断言包含正向客户端、负向认证、预期策略差异和真实 network reject 组合反例；**audit PASS 不代表 parity PASS**。

| Gate | Result |
| --- | --- |
| 现有默认 Bash entries | **50/50 PASS**；完整 `scripts/test.sh` 退出 0 |
| Bash syntax | **108 files PASS** |
| ShellCheck | **PASS**；ordered source graph + 70 direct files，warning gate |
| 原有 repository sanitization / secret scan | **PASS**；全部新增公开文件后的最终重扫 PASS，7 类泄漏计数均为 0 |
| 新 Python helper | AST parse PASS；独立 netns 实验断言 PASS |
| 新 Go helper | Go 1.26.3 build PASS；原公开 backend / Snapshot 实验 PASS |
| 本轮原始公开 source vs 已核验 source archive | **510 files，0 differences** |
| 既有候选文件哈希 | **175 files，0 changes**；包含用户要求保护的全部 functional files |
| 原生可选 runtime suite | 9 entries **NOT RUN**；本轮只运行上述独立审计矩阵 |

完整 suite 覆盖 build/check、syntax、ShellCheck、原有全部默认测试；日志末尾为 `[PASS] NoBrand test suite`。本轮不将预期 parity 反例计为迁移通过。

## Git

基线 HEAD：`f98cf70e7159c07826101676a4a08394f0a203f9`，branch=`main`。

本轮仅新增两个审计 helper、此报告及相邻脱敏 evidence JSON。开始时已有迁移工作保持原样；175 个既有候选文件的 SHA256 全量对照证明没有改变既有 functional/test/report 字节。

| Action | Result |
| --- | --- |
| Stage | **NONE；index EMPTY** |
| Commit | **NONE** |
| Push | **NONE** |
| Tag | **NONE** |
| Release | **NONE** |

没有新的 Freeze，没有生产访问、宿主 firewall 变更、sidecar workaround 或本地未发布核心依赖。
