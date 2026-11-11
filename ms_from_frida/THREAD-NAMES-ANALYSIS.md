# Frida 17.15.3 / GLib 线程创建与线程名分析

## 范围与结论

分析对象是当前锁定快照：

| 仓库/模块 | commit |
|---|---|
| Frida root | `831acfffc87483c4a1d665b9b6ae89e66bcefaa2` |
| frida-core | `e0ec2bee624b6ea11b72d5cc74639132449789c2` |
| frida-gum | `e5b0d7d6a9a83da1750b6fc654006a714b81a890` |
| GLib | `92d65736b198c2cf131f691dd83db0b25f7b02d2` |

结论：当前 patch 已覆盖一部分关键线程名，但没有覆盖所有线程创建点，也没有覆盖 GLib thread-pool 的所有动态命名路径。尤其是当前默认的“GLib 源码增量构建”方案中，`004` 的二进制字符串替换不会参与构建，因此 `pool-%s` 仍会保留原规则。

这里区分三件事：

1. 创建线程：`g_thread_new()`、Vala `new Thread<T>()`、`pthread_create()`、`clone()`。
2. 传入线程名：创建 API 的 name 参数或格式化规则。
3. 真正设置 OS 线程名：GLib 的 `g_thread_proxy()` 最终调用 `g_system_thread_set_name()`，POSIX 实现再调用 `pthread_setname_np()`。

## GLib

### 生产代码中的命名点

| 位置 | 创建/命名方式 | 原始或当前规则 | 当前 patch 覆盖 | 备注 |
|---|---|---|---|---|
| `glib/glib/gmain.c:6817` | `g_thread_new()` | 原：`gmain`；当前：`ms-gm` | 是，`002` | GLib worker context 的后台线程 |
| `glib/gio/gdbusprivate.c:311` | `g_thread_new()` | 原：`gdbus`；当前：`ms-db` | 是，`002` | GDBus shared thread |
| `glib/glib/gthreadpool.c:321` | `g_thread_try_new()` | `pool-%s`，`%s = g_get_prgname()` | 否，源码模式 | GTask/非 exclusive thread pool 的工作线程命名来源之一 |
| `glib/glib/gthreadpool.c:494` | `g_thread_try_new()` / `g_thread_new_internal()` | `pool-%s`，`%s = g_get_prgname()` | 否，源码模式 | exclusive/non-exclusive pool 都可能经过此路径 |
| `glib/glib/gthreadpool.c:1486` | `g_thread_new()` | 原：`pool-spawner`；当前：`mspl-spawner` | 是，`002` | 全局 pool spawner |
| `glib/glib/gthreadpool.c:321,494` | 格式化失败分支 | 初始值为 `pool` | 否 | 当 `g_get_prgname()` 为空时不会变成 `mspl` |

### GLib 的底层设置链

```text
g_thread_new(name, ...)
        ↓
g_thread_new_internal()
        ↓
pthread_create()
        ↓
g_thread_proxy()
        ↓
g_system_thread_set_name(name)
        ↓
pthread_setname_np()
```

关键实现位置：

| 位置 | 作用 |
|---|---|
| `glib/glib/gthread.c: g_thread_proxy()` | 在线程入口消费 `thread->name` |
| `glib/glib/gthread-posix.c:1422-1424` | 调用 `pthread_create()` |
| `glib/glib/gthread-posix.c:1483-1492` | 按平台调用 `pthread_setname_np()` |
| `glib/glib/gthread-win32.c:722` | Windows 线程名实现，不属于 Android 目标 |

因此修改 GLib 的线程名参数，确实会影响最终 Android 进程中的 OS 线程名；但仅修改 `gmain`、`gdbus` 和 spawner 字面量，并不能覆盖 `pool-%s` 工作线程。

## frida-gum

| 位置 | 创建/命名方式 | 线程名或规则 | 当前 patch 覆盖 |
|---|---|---|---|
| `gum/bindings/gumjs/gumscriptscheduler.c:127` | `g_thread_new()` | 原：`gum-js-loop`；当前：`my_loop` | 是，`006` |
| `gum/backend-linux/gumprocess-linux.c:734` | `g_thread_new()` | `gum-modify-thread-worker` | 否 | ptrace/线程修改通信 worker |
| `gum/backend-linux/gumprocess-linux.c:3956` | `pthread_create()` | 没有显式线程名 | 否 | `gum_linux_thread_proc` 等待控制信号 |
| `gum/backend-linux/gumprocess-linux.c:717` | `clone()` | 没有普通线程名参数 | 否 | 创建不同 process group 的辅助执行上下文，不是标准命名入口 |

`006` 只覆盖 JavaScript scheduler 的线程名替换，不会覆盖 Gum 的 Linux process worker。

## frida-core：Android/通用运行时相关

