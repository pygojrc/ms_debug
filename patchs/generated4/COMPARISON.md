# `ms_debug/patchs` 与全量 diff 对比

## 对比范围

| 项目 | 路径 |
|---|---|
| Frida 17.15.3 基线 | `frida/` |
| `ms_debug` 源码 | `ms_debug/frida/` |
| 仓库已有补丁 | `ms_debug/patchs/*.patch` |
| 新生成全量补丁 | `ms_debug/patchs/generated4/000-full-frida-17.15.3-to-ms_debug.patch` |

全量 diff 按实际文件路径逐项比较，保留符号链接，不跟随符号链接展开；排除了 `.git` 和 `.gitmodules`。共生成约 3282 个文件/路径差异。由于基线仓库和 `ms_debug` 的子模块布局不同，差异主要集中在 `frida/subprojects/`。

## 已有正向 patch 与全量 diff

| 已有 patch | 具体目标位置 | 全量 diff 中是否存在 | 结论 |
|---|---|---:|---|
| `001-frida-core-gadget-bisect.patch` | `frida/subprojects/frida-core/lib/gadget/gadget.vala`、`gadget-glue.c` | 是 | 相同的 Gadget 二分停止点和线程名修改已合并到 `ms_debug/frida` |
| `002-glib-gio-thread-name-and-gtask-bisect.patch` | `frida/subprojects/glib/glib/gmain.c`、`gthreadpool.c`；`gio/gdbusprivate.c`、`gtask.c` | 是 | 相同的 GLib/GIO 线程名与 `GTask` 二分修改已合并 |
| `003-project-build-temporary-sdk-patch.patch` | `frida/scripts/build_frida_android.sh`、`run_podman.sh`，以及新增构建脚本 | 是 | 相同的构建前临时修补 `.a`、构建后恢复、版本检查逻辑已合并 |
| `004-project-thread-name-patcher-script.patch` | `frida/scripts/修补_ms线程名.py` | 是 | 相同的等长字节替换与 `--reverse` 恢复脚本已合并 |
| `005-frida-server-group-stop-inject.patch` | `frida/subprojects/frida-core/src/linux/frida-helper-backend.vala` | 是 | 相同的 `SIGSTOP`、`PTRACE_SEIZE`、`ThreadSuspendScope` 注入窗口控制已合并 |
| `006-frida-gum-runtime-and-pretty-method.patch` | `frida/subprojects/frida-gum/bindings/gumjs/gumscriptscheduler.c`、`gum.c`、`gumelfmodule.c`、ARM64 interceptor | 是 | 相同的 `MYOBS`、ELF 普通内存读取、`PrettyMethod` trampoline 等修改已合并 |
| `007-frida-core-agent-memfd-name-msagent.patch` | `frida/subprojects/frida-core/src/linux/linjector.vala` | 是 | 相同的 agent memfd 名称替换为 `msagent.so` 已合并 |

## `.a` 构建工具修改

| 项目 | 结论 |
|---|---|
| `.a` 文件本身 | `ms_debug/frida` 中没有作为源码提交的 `.a` 静态库文件，因此全量源码 diff 不会产生 `.a` 二进制补丁 |
| 构建工具对 `.a` 的处理 | 已包含在全量 diff 中，主要位于 `frida/scripts/build_frida_android.sh` 等脚本 |
| 处理内容 | 构建前临时修改 `libglib-2.0.a`、`libgio-2.0.a`，构建完成后反向恢复；另涉及 `libfrida-gum-1.0.a`、`libfrida-gumjs-1.0.a` 的复制/产物处理 |
| 与已有 `003` 的关系 | 属于同一类修改；已有 `003` 是可单独应用的聚焦 patch，全量 diff 是最终源码树的整体结果 |

## 全量 diff 中 `ms_debug` 独有的内容

这些内容不属于已有 `001..007` 的核心修改，或不能由这 7 个 patch 单独解释：

| 类型 | 具体位置/示例 | 说明 |
|---|---|---|
| 项目文档 | `frida/docs/` | 注入、Gadget 风险、可复现构建、Frida Gum 修改计划等文档是仓库额外内容 |
| 项目构建脚本 | `frida/scripts/apply_patches.sh`、`build_android.sh`、`copy_outputs.sh`、`apply_production_cleanup_patches.sh` | 用于批量应用补丁、Android 构建、产物复制和生产清理，不等同于 Frida 官方源码修改 |
| 线程名工具 | `frida/scripts/修补_ms线程名.py` | `004` 已记录其新增内容；它同时属于全量 diff 的独有脚本文件 |
| 生产清理逻辑 | `ms_debug/patchs/rollback/` 对应的移除逻辑 | rollback patch 是已有补丁记录，不是最终源码树中的单独 Frida 功能；不能作为新增源码修改重复计算 |
| 子模块链接/布局 | `frida/subprojects/*/subprojects/` | `ms_debug` 增加了跨子模块链接，例如 `frida-gum`、`glib`、`libffi`、`termux-elf-cleaner`；这是源码树布局差异，不属于 `001..007` 的业务修改 |
| 基线差异 | `frida/subprojects/` 大量文件 | 子模块提交版本、测试文件和依赖布局差异会产生大量全量 diff，需要与“本地业务修改”区分 |

## rollback patch 的关系

`patchs/rollback/001..003` 不是额外的正向修改，而是用于在已经应用 `001..006` 的源码树上移除诊断/二分代码的反向 patch。因此：

- 它们的修改范围与全量 diff 有重叠；
- 不应把 rollback patch 再计入 `ms_debug` 的新增功能；
- 应用全量 diff 后，再应用 rollback 会得到生产清理版本，而不是当前调试版本。

## 结论

1. 现有 `001..007` 的核心修改均已进入 `ms_debug/frida`，全量 diff 能找到对应路径和修改。
2. `003` 中对构建工具处理 `.a` 的逻辑也已进入全量 diff，但 `.a` 本身没有被提交为源码文件。
3. 全量 diff 额外包含文档、构建辅助脚本、生产清理相关记录，以及较多子模块布局/版本差异。
4. 若只想迁移调试功能，优先使用已有 `001..007`；若想得到当前完整源码树，使用 `000-full-frida-17.15.3-to-ms_debug.patch`，并注意其路径基于 `frida/` → `ms_debug/frida/`。
