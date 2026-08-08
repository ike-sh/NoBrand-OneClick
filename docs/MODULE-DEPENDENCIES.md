# Module Dependencies

本文记录 v2.2.0 模块化必须保持的 Bash 顺序与全局副作用。它是维护约束，不定义新的模块 API。

## 构建顺序

`scripts/build.sh` 显式列出 20 个模块，并按数字前缀从 `00-bootstrap.sh` 拼接到 `99-main.sh`。模块不得通过运行时 `source` 组装，发布产物始终是自包含的 `install-mita.sh`。

依赖层次可概括为：

```text
bootstrap / constants / CLI prelude
                 ↓
             core / state
                 ↓
 platform / network / profile configuration
                 ↓
 users / instances ↔ users state ↔ tc / quota ↔ backup actions
                 ↓
 daemon / firewall ↔ service / BBR ↔ client export
                 ↓
 lifecycle → status actions → UI → main
```

用户、实例、配置、回滚和服务层存在合法的函数向后引用。最终平铺脚本会在调用 `main` 前完成全部函数定义，因此不要为了消除这些循环依赖而改写函数接口。

## 顶层执行顺序

以下顺序会影响 source 与直接执行语义，必须保持：

1. `set -euo pipefail` 与 `umask 077`；
2. 路径、版本、默认值和可变运行时全局变量；
3. Bash 环境检查；
4. `on_error` 与全局 `ERR` trap；
5. usage、日志与翻译 helpers；
6. 顶层 argv `while` 解析；
7. 其余函数定义；
8. 唯一 `main`；
9. 现有 `MITA_SOURCE_ONLY` guard。

`MITA_SOURCE_ONLY=1` 只跳过 `main`；strict mode、umask、trap 和参数解析仍按原有行为执行。不要擅自替换为 `BASH_SOURCE` 判断，也不要改变裸 `main` 调用方式。

## 全局状态与动态作用域

- 配置、Profile、endpoint、版本通道和用户操作通过共享全局变量传递状态。
- `load_install_state` 在安全检查后读取 state，并更新这些共享配置变量。
- 管理锁使用文件描述符 8 和 `_ADMIN_LOCK_HELD` 实现可重入计数。
- package service guard 使用 `PACKAGE_SERVICE_GUARD_*` 动态状态，并在受控子 shell 中导出真实 systemctl 路径。
- 用户事务与 Python helpers 使用 `_U_*` 等动态变量；不要用额外函数或子 shell 包裹模块内容。
- 全局 `ERR` trap 位于 CLI prelude；菜单路径还包含局部 trap 清理，移动时必须保留其作用域。

源码模块没有 `readonly` 或顶层 `export` 契约。新增跨模块状态前应优先沿用现有调用与测试模式，避免创建隐式初始化顺序。

## 维护规则

- 移动代码时保持完整函数、heredoc 和节标题，不在 heredoc 中间切分。
- 不直接编辑 `install-mita.sh` 或 `dist/install-mita.sh`。
- 修改 `src/` 后重新构建，并对生成产物运行完整 ShellCheck、Docker smoke 和 compatibility smoke。
- 模块文件可由 lint-only `scripts/shellcheck-src.sh` 按构建顺序 source；用户运行的发布脚本绝不依赖该文件。