| 位置 | 创建/命名方式 | 线程名或规则 | 当前 patch 覆盖 |
|---|---|---|---|
| `src/frida-glue.c:63` | `g_thread_new()` | `frida-main-loop` | 否 |
| `server/server.vala:181` | Vala `new Thread<int>()` | `frida-server-main-loop` | 否；当前主要是 Darwin 分支 |
| `lib/gadget/gadget-glue.c:128` | `g_thread_new()` | 原：`frida-gadget`；当前：`mygadget-worker` | 是，`001` |
| `src/agent-container.vala:106` | Vala `new Thread<bool>()` | `frida-agent-container` | 否 |
| `lib/agent/agent.vala:366,562,670` | Vala `new Thread<bool>()` | `frida-eternal-agent` | 否 |
| `lib/agent/agent.vala:1432` | Vala `new Thread<void>()` | `frida-agent-emulated` | 否 |
| `lib/base/p2p.vala:892` | Vala `new Thread<bool>()` | `frida-generate-certificate` | 否 |
| `src/linux/linux-host-session.vala:538` | Vala `new Thread<void>()` | `frida-android-helper` | 否 |
| `src/system.vala:15,77` | Vala `ThreadPool` | 不直接指定名称；落入 GLib `pool-%s` 规则 | 否 |
| `src/linux/helpers/loader.c:64` | 间接 `pthread_create()` | 没有显式线程名 | 否 | 注入 loader 在目标进程中创建 worker |

其中 `frida-agent-*`、`frida-main-loop` 等名称会随 agent/server/gadget 的实际编译配置进入相应产物。当前 patch 没有统一替换为 `ms-*` 规则。

## frida-core：其它平台或构建工具

以下位置属于源码树中的实际线程创建点，但通常不进入 Android server/gadget 产物：

| 位置 | 名称/规则 | 说明 |
|---|---|---|
| `src/darwin/frida-helper-service.vala:8` | `frida-helper-main-loop` | Darwin helper |
| `src/windows/frida-helper-process.vala:162` | `frida-helper-factory` | Windows helper |
| `src/fruity/device-monitor-portable.vala:161` | `frida-core-device-usb` | Fruity/Apple USB monitor |
| `src/qnx/qinjector.vala:247` | `pulse-reader` | QNX injector |
| `src/fruity/helpers/upload-receiver.c:1042` | 无显式名称 | 测试/辅助上传接收器 |
| `tools/resource-compiler.vala:209` | `ThreadPool`，无显式名称 | 构建期资源压缩工具 |
| `src/fruity/fruity-host-session.vala:2698` | `ThreadPool`，无显式名称 | Apple kperf 数据处理 |

## 当前 patch 覆盖矩阵

| Patch | 覆盖内容 | 当前状态 |
|---|---|---|
| `debug/bisect/frida-core.patch` | Gadget 二分停止点 | 仅 debug |
| `debug/bisect/glib.patch` | GTask 二分停止点 | 仅 debug |
| `release/thread-name/glib.patch` | GLib 统一分配 `Jit thread pool worker thread N`，维护 TID → 完整逻辑名注册表 | release 已覆盖 GLib/Vala/ThreadPool |
| `release/thread-name/frida-gum.patch` | Gum Linux worker 接入注册表；线程枚举优先返回完整逻辑名 | Android/Linux 已覆盖 |
| `release/thread-name/frida-core.patch` | loader 和 Android helper 使用描述性线程名 | Android/Linux loader/helper 已覆盖 |
| 其它 patch | 未发现线程名统一替换 | 未覆盖 |

## 线程名是否具有业务语义

### 总体判断

在 Android 目标和 GLib/Frida 的通用运行时路径中，线程名主要是可观测性元数据，不是线程身份，也不是核心调度、同步或注入协议的索引键。当前源码没有发现通过 `gmain`、`gdbus`、`pool-*`、`frida-agent-*` 等固定名称反向查找线程的 Android 生产路径。

GLib 自身的 API 文档已经明确说明：`g_thread_new()` 的 `name` 用于在 debugger 中区分线程，不用于其它目的，也不要求唯一；随后它只是被保存并传递到平台的 `pthread_setname_np()` 等接口。

### 按线程名读取，但不按线程名控制

