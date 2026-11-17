# ms_debug 改动总览与跨版本适配指南

> 本文档面向后续 agent：说明本仓库相对**官方 Frida** 做了哪些改动、每个改动解决什么问题、用什么手法实现，以及官方升级到新版本时如何逐项核对与适配。
>
> 本文不复制 patch 原文。需要看精确 diff 时按文中的路径索引查 `ms_from_frida/patches/`。

## 0. 怎么用这份文档

- **只关心"现在是什么"** → 读 §1 全景 + §2 能力清单。
- **要升级 Frida 版本** → 直接读 §5 适配流程，按检查清单逐项走；每项的"适配锚点"和"失败信号"写在 §2 对应条目里。
- **遇到构建/产物异常** → 先看 §6 已知技术债，很多现象是那里列的历史遗留。

基线版本：Frida **17.15.3**，所有 commit 锁定在 [`ms_from_frida/config/versions.env`](../config/versions.env)。

```text
FRIDA_TAG            17.15.3
FRIDA_ROOT_COMMIT    831acfffc87483c4a1d665b9b6ae89e66bcefaa2
FRIDA_CORE_COMMIT    e0ec2bee624b6ea11b72d5cc74639132449789c2
FRIDA_GUM_COMMIT     e5b0d7d6a9a83da1750b6fc654006a714b81a890
GLIB_COMMIT          92d65736b198c2cf131f691dd83db0b25f7b02d2
LIBFFI_COMMIT        c06a577933f07c76c3f536c9e4ba0f7d9c1e8c4d
LIBICONV_COMMIT      bbbf4561da4847bf95ce9458da76e072b77cabd1
TERMUX_ELF_CLEANER   ab933ec128c6538067cdf3907ebbbc3bc35f1c55
```

## 1. 全景：三类改动

```text
ms_debug/
├── ms_from_frida/
│   ├── config/versions.env        # ① 版本锁定：所有源码的固定 commit
│   ├── patches/<profile>/<目的>/  # ② 源码补丁：唯一改变 Frida 行为的地方
│   │   ├── release/               #    正式构建启用
│   │   └── debug/                 #    仅 debug 构建启用
│   └── files/frida-core/          # ③ 二进制资源 overlay：无法用文本 patch 表达的产物
└── .github/                       # ④ 构建链：GitHub Actions 唯一入口
```

| 类别 | 作用 | 适配时的性质 |
| --- | --- | --- |
| ② 源码补丁 | 改变行为（改名、加逻辑、改语义） | **每次升版都要逐条重新 apply + 语义核对** |
| ③ 资源 overlay | 提供预编译 payload/dex | **依赖 ② 的源码同步重编**，容易漂移 |
| ④ 构建链 | 固定源码、应用补丁、交叉编译、产物门禁 | 依赖官方 `configure`/`deps.py`/meson 目标名 |

构建目标与平台：

| host | 编译方式 | 补丁集合 |
| --- | --- | --- |
| `android-arm64`、`android-x86_64` | ubuntu + x-tools 容器 + NDK r29 交叉 | 公共集 + linux-family 集 |
| `linux-x86_64` | ubuntu + x-tools 容器本机构建 | 公共集 + linux-family 集 |
| `windows-x86_64` | windows-latest + MSVC | 公共集 + windows 集 |

```text
公共集 = process-name, control-port, exceptor-handler-only, gum-runtime,
         thread-name(glib/frida-gum/frida-core), [debug: logging, bisect]
linux-family 集 = agent-memfd-name, injection-group-stop, helper-injection
windows 集      = windows-identity
```

## 2. 能力清单

### 2.1 process-name：进程可见名

- **目的**：让 server 进程在 OS 层显示为非 Frida 标识（Android/Linux 看 `/proc/<pid>/comm` 与 `ps`，Windows 看线程描述）。
- **关键认知**：`g_set_prgname()` **只改 GLib 进程内静态字符串**（`gutils.c` 里的 `g_prgname`），**不改变任何 OS 可见名**。仅改它没有免探测价值，必须配合平台后端。
- **改动位置**
  - `glib` → [`patches/release/thread-name/glib.patch`](../patches/release/thread-name/glib.patch) 新增 `glib/ms-process-name.{h,c}`
  - `frida-core/server/server.vala` → [`patches/release/process-name/frida-core.patch`](../patches/release/process-name/frida-core.patch)
- **做法**
  1. 新增 `ms_process_name_set_current(const gchar *name)`：
     - Linux/Android：`prctl(PR_SET_NAME, name)`（改调用线程 comm，主线程调用即改进程名）
     - Windows：动态解析 `SetThreadDescription(GetCurrentThread(), utf16)`（Win10+；取不到则 no-op）
     - 其它平台 no-op
  2. `server.vala` 在 `main()` 的 `Environment.init()` 之后调用 `g_set_prgname("gogogo")` + `ms_process_name_set_current("gogogo")`（Vala 用 `[CCode(cname=...)] extern` 直接绑定该符号）
  3. 同 patch 顺带把 `DEFAULT_DIRECTORY`（`re.frida.server` → `re.ms.server`）和 DARWIN 下的主循环线程名（`frida-server-main-loop` → `ms-server-main-loop`）改名
- **平台**：全平台；Windows 的进程**映像名**由 exe 文件名决定，产物命名 `ms_server.exe` 已覆盖，运行期只能改线程描述。
- **适配锚点**
  - `glib/gutils.c` 的 `g_set_prgname` 实现（确认它确实只是内存赋值，不需要另找 OS 调用）
  - `glib/meson.build` 的 `glib_sub_headers` 与 `glib_sources` 两个列表（新文件必须两边都注册，否则头文件不安装/源文件不编译）
  - `frida-core/server/server.vala` 的 `main()` 首行 `Environment.init ()`
