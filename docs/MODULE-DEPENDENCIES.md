# Module dependencies

## Ordinary protocols

```text
10-cli-prelude / 90-ui / 99-main
              ↓
19-splicore: read-only legacy refusal
              ↓
runtime/splicore.py
  ├─ splicore-release.json: public v0.3.0-rc.4 exact pin
  ├─ artifact validation and atomic install
  ├─ native desired → private validation generation
  ├─ one active daemon / splicore-launch.py
  ├─ REALITY Local Tunnel Guard and routing
  └─ matching client profiles / native rollback
```

Mieru、Snell、HY2、TUIC、REALITY 不依赖旧独立 Core 下载器。旧转换、证书导入、服务
snapshot/restore、多 Core rollback 已移除。旧文件/服务名只在只读检测边界使用。

## Shared product layer

`15-core-state` 提供产品 registry 和 lifecycle lock；`16-core-port` 读取 native desired
及保留功能的端口；`16-core-ingress` 管理 Profile 和 native 节点引用；`17-core-endpoint`
提供 Endpoint/firewall 工具；`18-core-nodes` 提供 native backup/restore 和产品资源管理。

普通协议 generation 的 DB、控制 socket、控制 key、TLS 文件和配置由 Splicore manager
独占管理。备份含私有材料，权限必须为 `0600`，不得作为公开报告附件。

## Retained features

| Feature | Dependency / ownership |
|---|---|
| FinalMask/Sudoku | 固定 Xray；仅其拥有的配置、服务和 runtime |
| SSH Tunnel | 现有系统 OpenSSH sshd；只管理所属账号/策略，保留确认/watchdog |
| Forward | 所属 nftables table 或固定 Realm；保留外部副作用 rollback |
| Ingress / BBR | 公共网络策略；strict native bind 与所属 fragment，不更改路由 |

协议菜单只请求协议和业务参数。版本、原生安全结构、证书和单 runtime 事务由统一管理器
生成。不能调用已移除的 legacy adapter。

历史多 Core 依赖与原结论见 `docs/reports/SPLICORE_*` 旧报告；这些历史证据不构成当前
安装合同。当前接口见 [rc.4 contract](SPLICORE-RC4-CONTRACT.md)。