| 代码位置 | 行为 | 语义判断 |
|---|---|---|
| `glib/glib/gthread.c` 的 `g_thread_proxy()` | 在线程入口设置 OS 线程名 | 展示/诊断；不是查找机制 |
| `frida-gum/gum/backend-linux/gumprocess-linux.c` 的 `gum_linux_query_thread_name()` | 读取 `/proc/self/task/<tid>/comm` | 通过 TID 找线程，再读取名称 |
| `frida-gum/gum/backend-linux/gumprocess-linux.c` 的 `gum_process_find_thread_by_id()` | 查找并返回线程详情 | 明确按数字 TID 查找，不按名称 |
| `frida-gum/bindings/gumjs/gumquickprocess.c` 的 `Process.enumerateThreads()` | 将 `GumThreadDetails.name` 暴露给脚本 | API 可观测字段；用户脚本可以自行按名称过滤 |
| `frida-gum/gum/backend-linux/gumthreadregistry-linux.c` | 在线程观察/注册信息中附带名称 | 线程观察元数据；线程身份仍是 TID/`pthread_t` |
| `frida-core/src/linux/frida-helper-backend.vala`、`proc-mem-injector.vala` | 使用 `/proc/<pid>/task/<tid>`、`tgkill(pid, tid, ...)` | 注入、暂停、恢复按数字 TID 操作 |

因此，改名通常不会改变 Frida/GLib 内部“找到哪个线程”或“暂停哪个线程”的结果。但名称仍可能影响外部调试器、`ps -T`、`/proc/.../comm`、崩溃报告、日志采集器和用户自己的 Frida 脚本；这些属于外部可观测契约，不能简单视为完全无影响。

### 已确认的固定线程名查找例外

Apple/Fruity 注入路径存在一个有实际协议语义的例外：

| 代码位置 | 逻辑 | 影响范围 |
|---|---|---|
| `frida-core/src/fruity/injector.vala:135-159` | 枚举 LLDB 线程，并匹配 `^frida-gadget-tcp-(\d+)$`；匹配后提取端口，认为目标中已有 Gadget | Apple/Fruity 注入路径 |
| `frida-core/lib/gadget/gadget.vala:649` | TCP Gadget 启动后设置 `frida-gadget-tcp-<port>` | 与上面的发现逻辑配套 |
| `frida-core/lib/gadget/gadget.vala:660` | UNIX socket 设置 `frida-gadget-unix` | 当前所见注入器没有用它提取端口 |
| `frida-core/lib/gadget/gadget-glue.c:232` | Android 实现的 `Environment.set_thread_name()` 为空；注释说明该能力目前只在 i/macOS 实现，因为 Fruity.Injector 依赖它 | Android 不走这个名称发现机制 |

这说明“线程名永远只是展示”并不绝对成立：在 Fruity/Apple 这一处，它被复用成了 Gadget 存在性和 TCP 端口的发现信号。但这属于跨模块协议约定，不是 GLib 的线程池机制，也不是 Android Frida server/gadget 的通用线程查找方式。

### 对当前 patch 的含义

当前 `001`、`002`、`004`、`006` 修改的是诊断标签或线程角色标签；对 Android 运行时而言，没有证据表明这些名称是 Frida 内部业务查找键。需要保留的边界是：

1. 不应把 Apple/Fruity 的 `frida-gadget-tcp-<port>` 改成任意名称，除非同时修改对应的注入器匹配规则。
2. Android 路径可以统一改名，但应在验证脚本中检查 `Process.enumerateThreads()`、`/proc/<pid>/task/*/comm` 以及外部监控工具的兼容性。
3. 如果将来新增“按名称查找线程”的代码，应优先改为使用 TID/`pthread_t` 等稳定身份；名称不唯一且受平台长度限制，不适合作为内部主键。

## 最终结论

当前独立 patch `009–011` 实现的是默认方案 A，覆盖 Android/Linux 运行时的统一命名：

- `g_system_thread_set_name()` 是统一入口，因此 `gmain`、GDBus、`pool-%s`、pool spawner、Frida main loop、agent、gadget、Vala Thread 等 GLib 创建线程都进入方案 A。
- Gum Linux 的直接 pthread worker 由 `010` 显式接入；远程 loader 由 `011` 使用无 GLib 依赖的前缀设置。
- Android/Linux OS 层名称按要求为 `Jit thread pool`；完整编号通过 Gum/GLib 注册表提供。
- 旧 `004` 仅是历史的预编译 `.a` 修补记录，不属于当前 workflow。
- Apple/Fruity `frida-gadget-tcp-<port>` 协议名、Windows 专用线程实现和测试专用线程仍属于明确豁免或单独平台范围。

本报告只统计生产源码路径；GLib、Frida 和 Meson 的测试用例还包含大量测试专用线程名，它们不应被当作 Android 发布产物的运行时线程名。

统一命名的推荐实现见 [`THREAD-NAMING-DESIGN.md`](THREAD-NAMING-DESIGN.md)。默认方案严格使用完整逻辑名 `Jit thread pool worker thread N`，Android/Linux OS 层仅保留前 15 个可见字符 `Jit thread pool`；另保留默认关闭的 `ms-tN` 紧凑命名方案，后续再决定运行时开关、编译时开关或独立 patch。
