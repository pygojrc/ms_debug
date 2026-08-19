# Patch 后线程名复核

## 结论摘要

本次复核基于当前锁定的 Frida 17.15.3 / GLib 快照、已应用的 `001–011` patch，以及已经构建的 Android `arm64`、`x86_64` 产物。

需要区分两个问题：

1. 源码中是否仍保留旧的线程名字面量；
2. 线程运行后，Android `/proc/<pid>/task/<tid>/comm` 是否仍显示旧名字。

结论如下：

- 默认 `FRIDA_BUILD_GLIB=1` 时，所有经过 GLib `GThread` 入口的 Frida、GIO、GDBus、GTask、GThreadPool、Vala `Thread<T>` 线程，最终都会进入 `ms_thread_name_set_current()`，OS 名被设置为 `Jit thread pool` 前 15 个字符。
- 因此，`frida-main-loop`、`frida-agent-container`、`frida-eternal-agent`、`pool-%s`、`mygadget-worker` 等旧名字虽然仍保留在源码/二进制中作为 source name、调试信息或格式字符串，但不会作为这些 native GLib 线程的最终 OS 名。
- 在 `012` 实施前，仍然实际绕过当前方案的 Android 固定名是 Java Android helper 的 `Connection Listener` 和 `Connection Handler`；现在已由 `012` 接入统一命名，但必须重新生成 `helper.dex` 才会进入最终产物。
- 原始 `clone()`、非 Android Fruity/QNX 的直接 `pthread_create()` 仍没有统一命名；它们不进入当前 Android server/gadget 的主要 native 线程路径，但属于完整源码树中的未覆盖点。
- `frida-gadget-tcp-<port>` / `frida-gadget-unix` 是 Apple/Fruity 的协议型名称。Android glue 中该函数为空，因此 Android 不会实际设置这些名字；Darwin 仍会设置，不能直接改成 Scheme A。

## 判断依据

### GLib 统一入口

`glib/gthread.c:g_thread_proxy()` 现在无条件调用：

```c
g_system_thread_set_name (thread->name);
```

`glib/gthread-posix.c:g_system_thread_set_name()` 已改为：

```c
ms_thread_name_set_current (name);
```

`ms_thread_name_set_current()` 会忽略原始 source name 的格式，只分配：

```text
Jit thread pool worker thread N
```

并将 Android/Linux OS 层设置为：

```text
Jit thread pool
```

所以，源码旧名称是否被逐字替换，不能单独作为运行时覆盖判定。

## Android 运行时：源码旧名字仍在，但最终 OS 名已被覆盖

| 源码位置 | 源码中的旧/固定名 | 创建路径 | Patch 后运行时判断 |
|---|---|---|---|
| `subprojects/frida-core/src/frida-glue.c:63` | `frida-main-loop` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-core/src/agent-container.vala:106` | `frida-agent-container` | Vala `new Thread<bool>()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-core/lib/agent/agent.vala:366,562,670` | `frida-eternal-agent` | Vala `new Thread<bool>()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-core/lib/agent/agent.vala:1432` | `frida-agent-emulated` | Vala `new Thread<void>()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-core/lib/base/p2p.vala:892` | `frida-generate-certificate` | Vala `new Thread<bool>()` | 进入 GLib 统一入口，最终为 Scheme A；仅在 `HAVE_NICE` 路径使用 |
| `subprojects/frida-core/src/linux/linux-host-session.vala:538` | `frida-android-helper` | Vala `new Thread<void>()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-core/lib/gadget/gadget-glue.c:128` | `mygadget-worker` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-gum/bindings/gumjs/gumscriptscheduler.c:127` | `my_loop` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/frida-gum/gum/backend-linux/gumprocess-linux.c:740` | `gum-modify-thread-worker` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/glib/glib/gthreadpool.c:321,494` | `pool-%s` / fallback `pool` | `g_thread_try_new()` / `g_thread_new_internal()` | source rule 未改，但最终进入 GLib 统一入口 |
| `subprojects/glib/glib/gthreadpool.c:1486` | `mspl-spawner` | `g_thread_new()` | source 仍是独立角色名，但最终进入 GLib 统一入口 |
| `subprojects/glib/glib/gmain.c:6817` | `ms-gm` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |
| `subprojects/glib/gio/gdbusprivate.c:311` | `ms-db` | `g_thread_new()` | 进入 GLib 统一入口，最终为 Scheme A |

这些名称仍可通过 `strings` 看到，例如当前 `ms_server` 中仍有 `pool-%s`、`pool-spawner`、`frida-main-loop` 和 `gum-modify-thread-worker`。这属于编译进来的 source name 或格式字符串，不表示它们仍是 `/proc` 中的最终线程名。