- **失败信号**：`prctl` 不生效 → 检查 glib 是否用了 `G_OS_LINUX` 宏（**GLib 只定义 `G_OS_UNIX`、`G_OS_WIN32`，没有 `G_OS_LINUX`**，必须用编译器内置的 `__linux__`）；`strings` 里没有 `gogogo` → patch 没应用或编到了别的 glib。

### 2.2 thread-name：线程名统一改造

- **目的**：把 Frida 自建线程从 `frida-*`/`Connection Listener` 之类改成统一的中性命名，且让"逻辑名"可被 gum 查询。
- **改动位置**
  - glib：`patches/release/thread-name/glib.patch` → 新增 `glib/ms-thread-name.{h,c}`，改 `gthread-posix.c`、`gthread-win32.c`、`gthread.c`、`meson.build`
  - frida-gum Linux worker：`patches/release/thread-name/frida-gum.patch` → `gum/backend-linux/gumprocess-linux.c`
  - frida-core：`patches/release/thread-name/frida-core.patch` → `src/android-helper/Makefile`、`src/android-helper/re/frida/Helper.java`、`src/linux/helpers/loader.c`
- **做法**
  1. `ms-thread-name` 模块维护一个"进程内线程名注册表"（`GHashTable<tid, {logical_name, source_name}>` + 全局自增索引）：
     - `ms_thread_name_set_current(source)`：分配索引 → 生成逻辑名 `Jit thread pool worker thread N` → 截断 15 字节写入 OS → 登记到表
     - `ms_thread_name_lookup(tid, buf, size)`：按 tid 查逻辑全名（供 gum 查询线程名使用）
     - `ms_thread_name_unregister_current()`：线程退出时清理
     - OS 写入后端：`pthread_setname_np` 的四种变体宏 → `prctl(PR_SET_NAME)`（`__linux__`）→ Windows `SetThreadDescription` → 其它 no-op
  2. `glib/gthread-posix.c` 的 `g_system_thread_set_name` 改为调用 `ms_thread_name_set_current`
  3. `glib/gthread-win32.c` 的 `g_system_thread_set_name` 同样改为调用该入口（原生实现走 `SetThreadDescription` 或 `0x406D1388` 异常命名）
  4. `glib/gthread.c` 的 `g_thread_proxy`：去掉 `if (thread->name)` 判断（始终登记）、线程结束时 `unregister`
  5. `frida-gum` 的 `gum_linux_thread_proc` 用 `__has_include(<glib/ms-thread-name.h>)` 探测注册表：有则进入时 `set_current("gum-linux-thread")`、退出时 `unregister`；`gum_linux_query_thread_name` 优先查注册表，查不到再回退 `/proc/self/task/<tid>/comm`
  6. Android helper（Java）：`Helper.java` 里把 `Connection Listener`/`Connection Handler` 换成 `createWorker(Runnable)` 工厂，线程名统一 `Jit thread pool`，逻辑名 `Jit thread pool worker thread N` 存入 `ConcurrentHashMap<tid, name>`；`Makefile` 把 `javac`/`jar`/`d8` 变量化以便自建
  7. `src/linux/helpers/loader.c`：注入器 loader 在目标进程内，不能依赖自定义 GLib 注册表，直接 `syscall(SYS_prctl, PR_SET_NAME, "Jit thread pool")`
- **平台**：glib 层全平台；`frida-gum` Linux worker 仅 linux/android；`loader.c` 仅 linux-family；Java helper 仅 android。
- **适配锚点**
  - `glib/gthread.c` 的 `g_thread_proxy`（线程名设置与清理时机）
  - `glib/gthread-posix.c` / `gthread-win32.c` 的 `g_system_thread_set_name` 符号名
  - `frida-gum/gum/backend-linux/gumprocess-linux.c` 的 `gum_linux_thread_proc`、`gum_linux_query_thread_name`
  - `frida-core/src/android-helper/re/frida/Helper.java` 的线程构造点（`new Thread("Connection Listener"...)` 一类）
- **失败信号**：线程名仍是 `frida-*` → glib patch 未生效（检查 `__has_include` 探测是否命中，头文件必须装到 `<prefix>/include/glib-2.0/glib/`）；Android 侧仍是 `Connection Listener` → **`helper.dex` 没重编**（见 §3.1，这是最常见的漂移点）。

### 2.3 agent-memfd-name：agent 内存文件名

- **目的**：Linux/Android 上 agent 通过 memfd 注入，`/proc/<pid>/maps` 里会显示 memfd 名；把 `frida-agent-*.so` 改成 `msagent.so`。
- **改动位置**：`frida-core/src/linux/linjector.vala`（[`patches/release/agent-memfd-name/frida-core.patch`](../patches/release/agent-memfd-name/frida-core.patch)）
- **做法**：在 `MemoryFileDescriptor.from_bytes` 调用处外包一个 `get_memfd_name(name)`：命中 `frida-agent-64.so` / `-32.so` / `-arm64.so` / `-arm.so` / `frida-agent.so` 时返回 `msagent.so`，否则原样返回。
- **平台**：linux-family（android + linux）。Windows 无 memfd，等价改造在 §2.9。
- **适配锚点**：`linjector.vala` 里 memfd 创建点（搜 `MemoryFileDescriptor.from_bytes`）、以及 agent 名字符串的**产生处**（官方可能在 `AgentDescriptor`/`AssetLocation` 里换名，需要重新列出所有可能取值）。
- **失败信号**：`/proc/<pid>/maps` 仍显示 `frida-agent` → 官方改名了（新增了别的 agent 名变体），需要把新名字补进 `switch`。

### 2.4 control-port：默认控制端口

