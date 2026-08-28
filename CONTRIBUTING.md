# Development Workflow

## 范围

当前产品范围只接受 Mieru、Snell v4/v5、Xray-core Hysteria2 与 Plain VLESS + FinalMask + Sudoku/TCP 相关变更。Snell v1、v2、v3、v6 不受支持；v6 只允许维护精确历史状态清理、负向测试与历史文档。不要加入其它协议、Web panel 或自动迁移 Xray-OneClick 配置。

Mieru 是成熟母体。除 Common Core adapter 外，不重写 isolated-v2、多用户、quota、tc、state、export 或卸载逻辑；`/var/lib/mita-oneclick` 继续是 Mieru 权威 state。

## 源码与构建

- 修改 `src/*.sh`；`src/` 是真源。
- `scripts/build.sh` 的显式 module manifest 是权威顺序。
- 不直接维护生成的四个 installer。

```bash
bash scripts/build.sh
bash scripts/build.sh --check
```

## 必跑测试

```bash
bash scripts/test.sh
bash scripts/test.sh --runtime
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
git diff --check
```

`--runtime` 需要网络。不能运行时必须记录 `NOT RUN` 与原因，不能写成 PASS。Mieru smoke 只可更新项目 identity assertion，不能删除 isolated-v2、用户事务、quota、tc、export、firewall、migration 或卸载保护断言来“修绿”。

## 协议约束

- Snell runtime 必须来自 Surge 官方 HTTPS；v6 resolver 不能硬编码；官方 release metadata 和 binary upgrade 一起回滚；v6 必须断言无 Mihomo。
- HY2 以 `ike-sh/Xray-OneClick/lib/57-hysteria2.sh` 为协议第一事实来源，保持 Xray、v2、TLS/h3、P-256/3650/CN、16-byte auth/Salamander 与 URI。
- VLESS Sudoku 以 `ike-sh/Xray-OneClick/lib/50-vless-enc.sh` 的 TCP FinalMask/Sudoku inbound 为结构事实来源，但必须解耦并排除 VLESS Encryption。服务端只允许 plain `decryption=none`，客户端只允许 `encryption=none`；禁止调用 key generator、保存 key pair、ML-KEM、xorpub、method、RTT 或 ticket。
- VLESS 只允许 TCP + FinalMask/Sudoku；禁止扩展为 REALITY、Vision、XHTTP、FullStack 或其它 VLESS 组合。客户端只生成经真实 Xray 验证的 JSON 与分享链接，不伪造 Mihomo/sing-box 配置。
- HY2 与 VLESS 共用 NoBrand-owned Xray binary，但 config/state/service/process 必须隔离。runtime upgrade 必须把两个 active 服务视为一个验收事务。
- Endpoint setter 必须证明 config/unit/firewall hash 不变、没有 service action、客户端输出变化。
- transport key 使用 `tcp:PORT` / `udp:PORT`；配置提交前二次验端口。
- state/config 使用同目录临时文件和原子 rename；破坏性清空前验证 NoBrand namespace。
- Doctor 不输出 secret；任何验收失败不得输出“完成”。
- Golden test 必须固定 UUID/port/Sudoku password，使用 `jq -S` canonical diff，并用同一真实 Xray 校验 server/client config。Encryption-absence test 是强制闸门。

提交源码时同步提交 tests/scripts/CI/docs 与重新生成的 installer。不要 push、创建 release 或发布 package，除非维护者另行要求。