## 确认仍未被当前 patch 覆盖的 Android 固定名

### Android Java helper

| 源码位置 | 固定名 | 创建方式 | 结论 |
|---|---|---|---|
| `subprojects/frida-core/src/android-helper/re/frida/Helper.java:79` | 原始 `Connection Listener` | Java `createWorker()` | `012` 改为 `Jit thread pool`，完整逻辑名按 TID 保存 |
| `subprojects/frida-core/src/android-helper/re/frida/Helper.java:98` | 原始 `Connection Handler` | Java `createWorker()` | `012` 改为 `Jit thread pool`，完整逻辑名按 TID 保存 |

这两个字符串曾经在构建出的 `android-arm64/ms_server` 中发现，说明 Android helper 内容被纳入 server 相关产物/资源。`009–011` 是 native C/GLib/Gum/loader patch，不会影响 Java `Thread`；现在由独立 `012-frida-core-android-helper-descriptive-thread-name.patch` 处理。

#### Helper.java 的命名设计与实施状态

这里必须分别定义两个概念：

1. Java 层的 `Thread.getName()`，用于 Java 日志、异常和 Java 调试器；
2. Linux/Android 内核的线程名，即 `/proc/<pid>/task/<tid>/comm`，用于 `top`、`ps`、Perfetto、native 调试器等。

