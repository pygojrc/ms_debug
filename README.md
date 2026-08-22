# ms_debug

`ms_debug` 是基于官方 Frida 17.15.3 的 Android 构建仓库。当前源码分析、补丁分类和构建入口均以 `ms_from_frida/` 为准。

## 构建

构建统一通过 GitHub Actions 手动执行，默认是 release 构建；release 默认不启用打印日志、二分停止点等调试 patch。构建参数、产物下载和发布规则见 [`ms_from_frida/BUILD-WORKFLOW.md`](ms_from_frida/BUILD-WORKFLOW.md)。

本地不再运行构建脚本，也不再修改 SDK 中的预编译 `.a`。GitHub workflow 会始终从固定源码构建 GLib/GObject/GIO，再构建 Android `arm64` 与 `x86_64` 的 `ms_server`、`gadget.so`、`frida-code-inject` 和 `frida-so-inject`。

## 补丁

当前活动补丁按目的拆分在 [`ms_from_frida/patches/`](ms_from_frida/patches/)：进程名、agent memfd 名、线程名、注入分组停止、Gum 运行时、helper 注入属于 release；打印日志和二分调试点属于 debug。完整应用顺序和 release/debug 约束见 [`ms_from_frida/patches/README.md`](ms_from_frida/patches/README.md)。

`ms_from_frida/patchs/` 保留为旧版本混合 patch 的历史记录，不是当前 workflow 的输入。仓库内的 `frida/` 仍是既有源码快照，用于对照分析；workflow 会重新 checkout `config/versions.env` 指定的官方 commit。
