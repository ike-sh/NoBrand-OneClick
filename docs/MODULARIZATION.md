# Mieru OneClick Source Modularization

## 目标

v2.2.0 完成了开发源码模块化。开发者在 `src/` 中维护源码，普通用户仍只需要仓库根目录的单文件 `install-mita.sh`：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash
```

模块化只改变开发与维护方式，不改变安装、升级、配置或运行方式。

## 目录结构

```text
src/
  00-bootstrap.sh
  05-constants.sh
  10-cli-prelude.sh
  15-core-state.sh
  20-platform-mieru.sh
  25-network-mtu.sh
  30-users-instance.sh
  35-users-state.sh
  40-tc-quota.sh
  45-backup-user-actions.sh
  50-diagnostics.sh
  52-user-actions-ui.sh
  55-profile-config.sh
  60-daemon-firewall-network.sh
  65-service-bbr.sh
  70-client-export-install.sh
  80-lifecycle.sh
  85-status-actions.sh
  90-ui.sh
  99-main.sh
```

| 模块 | 职责 |
|---|---|
| `00-bootstrap.sh` | strict mode、umask 与脚本头部环境 |
| `05-constants.sh` | 版本、路径、默认值与运行时全局变量 |
| `10-cli-prelude.sh` | Bash 检查、错误 trap、帮助、日志与顶层参数解析 |
| `15-core-state.sh` | 通用工具、安全文件操作、锁与安装状态读写 |
| `20-platform-mieru.sh` | 平台探测、安装脚本管理、Mieru 包与服务安装 |
| `25-network-mtu.sh` | 端口、地址和 MTU 的基础验证与选择 |
| `30-users-instance.sh` | 多用户基础状态与 isolated-v2 实例生命周期 |
| `35-users-state.sh` | `users.json` 事务、用户变更与配置同步 |
| `40-tc-quota.sh` | tc 限速、配额、到期扫描与调度器 |
| `45-backup-user-actions.sh` | 备份恢复、导入导出与主要用户操作 |
| `50-diagnostics.sh` | Doctor 与只读性能诊断 |
| `52-user-actions-ui.sh` | 其余用户操作及用户管理交互 |
| `55-profile-config.sh` | Profile、交互配置、配置加载与服务端 JSON |
| `60-daemon-firewall-network.sh` | daemon 应用、firewall 所有权与 endpoint helpers |
| `65-service-bbr.sh` | 服务启动验收与 BBR/FQ 管理 |
| `70-client-export-install.sh` | 客户端导出、入口映射与 fresh-install helpers |
| `80-lifecycle.sh` | install、reconfigure、upgrade 与 uninstall 编排 |
| `85-status-actions.sh` | 状态、配置调整及服务 start/stop/restart |
| `90-ui.sh` | 主菜单与子菜单 |
| `99-main.sh` | 唯一 `main` 和现有 `MITA_SOURCE_ONLY` 测试守卫 |

这些文件是按固定顺序拼接的开发源码，不是可任意顺序单独 source 的公共模块 API。

## 构建流程

开发者修改 `src/*.sh` 后执行：

```bash
bash scripts/build.sh
```

构建器使用显式模块清单生成临时文件，先执行 Bash 语法检查，再原子更新：

- `install-mita.sh`：正式 Raw 发布产物；
- `dist/install-mita.sh`：与根目录产物逐字节一致的构建产物。

构建不写入时间、主机名或随机内容，连续构建应产生完全相同的文件。最终脚本完全自包含，不会在用户机器上 source `src/`。

## 设计原则

1. `install-mita.sh` 是用户下载和执行的正式发布产物。
2. `src/` 是唯一推荐修改的开发源码位置，不直接编辑生成文件。
3. 最终运行环境不依赖 `src/`、构建器或其他仓库文件。
4. 模块化只移动完整代码块，不改变运行行为、输出和错误码。
5. state schema、`users.json`、migration、CLI 与用户配置 API 保持兼容。

## 测试流程

修改后至少执行：

```bash
bash scripts/build.sh
bash -n install-mita.sh
shellcheck install-mita.sh
bash scripts/docker-smoke.sh
bash scripts/compat-smoke.sh
git diff --check
bash scripts/build.sh --check
```

所有功能测试都针对生成后的根目录 `install-mita.sh`，不以单独 source 某个源码模块代替发布产物测试。

## 模块依赖

数字前缀表达源码顺序，`scripts/build.sh` 中的显式清单是权威构建顺序；构建器不会依赖 `src/*.sh` 的 glob 排序。Bash 函数允许向后引用，因此模块间存在的用户、实例、回滚与配置循环依赖不需要额外依赖系统。

顶层参数解析必须保留在早期 prelude，`main` 与执行守卫必须位于最后。全局变量、trap、锁和动态作用域约束见 [MODULE-DEPENDENCIES.md](MODULE-DEPENDENCIES.md)。
