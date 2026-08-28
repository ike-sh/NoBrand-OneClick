# Source Audit

审计日期：2026-08-28（Asia/Shanghai）

## Mieru mother project

- `ike-sh/mieru-OneClick`
- 目标仓库初始 commit：`2b3e2371746a0dd0248887a216d3a45d6ac8e95c`
- 本地没有单独 `D:\code\mieru-OneClick`；目标目录初始就是干净 Source A clone。
- 审计全部 `src/`、build、README、CONTRIBUTING 与模块文档。

确认端口链：default-route IPv4 → tail×100 → xx01-xx99 → random circular scan → state/ss/netstat/bind probe。Display Endpoint 只写 users state/client exports，不改 instance/listener/firewall/tc/quota。

## Xray-OneClick Hysteria2

- 只读仓库：`D:\code\Xray-OneClick`
- 审计 commit：`5b6a049f1c24469c79e233989248deb9ecf3481c`
- 第一事实来源：`lib/57-hysteria2.sh`，并审计 constants/output/system/path/config/state/network/service/runtime/CLI/menu/tests。

确认 Xray hysteria v2、TLS/h3、Salamander、16-byte hex auth/obfs、P-256 self-signed 3650、CN=SNI、0600/0644 与 `insecure=1` URI。

## Xray-OneClick VLESS FinalMask/Sudoku

- 同一只读仓库与 commit：`5b6a049f1c24469c79e233989248deb9ecf3481c`
- 结构事实来源：`lib/50-vless-enc.sh:190-398`
- 配套审计：`lib/50-vless-common.sh`、paths/config/state/runtime/service/network/doctor/smoke/export/view/CLI/menu/test harness 与 `tests/test_config_generation.sh`

确认 reference Sudoku JSON：

```json
{
  "tcp": [{
    "type": "sudoku",
    "settings": {
      "password": "<16-byte-hex>",
      "ascii": "prefer_ascii",
      "paddingMin": 0,
      "paddingMax": 3
    }
  }]
}
```

NoBrand 保持 reference inbound 的 VLESS、UUID、TCP、`security=none`、FinalMask/Sudoku、sniffing 结构。唯一协议差异是把 reference Encryption decryption secret 替换为 plain VLESS 合法值 `decryption=none`，client 对应 `encryption=none`。

已识别并明确不移植的 Encryption 耦合点：runtime key-generation subcommand、encryption/decryption pair、auth/method、client RTT、server ticket、ML-KEM、xorpub 与 share-link secret。NoBrand 没有这些 state、参数或安装依赖。

Golden test 固定 UUID/port/password，从上述 reference inbound 构造 expected，删除仅允许变化的 tag/email/decryption 层后执行 `jq -S` canonical diff；runtime 测试使用同一 Xray-core 26.3.27 对 server/client `run -test` 并完成 localhost 数据面。

## Surge Snell official upstream

- Release page：`https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md`
- Assets：`https://dl.nssurge.com/snell/`
- 2026-08-28 动态解析：v4.1.1、v5.0.1、v6.0.0rc2（v6 仅用于删除决策前的最后一次资格测试，不再是产品 runtime）。
- 真实 amd64 binary 验证 `--help`、`--version`、wizard config 与 localhost listener。

确认 v5 official runtime 没有 `quic=true` 一类 server config 字段；同一进程会 bind 同号 TCP/UDP。NoBrand 因而把 QUIC OFF/ON 实现为 state 与 firewall exposure，而不是虚构配置参数：OFF 只拥有 TCP，ON 拥有同号 TCP/UDP，并验证两个 socket 的 PID 都等于 service MainPID。

Snell v6 最后一次强制公网资格测试使用官方 sing-box 1.14.0-rc.1、NoBrand exporter 和 `211.136.162.185:16895`，结果为 3/20 HTTPS，download/upload 均失败，公网双端抓包仍有流量。结论固定为 `SNELL_V6_FINAL_TEST=FAIL`、`SNELL_V6_DECISION=REMOVE`；此测试不得重跑。生产代码只保留 exact historical-state migration，resolver/download/export/status/nodes/Doctor/service/runtime 全部拒绝 v6。

## Mihomo upstream

- Official release：MetaCubeX/mihomo v1.19.30。
- Debian CPU 使用同一官方 release 的 `linux-amd64-compatible` asset；普通 amd64 asset 需要 x86-64-v3，不能在该 CPU 启动，属于 asset/CPU compatibility，不是协议失败。
- SHA-256：asset `db214c7a2517e63c150d123178d16d102e03a241ccdae4e5e07ffbe9cf56c6f9`；binary `8ad44e28fe72be4640254b96741b677f4074991b99186cc4486a1c28ded02b1a`。
- 源码与真实 config check/runtime 确认 Mieru、Snell v4、Snell v5 non-QUIC、Hysteria2 支持；FinalMask/Sudoku 不支持。普通 Snell `udp: true` 不是官方 v5 QUIC Proxy wire，因此 Mihomo QUIC 状态为 `NOT VERIFIED`。

## sing-box upstream

- Official testing release：SagerNet/sing-box v1.14.0-rc.1。
- Binary SHA-256：`dc4464152b4aa70907d96486953fafbc16ab06e6a4265dbc56e2acb2830c0336`。
- 源码与真实 `sing-box check`/runtime 确认 Snell v4、Snell v5 non-QUIC（client `version:4` wire-compatible expression）和 Hysteria2 支持。
- Mieru、FinalMask/Sudoku 与 Snell v5 official QUIC Proxy Mode 不支持；NoBrand 返回 `CLIENT_UNSUPPORTED`，不生成假配置。