- **目的**：避开 Frida 默认 `27042` 的端口指纹。
- **改动位置**：`frida-core/lib/base/socket.vala`（[`patches/release/control-port/frida-core.patch`](../patches/release/control-port/frida-core.patch)）
- **做法**：`DEFAULT_CONTROL_PORT` 由 `27042` 改为 `27056`（`DEFAULT_CLUSTER_PORT` 27052 保持）。
- **平台**：全平台（纯 Vala 常量）。
- **适配锚点**：`lib/base/socket.vala` 顶部常量区。
- **失败信号**：`ss -lntp` 仍监听 27042 → 常量被官方改名或挪到别处（搜 `DEFAULT_CONTROL_PORT`）。

### 2.5 injection-group-stop：注入期冻结目标进程

- **目的**：目标 App 在其它线程检测 `TracerPid`；注入准备阶段若目标线程继续跑，会被发现。这里让整个进程先 group-stop，再 attach/暂停线程，注入完成后再恢复。
- **改动位置**：`frida-core/src/linux/frida-helper-backend.vala`（[`patches/release/injection-group-stop/frida-core.patch`](../patches/release/injection-group-stop/frida-core.patch)）
- **做法**
  1. `LinuxHelperBackend.open()`：`Posix.kill(pid, SIGSTOP)` → 等 200ms → 置静态标志 `SeizeSession.keep_group_stopped_during_init = true` → `session.init_async()`
  2. `init` 完成后建 `ThreadSuspendScope`（排除注入线程自身）→ `scope.enable()` → 记录到 session → 清标志 → `SIGCONT`
  3. 失败路径：清标志、关 session、`SIGCONT`（保证不会把目标永久停在 group-stop）
  4. `close()` 覆写：先 `base.close()`（detach 执行线程）→ 再恢复 `ThreadSuspendScope` → 最后 `SIGCONT`。顺序关键：先 detach 再恢复其它线程，否则恢复后的线程会在短窗口看到 `TracerPid != 0`
  5. `SeizeSession.attach` 里新增 `keep_group_stopped_during_init` 分支：目标已处于 group-stop 时只建立 ptrace 关系、不等待额外 stop 事件（否则 Android 上会卡住）
  6. 附带把 `wait_for_signals({SEGV, STOP})` 扩为 `{SEGV, BUS, STOP}`，让远程调用遇到 SIGBUS 能正常返回而不是挂住
- **平台**：linux-family。**Windows 没有 SIGSTOP，未实现等价能力**（Windows 走 `CreateRemoteThread`，spawn 路径已有 `CREATE_SUSPENDED`）。
- **风险**：这段逻辑原为 Android TracerPid 检测设计，在 Linux 桌面进程上同样是"每次注入都冻整个进程 200ms+"，属于默认开启的强副作用。
- **适配锚点**：`frida-helper-backend.vala` 的 `LinuxHelperBackend.open`、`close`、`SeizeSession.attach`（搜 `PTRACE_SEIZE`）、`ThreadSuspendScope` 类是否存在。
- **失败信号**：注入后目标卡死 → `close()` 里 `SIGCONT` 路径没走到，或 `new close()` 的静态派发没生效（应改为 `virtual/override`）；Android 上 attach 超时 → `keep_group_stopped_during_init` 分支没生效。

### 2.6 helper-injection：自研注入器与 code/so 注入

这是最大的一块（新增 5 个文件 + 改 3 处 meson + 改 loader/backend），提供两个官方没有的工具：`frida-code-inject`（注入纯位置无关代码 payload）和 `frida-so-inject`（注入 .so，支持 load-only）。

- **目的**
  1. 不走 `frida-inject` 的完整 agent 流程，直接把一段或一个 ELF 塞进目标进程执行
  2. `frida-code-inject`：不用落地文件，注入内存中的代码 blob（hello / exec / 业务扫描器）
  3. `frida-so-inject`：只 `dlopen` 某个 .so 不调用入口（`--entrypoint` 省略即 load-only）
- **改动位置**（[`patches/release/helper-injection/frida-core.patch`](../patches/release/helper-injection/frida-core.patch)）
  - 新增 `inject/code-inject.vala`、`inject/so-inject.vala`
  - 新增 `src/linux/helpers/code-hello.c`、`code-exec.c`、`code-commercial-wrapper.c`
  - `inject/meson.build`：加 `frida-so-inject` / `frida-code-inject` 两个 executable + custom_target
  - `src/linux/helpers/meson.build`：加三个 code payload 的 `shared_module` + `objcopy -O binary -j .payload` 后处理
  - `src/meson.build`：`helper_backend_inputs` 条件化，`host_lowlevel_abi == 'arm64'` 时追加三个 `code-*.bin` 进内嵌资源
  - `src/linux/helpers/inject-context.h`：新增 `FridaCodeContext { const char *data; FridaLibcApi *libc; }`
  - `src/linux/frida-helper-backend-types.c`：加 `G_STATIC_ASSERT(sizeof(FridaHelperCodeContext) == sizeof(FridaCodeContext))`
  - `src/linux/frida-helper-backend.vala`：新增 `inject_code_blob()` / `inject_hello_code()` / `inject_exec_code()` / `inject_commercial_wrapper_code()`、`InjectCodeTask`、`InjectSession.inject_code()`、`CodeLayout` 计算、`HelperCodeContext` 结构
  - `src/linux/helpers/loader.c`：支持"空 entrypoint"（load-only 时 `dlsym` 跳过、`unload_policy = RESIDENT`、调用改为 `if (impl != NULL)`）
