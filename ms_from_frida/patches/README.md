# 当前活动 patch 分类

当前 patch 从官方 Frida 17.15.3 固定 commit 的干净源码开始应用。每个 patch 只承担一个目的，便于 release/debug 组合和二分定位。

| 构建 | 目的 | 目标 | 内容 |
| --- | --- | --- | --- |
| release | process-name | frida-gum | `g_set_prgname("gogogo")` |
| release | agent-memfd-name | frida-core | agent memfd 名 `msagent.so` |
| release | thread-name | glib | GLib/GIO/GTask/GThreadPool 线程命名基础 |
| release | thread-name | frida-gum | Linux worker 线程名 |
| release | thread-name | frida-core | loader、Android helper 的描述性线程名 |
| release | injection-group-stop | frida-core | 注入分组的 `SIGSTOP`/`PTRACE_SEIZE` 保护 |
| release | gum-runtime | frida-gum | ELF/ART `PrettyMethod` 运行时处理和 ARM64 trampoline |
| release | helper-injection | frida-core | helper 注入源码、Meson 和构建集成 |
| debug | logging | frida-gum | `MYOBS` 运行时日志；仅 debug |
| debug | bisect | frida-core | Gadget 二分停止点；仅 debug |
| debug | bisect | glib | GTask 二分停止点；仅 debug |

## 应用顺序

Workflow 按以下顺序对每个官方子仓库应用：

```text
frida-core:
  release/agent-memfd-name
  release/injection-group-stop
  release/helper-injection
  release/thread-name
  [debug/bisect]

frida-gum:
  release/process-name
  release/gum-runtime
  release/thread-name
  [debug/logging]

glib:
  release/thread-name
  [debug/bisect]
```

`frida-core` 的线程名 patch 依赖 helper injection；`frida-gum` 的 runtime patch 依赖 process-name 已建立的 release 基线。上述顺序已在临时官方基线中通过 `git apply --check` 验证。

## Profile 约束

- `release` 是默认构建，不能出现 `MYOBS`、`mygadget.stop.*`、`mygadget.nop` 或旧 Android helper 名。
- `debug` 同时启用 logging 和 bisect，便于一次 workflow 运行完成观测与二分。
- 线程名 release 统一使用 `Jit thread pool worker thread N` 方案；旧的 `mygadget-worker`、`ms-gm`、`ms-db`、`mspl-*`、`my_loop` 不再作为活动方案。
- GLib 始终使用源码构建。当前 workflow 没有 `FRIDA_BUILD_GLIB=0` 回退，也没有静态库等长字符串替换路径。
