# 当前活动 patch 分类

当前 patch 从官方 Frida 17.15.3 固定 commit 的干净源码开始应用。每个 patch 只承担一个目的，便于 release/debug 组合和二分定位。

## 平台矩阵

| 平台 | 说明 |
| --- | --- |
| `all` | android / linux / windows 都应用 |
| `linux-family` | android 与 linux（依赖 Linux 内核语义：memfd、ptrace/SIGSTOP） |
| `windows` | 仅 windows |
| `debug` | 仅 debug profile |

## Patch 列表

| 构建 | 目的 | 目标 | 平台 | 内容 |
| --- | --- | --- | --- | --- |
| release | process-name | frida-core | all | server 启动时 `g_set_prgname("gogogo")` + `ms_process_name_set_current("gogogo")`；默认数据目录 `re.ms.server`、主循环线程名 |
| release | agent-memfd-name | frida-core | linux-family | agent memfd 名 `msagent.so` |
| release | thread-name | glib | all | 新增 `ms-thread-name` 与 `ms-process-name` 模块（POSIX/Windows 后端），统一线程名与进程可见名 |
| release | thread-name | frida-gum | linux-family | Linux worker 线程名 |
| release | thread-name | frida-core | linux-family | Android helper、Linux loader 的描述性线程名 |
| release | injection-group-stop | frida-core | linux-family | 注入分组的 `SIGSTOP`/`PTRACE_SEIZE` 保护 |
| release | gum-runtime | frida-gum | all | ELF/ART `PrettyMethod` 运行时处理和 ARM64 trampoline |
| release | helper-injection | frida-core | linux-family | helper 注入源码、Meson 和构建集成 |
| release | control-port | frida-core | all | 默认控制监听端口为 `27056` |
| release | exceptor-handler-only | frida-core | all | 可选关闭 exceptor 对 `sigaction`/`signal` 的 inline hook（`#ifdef HAVE_ANDROID` 门限，默认关闭） |
| release | windows-identity | frida-core | windows | agent/helper/管道/临时目录标识改为 `msagent`/`ms-*` 前缀；修复 `frida-so-inject` 空入口调用崩溃 |
| debug | logging | frida-gum | all | `MYOBS` 运行时日志；统一走 `g_log`（Linux stderr / Windows OutputDebugString） |
| debug | bisect | frida-core | all | Gadget 二分停止点 |
| debug | bisect | glib | all | GTask 二分停止点 |

## 应用顺序

Workflow 按以下顺序对每个官方子仓库应用：

```text
frida-core:
  release/process-name
  release/control-port
  release/exceptor-handler-only
  release/thread-name
  [linux-family: release/agent-memfd-name, release/injection-group-stop, release/helper-injection]
  [windows: release/windows-identity]
  [debug/bisect]

frida-gum:
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
- 线程名统一使用 `Jit thread pool worker thread N` 方案；旧的 `mygadget-worker`、`ms-gm`、`ms-db`、`mspl-*`、`my_loop` 不再作为活动方案。
- GLib 始终使用源码构建。当前 workflow 没有 `FRIDA_BUILD_GLIB=0` 回退，也没有静态库等长字符串替换路径。