- **注入机制（伪代码）**
  ```text
  inject_code(code[], data):
      layout = 页对齐(code) + 页对齐(FridaCodeContext + FridaLibcApi + data + \0)
      bres  = bootstrap(layout.size)              # 复用官方 bootstrap：在目标里分配内存+建栈
      base  = bres.allocation_base
      write_memory(base, code)                    # 代码在页首
      maybe_fixup_helper_code(base, code)         # 重定位修正
      code_ctx = { data: base+data_off, libc: base+libc_off }
      write_memory(base+ctx_off, code_ctx)
      write_memory(base+libc_off, bres.libc)      # 把 libc 函数表交给 payload
      write_memory_string(base+data_off, data)
      regs.sp = bres.stack_root
      result = RemoteCallBuilder(base, regs).add_argument(base+ctx_off)
                                            .build(this).execute()
      if result.status != COMPLETED: 报错并带上崩溃偏移/寄存器
      finally: munmap(base, bres.allocation_size)
  ```
  payload 约束：必须用 `__attribute__((section(".text.entrypoint")))` + `visibility("default")` 导出 `frida_code_*` 入口，且**不能依赖 libc 符号解析**，所有外部函数都经 `ctx->libc`（`dlopen`/`dlsym`/`printf` 函数指针表）拿到。
- **三个内置 payload**
  | payload | 作用 | 备注 |
  | --- | --- | --- |
  | `code-hello` | 通过 `liblog.so` 的 `__android_log_print` 打一行 `hello <data> pid=<pid>` | 最小可用性验证 |
  | `code-exec` | `fork` + `setsid` + `execve("/system/bin/sh", {"sh","-c",data})`，环境只给固定 `PATH` | Android 路径写死 |
  | `code-commercial-wrapper` | 扫 `libUE4.so` 的 GNames/UWorld/ULevel/Actors，枚举 `BP_CommercialWrapper*` 类与 Actor 位置，结果打日志 | **含硬编码偏移**（`0x14e33c18`、`0x15772758`、`0x0b0` 等），绑定特定游戏版本 |
- **平台**：linux-family。Windows 未接入（官方 Windows 注入走 `LoadLibrary`，无这套 code payload 机制）。
- **适配锚点**
  - `frida-helper-backend.vala` 的 `InjectSession`、`bootstrap()`、`RemoteCallBuilder`、`compute_loader_layout`、`HelperLibcApi` 结构（`inject_code` 全部复用这些）
  - `src/meson.build` 中 `helper_backend_inputs` / `helper_backend_input_args` 的 `@INPUTn@` 编号（**加输入必须同步改编号**）
  - `src/linux/helpers/meson.build` 的 `extra_flags` / `extra_link_args` / `helper_lds` / `objcopy_flags`
  - `loader.c` 的 `frida_main` 加载流程
- **失败信号**：`make frida-code-inject` 报 target not found → meson 里 target 名变了；运行报 `Code payload crashed with signal ... at offset` → payload 与 ABI 不匹配（`FridaCodeContext`/`FridaLibcApi` 布局变了，必须同步 `types.c` 里的 `G_STATIC_ASSERT`）；arm64 上报 `NOT_SUPPORTED` → 只有 arm64 内嵌了 `code-*.bin`，其它 ABI 走 `#if ARM64` 的 else 分支。

### 2.7 gum-runtime：ART PrettyMethod 与 ELF 加载改造

- **目的**
  1. Android arm64 上 hook ART 的 `PrettyMethod`（函数头很短/很特殊）时能正常插桩——官方 16 字节 redirect 不够，需要 24 字节变体
  2. `gum_elf_module_load` 改用整文件读入堆，避开 mmap 在特定场景下的行为
- **改动位置**（[`patches/release/gum-runtime/frida-gum.patch`](../patches/release/gum-runtime/frida-gum.patch)）
  - `gum/backend-arm64/guminterceptor-arm64.c`
  - `gum/gumelfmodule.c`
- **做法**
  1. 新增 `GUM_INTERCEPTOR_PRETTY_METHOD_REDIRECT_SIZE = 24`；新增 `gum_is_art_pretty_method()`（`dladdr` 判模块名含 `libart.so` 且符号名含 `PrettyMethod`）
  2. `gum_interceptor_backend_prepare_trampoline`：命中 PrettyMethod 且能以 24 字节重定位时，`redirect_code_size = 24`
  3. `_gum_interceptor_backend_activate_trampoline` 增加 `case 24`：先写两条固定指令 `0xD2400000`（`mov x0, x0` 占位）、再接 `ldr scratch,[on_enter]; br scratch`
  4. `gumelfmodule.c`：`g_mapped_file_new` + `g_mapped_file_get_bytes` 改为 `g_file_get_contents` + `g_bytes_new_take`（整读入堆）；失败时 `g_clear_error` 后回退到进程内已有映射
- **平台**：ART 部分**仅 Android arm64**（`#ifdef HAVE_ANDROID` + `host_arch == 'arm64'` 才编译该文件）；`gumelfmodule` 的改动全平台生效。
- **注意**：该 patch 含历史噪声——空 `#ifdef HAVE_ANDROID/#endif`、空 `else { }`、`gum_is_art_pretty_method` 里的空 `if/else if` 分支、多处多余空行。**适配新版时应清理**，不影响功能但影响可读性和 apply 成功率。
- **适配锚点**：`gum/backend-arm64/guminterceptor-arm64.c` 的 `gum_interceptor_backend_prepare_trampoline`、`_gum_interceptor_backend_activate_trampoline`、`GUM_INTERCEPTOR_FULL_REDIRECT_SIZE`；`gum/gumelfmodule.c` 的 `gum_elf_module_load`。
- **失败信号**：arm64 hook ART 崩溃/跳飞 → 24 字节分支没命中或 `0xD2400000` 占位指令在新版 ART 上语义不对（那是占位 NOP 语义，需按实际需求确认）；ELF 加载内存翻倍 → 这是整读的预期代价。

### 2.8 exceptor-handler-only：可选关闭 sigaction inline hook