Android ART 会把 Java 线程名同步到 native 线程名，但 Linux 名称上限是 15 个可见字节。AOSP ART 的实现对过长、且不含 `@` 或 `.` 的名称取末尾 15 个字符后再调用 `pthread_setname_np()`。[AOSP ART 的 `SetThreadName` 实现](https://android.googlesource.com/platform/art/+/master/libartbase/base/utils.cc) 和 [Java 线程启动到 native 线程的实现](https://android.googlesource.com/platform/art/+/master/runtime/thread.cc) 可作为依据；实际 Android 16 镜像仍应在 AVD/真机上复测。

因此当前两个名字的显示结果应区分为：

| Java 源码名字 | Java `Thread.getName()` | Android `/proc/.../comm` 常见显示 |
|---|---|---|
| `Connection Listener` | `Connection Listener` | `ection Listener` |
| `Connection Handler` | `Connection Handler` | `nection Handler` |

直接把完整 Scheme A 名称 `Jit thread pool worker thread N` 传给 `new Thread(String)` 也不合适：ART 会倾向于显示其末尾 `worker thread N`，而不是要求的前缀 `Jit thread pool`。

当前已按推荐方案实施“短 OS 名 + 长逻辑名”的无 JNI 设计：

```java
private static final String OS_THREAD_NAME = "Jit thread pool";
private static final AtomicInteger NEXT_WORKER_INDEX = new AtomicInteger();
private static final ConcurrentHashMap<Integer, String> LOGICAL_NAMES =
        new ConcurrentHashMap<>();

private static Thread createWorker(final String role, final Runnable task) {
    final int index = NEXT_WORKER_INDEX.getAndIncrement();
    final String logicalName =
            "Jit thread pool worker thread " + index;

    return new Thread(OS_THREAD_NAME) {
        @Override
        public void run() {
            Thread.currentThread().setName(OS_THREAD_NAME);
            int tid = android.os.Process.myTid();
            LOGICAL_NAMES.put(tid, logicalName);
            try {
                task.run();
            } finally {
                LOGICAL_NAMES.remove(tid);
            }
        }
    };
}
```

`Connection Listener` 和每个 `Connection Handler` 都通过这个工厂创建，不再把旧角色名作为 OS 线程名。这样得到的结果是：

- `/proc`、`ps`、Perfetto 等显示严格为 `Jit thread pool`；
- Java 内部诊断可以通过 TID 查到完整的 `Jit thread pool worker thread N`；
- 不依赖 GLib，也不需要为独立 helper 进程引入 JNI/native 库；
- listener 和 handler 共享同一编号分配器，编号单调递增且可区分。

如果强制要求 Java `Thread.getName()` 本身也返回完整 Scheme A 名称，同时又要求 `/proc` 保留前 15 个字符，则仅修改 Helper.java 不够，需要额外 JNI/native bridge：Java 线程启动后先使用完整 Java 名称，再由 native 代码调用 `prctl(PR_SET_NAME, "Jit thread pool", ...)`。这会增加 helper 的 native 编译、ABI 打包和 dex/so 加载链路，不建议作为当前 x86_64/arm64 第一版。

`Helper.java` 的修改必须重新生成 `helper.dex`。Frida 的 Meson 构建消费的是仓库中的 `src/android-helper/helper.dex`，不是每次自动编译 Java 源码；对应规则位于 `src/android-helper/Makefile`，依赖 Android SDK 的 `android.jar`、`javac` 和 `d8`。当前构建入口已在主 Meson/Ninja 构建前调用 `scripts/build_android_helper.sh`，并通过 `012` 让 Makefile 支持外部指定这些工具。Java 实现使用匿名 `Runnable`，避免 Android `android.jar` bootclasspath 下生成无法解析的 `LambdaMetafactory` 引用。

#### Android x86_64/arm64 路径的最终显示分析

下表只覆盖当前关注的 Android x86_64 和 arm64，不把系统服务、ART 自身、zygote、渲染库或第三方库创建的线程误归因到 Frida patch：

| 路径 | 运行时线程 | Java 名称 | `/proc/.../comm` / OS 显示 | Frida 侧可见逻辑名 | 状态 |
|---|---|---|---|---|---|
| `frida-core/src/android-helper/re/frida/Helper.java:79` | helper 连接监听线程 | 原始 `Connection Listener` | 重新生成 Dex 后为 `Jit thread pool` | Java TID 表中为 `Jit thread pool worker thread N` | 已覆盖 |
| `Helper.java:98` | 每个连接的 helper handler 线程 | 原始 `Connection Handler` | 重新生成 Dex 后为 `Jit thread pool` | Java TID 表中为 `Jit thread pool worker thread N` | 已覆盖 |
| `frida-core/src/frida-glue.c`、Vala `Thread<T>`、GIO/GDBus/GTask/ThreadPool | Frida/GLib native worker | source name 仍可能是旧字面量 | `Jit thread pool` | `Jit thread pool worker thread N`（自构建 GLib registry） | 已覆盖 |
| `frida-gum/gum/backend-linux/gumprocess-linux.c:3970` | Gum 直接 `pthread_create()` worker | 无 Java 名称 | `Jit thread pool` | registry 中为 `Jit thread pool worker thread N` | 已覆盖 |
| `frida-core/src/linux/helpers/loader.c:65` | 注入目标进程中的 loader worker | 无 Java 名称 | `Jit thread pool` | 通常只有 OS 前缀；loader 无 GLib registry，无法提供完整逻辑名 | 已覆盖 OS 名，逻辑名受限 |
| `frida-gum/gum/backend-linux/gumprocess-linux.c:723` | ptrace 用 raw `clone()` 辅助上下文 | 无 Java 名称 | 未显式设置；通常继承 clone 时的进程名，且属于独立进程组 | 不保证出现在父进程的线程 registry 中 | **未统一** |
| `Helper.main` / `Looper.loop()` | helper 初始 Java 主线程 | 启动方式决定，通常为 `main` | 启动方式和 Android runtime 决定，通常为 `main` | 不属于 native GLib registry | 平台默认名 |

这里的“当前通常为”是基于 Android/Linux ART 的命名规则推导，不等同于已经完成 AVD 运行时验证；尤其 helper 的实际启动器可能影响主线程默认名。系统/ART/zygote/第三方库线程也不在本仓库 patch 的控制边界内，它们可能显示 `main`、`Binder:*`、`RenderThread`、`FinalizerWatchdogDaemon` 等平台名称，不能从 Frida 源码树确定，也不应纳入本次 Android x86_64/arm64 patch 覆盖率。

## 绕过 GLib 的未命名或未统一命名路径

这些位置没有当前旧的固定名称，但也没有保证使用 Scheme A：

| 源码位置 | 创建方式 | 当前状态 | 范围 |
|---|---|---|---|
| `subprojects/frida-core/src/linux/helpers/loader.c:65` | 目标进程中的间接 `pthread_create()` | 已由 `011` 设置 `Jit thread pool` 前缀 | Android/Linux 已覆盖 |
| `subprojects/frida-gum/gum/backend-linux/gumprocess-linux.c:3970` | 直接 `pthread_create()` | 已由 `010` 在入口调用注册表；但仅在能包含 `glib/ms-thread-name.h` 时生效 | Android/Linux 已覆盖；兼容 bundle 需使用带自定义 GLib 的 SDK 才能完整覆盖 |
| `subprojects/frida-gum/gum/backend-linux/gumprocess-linux.c:723` | 原始 `clone()`，`CLONE_VM \| CLONE_SETTLS` | 没有设置 Scheme A 名称；它是不同线程组的 ptrace 辅助执行上下文，不是普通 `pthread` 线程 | Linux 特殊路径 |
| `subprojects/frida-core/src/fruity/helpers/upload-receiver.c:1042` | 直接 `pthread_create()` | 没有显式名称，也没有当前 patch 接入 | Fruity/Apple |
| `subprojects/frida-core/src/qnx/qinjector-glue.c:482` | 远程进程中的 `pthread_create()` | 没有名称参数，不能由 Android/native GLib patch 覆盖 | QNX |

其中 `clone()` 辅助上下文不能简单套用 GLib API：源码注释明确说明它不能安全调用 libc 或常规 `clone()` wrapper。若未来要求 Linux 所有辅助执行上下文也统一命名，需要增加无 libc 依赖的 `prctl`/syscall 路径，并确认它是独立进程还是线程组成员。

## Apple/Fruity 的固定协议名称

| 源码位置 | 名称规则 | 当前状态 |
|---|---|---|
| `subprojects/frida-core/lib/gadget/gadget.vala:649` | `frida-gadget-tcp-<port>` | Apple/Fruity 中由 `gadget-darwin.m` 真实设置；Fruity injector 用正则提取端口，不能直接删除 |
| `subprojects/frida-core/lib/gadget/gadget.vala:660` | `frida-gadget-unix` | Apple/Darwin 路径使用；当前发现逻辑不提取端口，但仍属于平台固定名 |
| `subprojects/frida-core/lib/gadget/gadget-glue.c:232` | `set_thread_name()` | Android/non-Darwin glue 为空函数，因此 Android 不会设置上述名称 |

这不是 Android server/gadget 的遗漏，而是跨模块协议兼容边界。若要统一 Apple 名称，必须同步修改 Fruity injector 的匹配逻辑。

## 非 Android、测试和构建期线程

以下源码中仍有固定名或 ThreadPool，但不属于当前 Android 发布产物的运行时主路径：

- Darwin helper：`frida-helper-main-loop`；经过 GLib 时会被统一，但 Darwin Gadget 的协议型名称仍需保留。
- Windows helper：`frida-helper-factory`；不适用 Android POSIX patch。
- QNX：`pulse-reader` 及远程 `pthread_create()`。
- Fruity USB monitor：`frida-core-device-usb`。
- Java helper 之外的 Android helper/系统线程：属于独立 Java/Android runtime 命名域。
- `tools/resource-compiler.vala`、Fruity kperf `ThreadPool`：构建工具或 Apple 专用运行时。
- `tests/` 下的大量 `*-test-*`、`named-sleeper` 等：测试专用，不应当作为发布产物覆盖率判断。

## `FRIDA_BUILD_GLIB=0` 回退模式的注意事项

当前 Scheme A 的完整结论只适用于默认源码构建 GLib：

```bash
FRIDA_BUILD_GLIB=1
```

如果设置 `FRIDA_BUILD_GLIB=0`：

- `009` 不会进入预构建 GLib；
- `010` 的 GLib registry 依赖可能关闭；
- `011` 仍可覆盖 loader；
- `004` 只对预编译 `.a` 做有限的等长字符串替换，不能替代 GLib 统一入口；
- 因此 `pool-%s`、GLib/Vala 线程和部分固定 source name 不能宣称已完整进入 Scheme A。

## 最终覆盖结论

| 类别 | 当前 patch 后状态 |
|---|---|
| Native GLib/GIO/GDBus/GTask/GThreadPool | Scheme A 已覆盖最终 OS 名；旧 source name 仍可能留在二进制 |
| Vala `Thread<T>` | Scheme A 已覆盖最终 OS 名，只要最终链接的是自构建 GLib |
| Gum Linux 直接 `pthread_create()` worker | `010` 已覆盖；兼容 bundle 要确认使用带 registry 的 GLib SDK |
| Linux loader 远程 worker | `011` 已覆盖 OS 前缀；没有完整 registry 是设计限制 |
| Android Java helper | `012` 已覆盖；旧 `helper.dex` 或跳过 Dex 重建时仍会恢复旧显示名 |
| Android/系统/第三方库自行创建的线程 | 当前 patch 不覆盖 |
| Linux raw `clone()` 辅助上下文 | 未命名、未覆盖，属于特殊辅助进程/线程路径 |
| Apple/Fruity `frida-gadget-tcp-<port>` | 有协议语义，不能直接统一改名 |
| QNX/Fruity/Windows 专用路径 | 未统一，非 Android 范围 |

因此，若目标是“Android x86_64/arm64 产物中 Frida/GLib native 线程和 Java helper 不再显示旧名”，当前 `009–012` 已覆盖；构建流程必须实际执行 `build_android_helper.sh`。剩余未统一的 raw `clone()` 是短生命周期的 ptrace 辅助上下文，系统/第三方线程不属于 Frida patch 控制范围。
