# 旧 patch 历史归档

`patchs/` 保存迁移前的 001–012 混合 patch、回滚 patch 和构建记录，仅用于追溯旧实现与当前 `frida/` 快照的差异。

当前 workflow 不读取本目录，也不执行这里的脚本或回滚 patch。当前活动 patch 已重新按构建 profile 和目的拆分到 [`../patches/`](../patches/)：

- release：进程名、agent memfd 名、线程名、注入分组停止、Gum runtime、helper injection；
- debug：打印日志、frida-core/GLib 二分调试点。

当前构建入口、GLib 自构建和 release/debug 选择见 [`../BUILD-WORKFLOW.md`](../BUILD-WORKFLOW.md)。