- **目的**：加固壳会读目标函数前 12 字节判断是否 `paciasp`（是否被 inline hook）。Frida 的 exceptor 默认会 inline hook `sigaction`/`signal`，暴露痕迹。该开关把 exceptor 降级为"只装信号处理器、不改写机器码"。
- **改动位置**：`frida-core/lib/payload/libc-shim.c`（[`patches/release/exceptor-handler-only/frida-core.patch`](../patches/release/exceptor-handler-only/frida-core.patch)）
- **做法**：在 `frida_libc_shim_init()` 里、`gum_init_embedded()` **之前**判断两种标记任一存在即 `gum_exceptor_set_mode(GUM_EXCEPTOR_MODE_HANDLER_ONLY)`：
  1. 环境变量 `MS_EXCEPTOR_HANDLER_ONLY`
  2. 文件 `/data/local/tmp/msexceptor.handler_only`
  - 为什么两者都要：`frida-so-inject` 不向目标进程传环境变量，目标进程读不到 env，只能靠文件标记
  - 为什么必须在 `gum_init_embedded()` 前：`set_mode` 内部断言 exceptor 尚未创建
  - 代价：目标 App 之后调 `sigaction/signal` 会真实生效，可能覆盖已装的处理器
  - 不覆盖：`exit/_exit/abort` 的 hook 属 `ExitMonitor`，要用 `attach(exit_monitor=False)` 关
- **平台**：整段包在 `#if defined(HAVE_ANDROID)` 内——因为用了 `access()`/`<unistd.h>`，而 `libc-shim.c` 在 `HAVE_WINDOWS` 下排除 `<unistd.h>`，不加门限会导致 Windows 编译失败。**这个门限是 Windows 能编译的前提，不要移除。**
- **适配锚点**：`libc-shim.c` 的 `frida_libc_shim_init`、`gum_exceptor_set_mode` / `GUM_EXCEPTOR_MODE_HANDLER_ONLY` 是否存在。
- **失败信号**：Windows 构建报 `access` 未声明 → `HAVE_ANDROID` 门限被破坏；开关无效 → exceptor 模式名在新版改了。

### 2.9 windows-identity：Windows 可见标识改名 + so-inject 崩溃修复

- **目的**
  1. Windows 没有 memfd，agent 以**临时 DLL 文件**注入，路径/文件名/管道名构成固定指纹，全部改成 `ms*` 前缀
  2. 修复 load-only 注入（空 entrypoint）在目标进程里 `call NULL` 崩溃
- **改动位置**（[`patches/release/windows-identity/frida-core.patch`](../patches/release/windows-identity/frida-core.patch)）
  | 文件 | 改动 |
  | --- | --- |
  | `src/windows/winjector.vala` | 临时 blob 名 `blob%u.dll` → `msagent%u.dll` |
  | `src/windows/windows-host-session.vala` | agent 资源模板 `<arch>\frida-agent.dll` → `<arch>\msagent.dll` |
  | `src/windows/frida-helper-process.vala` | 临时 helper exe `frida-helper-$name.exe` → `ms-helper-$name.exe`；线程名 `frida-helper-factory` → `ms-helper-factory` |
  | `lib/pipe/pipe-windows.c` | 命名管道前缀 `\.\pipe\frida-*` → `\.\pipe\ms-*` |
  | `src/system.vala` | 临时目录名前缀 `frida-` → `ms-` |
  | `src/windows/frida-helper-backend-glue.c` | 注入 stub 增加空 entrypoint 判空 |
- **so-inject 修复做法**：在 `frida_remote_worker_context_emit_payload` 的 x86/x86_64 分支，`GetProcAddress` 之后插入
  ```text
  test rax, rax
  je   skip_entrypoint_call
  ...原调用 entrypoint...
  jmp  entrypoint_call_done
  skip_entrypoint_call:
  mov dword [rbx + offsetof(stay_resident)], 1   ; 置常驻，避免随后 FreeLibrary
  entrypoint_call_done:
  ```
  与 Linux `loader.c` 的 `if (ctx->agent_entrypoint[0] != '\0')` 分支语义对齐。
- **平台**：仅 windows。
- **适配锚点**：上述 6 个文件里的字符串常量与 `frida_remote_worker_context_emit_payload` 的 x86 代码生成段（`GumX86Writer` 指令序列）。注意 `#ifdef HAVE_ARM64` 分支（arm64 版 stub）**没有**加这个判空，若将来支持 windows-arm64 需要补。
- **失败信号**：Windows 产物里仍出现 `frida-agent.dll`/`frida-helper-*`/`\\.\pipe\frida-` → 官方新增了别的硬编码点（全仓搜 `"frida-` 再清）；load-only 注入目标进程崩溃 → stub 判空没生效。

### 2.10 debug/logging：MYOBS 观测日志（仅 debug）

- **目的**：debug 构建时能观察 gum 初始化、interceptor trampoline、ELF 加载、JS scheduler 的关键路径。
- **改动位置**：`frida-gum` 的 `gum/gum.c`、`gum/gumelfmodule.c`、`gum/backend-arm64/guminterceptor-arm64.c`、`bindings/gumjs/gumscriptscheduler.c`（[`patches/debug/logging/frida-gum.patch`](../patches/debug/logging/frida-gum.patch)）
- **做法**：每个文件顶部定义
  ```c
  #define MY_OBS_LOG(...) g_log ("MYOBS", G_LOG_LEVEL_INFO, __VA_ARGS__)
  ```
  在关键点打日志。**统一走 `g_log`** 而不是 `__android_log_print`：GLib 的默认日志路由在 Android 走 logcat、Linux 走 stderr、Windows 走 `OutputDebugString`，一份代码三平台可观测。
- **平台**：全平台（debug profile）。
- **适配锚点**：四个文件里插入点的上下文（`gum_init_embedded`、`gum_elf_module_load`、`prepare_trampoline`/`activate_trampoline`、`gum_script_scheduler_start/stop`）。
- **失败信号**：debug 构建搜不到 `MYOBS` → patch 没进；有 `MYOBS` 但看不到日志 → 该平台的 `g_log` 路由被重定向（gum 自己装了 handler，注意 `g_log_set_default_handler`）。

### 2.11 debug/bisect：二分停止点（仅 debug）

- **目的**：注入后在指定阶段主动停下，用于排查"是哪个初始化阶段触发崩溃/检测"。
- **改动位置**
  - `frida-core`：[`patches/debug/bisect/frida-core.patch`](../patches/debug/bisect/frida-core.patch) → `lib/gadget/gadget-glue.c`、`lib/gadget/gadget.vala`
  - `glib`：[`patches/debug/bisect/glib.patch`](../patches/debug/bisect/glib.patch) → `gio/gtask.c`
- **做法**：`frida_gadget_bisect_stop_after(stage)` 检查 `/data/local/tmp/mygadget.stop.<stage>` 是否存在，存在则提前 `return`；`gadget.vala` 里同名 `stop_after()` 覆盖 `load()` 全流程各阶段，另有 `mygadget.nop` 全局短路（只验证 dlopen、不做任何初始化）。
  阶段名：`glue-gio-init`、`glue-garbage-handler`、`glue-script-backend-type`、`glue-error-quark`、`glue-worker-context`、`glue-worker-loop`、`glue-worker-thread`、`glue-worker-entry`、`glue-worker-push-context`、`glue-worker-loop-return`、`environment-init`、`detect-location`、`load-config`、`process-policy`、`cloak-range`、`interceptor-obtain`、`interceptor-begin`、`exceptor-obtain`、`controller-create`、`interceptor-end`、`resume`、`start`、`start-before-idle-source`、`start-idle-callback`、`start-before-attach`、`perform-start-suspend`、`perform-start-enter`、`perform-start-ignore-scope`、`perform-start-before-controller-start`、`perform-start-after-controller-start`、`gtask-after-*` 系列。
- **平台**：全平台可编译，但**路径是 Android 专用的 `/data/local/tmp`**，Linux/Windows 上默认永不触发。
- **适配锚点**：`gadget-glue.c` 的 `frida_gadget_environment_init` / `run_worker_loop`；`gadget.vala` 的 `load()` 与 `start()`/`perform_start()`；`gtask.c` 的 `g_task_new`。
- **失败信号**：release 产物里出现 `mygadget.stop.` → debug patch 漏进了 release（`verify-artifacts` 会拦）。

## 3. 资源 overlay

`ms_from_frida/files/frida-core/` 在 `prepare-source.sh` 里对 **android** 目标 `cp -a` 覆盖到 `subprojects/frida-core/`。

### 3.1 `src/android-helper/helper.dex`

- **是什么**：`Helper.java` 打上线程名改造后**编译出来的 dex**（官方同路径也有一个 dex，但内容是改造前的）。
- **为什么要 overlay**：dex 是二进制，无法用文本 patch 表达；构建期不重编 Java（官方 CI 用预置 dex）。
- **一致性约束**：**`helper.dex` 必须与 `patches/release/thread-name/frida-core.patch` 里的 `Helper.java` 改动同步重编。** 当前 dex 里确实含 `Jit thread pool` 与 `LOGICAL_THREAD_NAMES`（已验证），即两者配套。
- **重编方法**：改 `Helper.java` 后在 `subprojects/frida-core/src/android-helper/` 执行 `make helper.dex`（`Makefile` 已变量化 `JAVAC`/`JAR`/`D8`，需 android.jar + d8 在 PATH），再把产物拷回 overlay。
- **漂移信号**：Android 上 helper 线程名仍是 `Connection Listener` → dex 是旧的。

### 3.2 `src/linux/helpers/artifacts/native/arm64/*.bin|elf`

| 文件 | 来源 | 说明 |
| --- | --- | --- |
| `bootstrapper.bin` | 官方源码重编 | 官方也有同名文件；overlay 是重编版 |
| `loader.bin` | 官方源码重编 | **含 `loader.c` 的 `PR_SET_NAME` 改造**，必须重编才能生效 |
| `zymbiote.elf` | 官方源码重编 | 官方也有同名文件 |
| `code-hello.bin` | **本项目自研** | 由 `code-hello.c` 编出，官方无 |
| `code-exec.bin` | **本项目自研** | 同上 |
| `code-commercial-wrapper.bin` | **本项目自研** | 同上 |

- **为什么 overlay**：这些是 `src/linux/helpers/` 独立 meson 工程的产物（`shared_module` + `objcopy -O binary -j .payload`），主构建只**消费** `.bin`，不生成。
- **一致性约束**：**改 `loader.c` / `code-*.c` 后必须重编对应 `.bin` 并更新 overlay**，否则主构建用的还是旧 payload（源码改动"看起来编进去了"但实际不生效）。
- **已知缺口**：只有 `arm64` 目录有重编产物，`x86_64`/`x86` 用官方原始 blob → Linux x86_64 上 load-only so-inject、loader 线程名会退化到官方行为。
- **重编方法**：`subprojects/frida-core/src/linux/helpers/` 下 `./rebuild.sh` 或独立 meson 构建（`meson setup build && ninja -C build`），取 `artifacts/native/<abi>/` 产物。

## 4. 构建链

唯一入口：`.github/workflows/ms-from-frida.yml`（手动 `workflow_dispatch`，输入 `release_tag`/`build_type`/`publish_release`）。

### 4.1 `.github/scripts/ms-from-frida/prepare-source.sh`

按 `--host` 做四件事，全部失败即中止：

```text
prepare(host, build_type):
    1. clone frida 根仓库 @ FRIDA_ROOT_COMMIT，submodule init
       clone frida-core / frida-gum / glib / libffi / libiconv / termux-elf-cleaner @ 各自锁定 commit
       link_dep: 把 frida-core、frida-gum 的 subprojects/{glib,libffi,...} 软链到根 subprojects/
    2. deps.py sync 下载预编译 bundle
       android → sdk-<host> + toolchain-linux-x86_64
       linux   → sdk-<host> + toolchain-linux-x86_64
       windows → sdk-windows-x86_64-mt + toolchain-windows-x86_64(实际映射到 windows-x86)
    3. 按 host 应用补丁（顺序见 §1），每个 patch 先 --check 再 apply
    4. android 时 cp -a files/frida-core/. 覆盖到 subprojects/frida-core/
```

- `--arch` 是旧参数兼容，等价 `--host android-<arch>`。
- 环境变量 `PYTHON` 可覆盖 python 命令名（Windows runner 上是 `python` 而非 `python3`）。

### 4.2 `.github/scripts/ms-from-frida/build-target.sh`（android/linux）

```text
build(host, build_type):
    android → 校验 ANDROID_NDK_ROOT 的 Pkg.Revision 是 29.x
    临时克隆 glib @ GLIB_COMMIT → apply thread-name/glib.patch [+ debug bisect/glib.patch]
    FRIDA_DEPS=<tmp> deps.py build --bundle=sdk --build=linux-x86_64 --host=<host> --only=glib
    tar 解压自建 glib SDK 覆盖到 deps/sdk-<host>/
    ./configure --host=<host> --enable-server --enable-gadget --enable-inject
                --disable-frida-tools --disable-frida-python
                -- -Dlibdir=lib [-Dfrida-core:compat=disabled]   # linux 关闭 compat
    make frida-server frida-gadget frida-code-inject frida-so-inject
    拷到 out/<build_type>/<host>/{ms_server,gadget.so,frida-code-inject,frida-so-inject}
```

- **native 构建（linux）必须显式 `--enable-*`**：根 meson 的 auto 规则在 build==host 时会把 server/gadget/inject 关掉。
- linux 关 `compat`：compat 是 32 位 legacy helper/agent，需要额外的 `sdk-linux-x86` 与 32 位工具链。

### 4.3 `.github/scripts/ms-from-frida/build-windows.ps1`

```text
build_windows(build_type):
    pip install setuptools                      # glib 的 gdbus-codegen 仍 import distutils
    临时克隆 glib → apply glib patch → deps.py build --host=windows-x86_64 --only=glib
    tar 覆盖到 deps/sdk-windows-x86_64-mt/
    清除 FRIDA_DEPS                            # 否则主 configure 会去临时目录找 SDK（缺 ngtcp2）
    configure.bat --host=windows-x86_64 --enable-server --enable-gadget --enable-inject
                  --disable-frida-tools --disable-frida-python
                  -- -Dlibdir=lib -Dfrida-core:compat=disabled
                     -Dfrida-core:compiler_backend=disabled
                     -Dfrida-core:barebone_backend=disabled
    make.bat                                   # 全量构建（custom_target 名与 make 目标名不一致）
    拷到 out/<build_type>/windows-x86_64/{ms_server.exe,gadget.dll,frida-inject.exe}
```

- **Windows 产物只有三件套**：`frida-code-inject`/`frida-so-inject` 依赖 linux-family 的 helper-injection，Windows 上不存在，改由官方 `frida-inject.exe` 承担注入。
- 关 `barebone_backend`/`compiler_backend`：前者要 node + quickjs/lzfse，后者要 Go ≥1.24，本项目都不需要。

### 4.4 产物门禁

`verify-artifacts.sh`（android/linux）+ `verify-artifacts.ps1`（windows）检查同一套语义：

| 检查 | release 要求 | debug 要求 |
| --- | --- | --- |
| 产物存在且非空 | ✓ | ✓ |
| 文件类型 | ELF：`readelf -h` 通过；PE：`MZ` 头 | 同 |
| `gogogo` | 必须存在 | 必须存在 |
| `msagent` | 必须存在 | 必须存在 |
| `Jit thread pool worker thread` | 必须存在 | 必须存在 |
| `MYOBS` | **不得存在** | 必须存在 |
| `mygadget.stop.` / `mygadget.nop` | **不得存在** | 必须存在 |
| `Connection (Listener\|Handler)` | 不得存在（旧线程名残留） | 同 |

### 4.5 发布

`release` job 在 `build_type=release` 且 `publish_release=true` 时跑：下载全部 artifact → 按 `<文件名>.<host>` 重命名 → `softprops/action-gh-release` 上传。

## 5. 跨版本适配流程

```text
开始
 │
 ├─ 1. 更新 versions.env：FRIDA_TAG / 四个 COMMIT（root/core/gum/glib）
 │       └─ 记录新旧版本，便于回溯
 │
 ├─ 2. 逐条 patch 做 apply --check（在干净 clone 上，按 §1 顺序）
 │       ├─ 全部通过 → 跳到 4
 │       └─ 失败 → 3
 │
 ├─ 3. 修 patch 上下文
 │       ├─ 语义未变、只是行号/上下文漂移 → 重生成 patch
 │       └─ 官方代码结构变了 → 读新代码找到等价锚点（见 §2 各条"适配锚点"），改 patch
 │
 ├─ 4. 资源 overlay 同步
 │       ├─ loader.c 或 code-*.c 改过 → 重编 artifacts/native/arm64/*.bin
 │       └─ Helper.java 改过 → 重编 helper.dex
 │
 ├─ 5. 触发 CI（publish_release=false），只看能否编过
 │       └─ 失败按 §6 排查
 │
 ├─ 6. 产物门禁核对（§4.4 表）；debug 与 release 各跑一次
 │
 ├─ 7. 运行时验证
 │       ├─ Linux：起 ms_server → /proc/<pid>/comm == gogogo、线程名 Jit thread pool、
 │       │         监听 27056、memfd 名 msagent.so（注入后看 /proc/<pid>/maps）
 │       ├─ Windows：ms_server.exe 起来、strings 无 frida-agent 残留、load-only 注入不崩
 │       └─ Android：真机 attach + 检查 /proc/<pid>/maps 的 memfd 名、helper 线程名
 │
 └─ 8. 提交。文档同步：本文档 §1 表、§2 各条的锚点/失败信号如已变化必须更新
```

### 5.1 每项改动的"还需不需要"判断法

升到新版后，**不要默认所有改动仍然必要**。逐个确认：

| 能力 | 什么情况下可以删掉 |
| --- | --- |
| process-name / thread-name / agent-memfd-name / control-port / windows-identity | 官方已改名或已提供配置项时 |
| exceptor-handler-only | 官方 exceptor 支持"不 hook sigaction"的配置时 |
| injection-group-stop | 官方注入流程已自带冻结策略时 |
| helper-injection | 官方提供等价 code/so 注入工具时 |
| gum-runtime（PrettyMethod 24 字节） | 官方 arm64 redirect 已能处理短函数头时 |
| gum-runtime（ELF 整读） | 官方明确不再需要规避 mmap 行为时 |
| debug/logging、debug/bisect | 一直保留（仅 debug） |

### 5.2 常见适配动作的判定顺序

1. **先确认是不是纯上下文漂移**：`git apply --check` 的报错行号 vs 官方文件实际内容；语义一致就只重生成 patch。
2. **再确认符号是否还在**：patch 里引用的函数/结构/常量（如 `gum_exceptor_set_mode`、`HelperLibcApi`、`ThreadSuspendScope`）在新版是否改名或移除。
3. **最后确认语义是否变了**：例如官方把 `g_thread_proxy` 里 NULL 判断加回来、或 `g_system_thread_set_name` 改成宏——这时不是改上下文，而是要在新结构里找等价插入点。

## 6. 已知技术债与陷阱

按"踩到会浪费最多时间"排序：

1. **`G_OS_LINUX` 不存在**。GLib 只定义 `G_OS_UNIX`/`G_OS_WIN32`（见 `glib/meson.build` 的 `glib_os` 生成逻辑）。任何"只在 Linux 生效"的分支必须用 `__linux__`，用 `G_OS_LINUX` 会静默不生效（编译通过、行为为空）。本项目踩过这个坑。

2. **`g_set_prgname` 不是免探测手段**。它只改 GLib 进程内静态字符串，与 OS 可见名无关。必须是"GLib 内部状态 + 平台后端（prctl / SetThreadDescription）"两件事都做。

3. **资源 overlay 与源码 patch 的静默漂移**。主构建消费的是 `artifacts/native/<abi>/*.bin` 和 `helper.dex`，改源码不重编这些产物，行为完全不变——且**构建不会报错**。改 `loader.c`/`code-*.c`/`Helper.java` 后必须按 §3 重编。

4. **`src/meson.build` 的 `@INPUTn@` 编号要手改**。给 `helper_backend_inputs` 加输入时，`helper_backend_input_args` 的编号必须从 1 连续排到 N，漏改会错位传参（编过、跑挂）。

5. **`gum-runtime` patch 里的历史噪声**：空 `#ifdef`/空 `else`/空 `if/else if` 分支、多余空行。不影响功能，但会持续增大 apply 失败概率，清理时要确认没有真正的逻辑被删。

6. **`code-commercial-wrapper.c` 是目标特化的**。硬编码 `0x14e33c18`（GNames）、`0x15772758`（UWorld）、`libUE4.so`、`BP_CommercialWrapper_LV4_C` 等，只对特定游戏版本有效。换成别的目标必须重算偏移，不能当通用组件。

7. **`injection-group-stop` 在 Linux 上是默认强副作用**。每次注入都 `SIGSTOP` 整进程 200ms+、`close()` 时再 `SIGCONT`。原本为 Android TracerPid 检测设计，在桌面/服务进程上可能导致挂起，`new close()` 的静态派发若失效还会漏发 `SIGCONT`（目标残留 group-stop）。考虑改为仅 Android 生效或加开关。

8. **Windows 进程名只能做到"文件名级"**。`EPROCESS.ImageFileName` 由 exe 文件名决定，用户态改不了；`SetThreadDescription` 只影响线程描述。不要承诺"运行期完全伪装"，PEB 改写也只覆盖自查询面。

9. **`compare` 陷阱：Windows 的 `make` 目标名**。`make frida-code-inject` 在 Windows 上会报 target not found（custom_target 名不同），只能 `make.bat` 全量后按路径取产物。

10. **`FRIDA_DEPS` 的环境污染**。`deps.py` 用它决定依赖缓存目录；自建 glib 时设了它，之后**必须清除**再跑主 `configure`，否则主 configure 会去临时目录找 SDK，报缺 `libngtcp2` 之类。

11. **Debug bisect 路径是 Android 专用的**。`/data/local/tmp/mygadget.stop.*` 在 Linux/Windows 上永不触发；若要让 debug 三平台可观测，需改成 `g_get_tmp_dir()` 或平台命名事件。

12. **Windows 未实现的能力**：code/so 注入（依赖 linux-family helper）、注入期 suspend-all、PEB 身份改写、`frida-agent-arm64` 之外的 arm64 stub 判空。若将来支持 windows-arm64，需补 `#ifdef HAVE_ARM64` 分支。

## 7. 快速索引

| 想改什么 | 看哪里 |
| --- | --- |
| 进程/线程/agent 名字 | §2.1、§2.2、§2.3、§2.9 |
| 端口与网络指纹 | §2.4 |
| 注入时序与反调试 | §2.5、§2.8 |
| 自研注入工具与 payload | §2.6、§3.2 |
| hook 引擎行为 | §2.7 |
| 构建失败 | §4、§6 |
| 升版适配 | §5 |
