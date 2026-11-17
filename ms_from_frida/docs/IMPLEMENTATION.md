# Frida 免探测改造说明与跨版本适配指南

> 本文描述一组**施加在 Frida 上游源码上的改动**：每项改动解决什么问题、改哪个文件、用什么手法实现，以及 Frida 升级到新版本时如何逐项核对与重新实现。
>
> 本文只依赖 **Frida 上游源码**。不依赖任何特定的改造仓库、补丁文件或构建脚本——拿到上游源码即可照此实现或核对。

## 0. 命名约定与使用方式

下文路径均相对 Frida 上游源码树，各仓库相互独立：

| 前缀 | 含义 |
| --- | --- |
| `frida/` | 根仓库（meson 根工程，`frida.git`） |
| `frida-core/` | 子模块（`frida-core.git`） |
| `frida-gum/` | 子模块（`frida-gum.git`） |
| `glib/` | frida 的 GLib fork（`frida/glib.git`，构建期单独 clone） |

- **只想知道"改了什么"** → 读 C1–C11（§1）。
- **要升级 Frida 版本** → 读 §4 流程，按 C1–C11 各自的"适配锚点/失败信号"逐项核对。
- **构建失败** → 读 §3 构建约束 + §5 技术债。

本文写作时的验证基线是 Frida **17.15.3**（根 commit `831acfff`、frida-core `e0ec2bee`、frida-gum `e5b0d7d6`、glib `92d65736`）。适配其它版本时基线仅作定位参考，以目标版本源码为准。

## 1. 能力清单

每项给出：**目的** / **改动位置** / **手法** / **平台** / **适配锚点** / **失败信号**。

```text
平台适用性总览：

                 android  linux  windows
C1 进程可见名      ✓        ✓      ✓(仅线程描述)
C2 线程名          ✓        ✓      ✓
C3 agent 内存名    ✓        ✓      ✗(无 memfd，见 C9)
C4 控制端口        ✓        ✓      ✓
C5 注入期冻结      ✓        ✓      ✗
C6 自研注入器      ✓        ✓      ✗
C7 Gum 运行时      ✓(arm64) ✓ELF   ✓ELF
C8 exceptor 降级   ✓        ✗      ✗
C9 Windows 标识    —        —      ✓
C10 观测日志       ✓        ✓      ✓(仅 debug)
C11 二分停止点     ✓        ✓      ✓(仅 debug，路径需改)
```

---

### C1 进程可见名

- **目的**：让进程在 OS 层显示为非 Frida 标识（Linux/Android 看 `/proc/<pid>/comm` 与 `ps`；Windows 看线程描述）。
- **关键认知**：`g_set_prgname()` **只写 GLib 进程内静态字符串**（`glib/glib/gutils.c` 里的 `g_prgname`），**与任何 OS 可见名无关**。只改它没有免探测价值。
- **改动位置**
  - `glib/glib/ms-process-name.{h,c}`（新增）
  - `glib/glib/meson.build`（注册新文件）
  - `frida-core/server/server.vala`（调用点）
- **手法**
  1. 新增 `void ms_process_name_set_current (const gchar *name)`：
     - Linux/Android：`prctl(PR_SET_NAME, name, 0, 0, 0)`——改调用线程的 comm，主线程调用即改进程名
     - Windows：`GetModuleHandleW("kernel32.dll")` + `GetProcAddress("SetThreadDescription")`，有则 `SetThreadDescription(GetCurrentThread(), utf16(name))`，没有则 no-op（Win7/8）
     - 其它平台：no-op
     - 同名去重、失败静默，不得抛错
  2. `glib/glib/meson.build` 两处注册：`glib_sub_headers`（头文件要安装到 `<prefix>/include/glib-2.0/glib/`）与 `glib_sources`（源文件要参与编译）。**两处都改，漏一处表现为"编过但符号缺失/头文件找不到"**。
  3. `frida-core/server/server.vala` 的 `main()` 在 `Environment.init ()` 之后：
     ```vala
     [CCode (cname = "g_set_prgname")]
     extern static void g_set_prgname (string prgname);
     [CCode (cname = "ms_process_name_set_current")]
     extern static void ms_process_name_set_current (string name);
     ...
     g_set_prgname ("gogogo");                  // 进程内 GLib 状态
     ms_process_name_set_current ("gogogo");     // OS 可见名
     ```
  4. 同一处顺带把 `DEFAULT_DIRECTORY` 由 `re.frida.server` 改为中性名（如 `re.ms.server`），以及 DARWIN 分支的 `frida-server-main-loop` 线程名。
- **平台**：全平台。Windows 的进程**映像名**由 exe 文件名决定，运行期只能改线程描述 → 需要在产物命名上解决（把 server 产物命名为 `ms_server.exe`）。
- **适配锚点**
  - `glib/glib/gutils.c` 的 `g_set_prgname`（确认仍是纯内存赋值）
  - `glib/glib/meson.build` 的 `glib_sub_headers` / `glib_sources` 列表
  - `frida-core/server/server.vala` 的 `main()` 首行 `Environment.init ()`
- **失败信号**
  - `prctl` 不生效 → 平台判定宏用错：**GLib 只定义 `G_OS_UNIX` 与 `G_OS_WIN32`，不存在 `G_OS_LINUX`**（见 `glib/meson.build` 里 `glib_os` 的生成逻辑）。Linux 专用分支必须用编译器内置 `__linux__`。
  - `strings` 里找不到 `gogogo` → 调用点没编进 server，或改到了另一个 glib 副本。

---

### C2 线程名统一

- **目的**：把 Frida 自建线程从 `frida-*` / `Connection Listener` 等特征名改为统一中性命名，并让"逻辑全名"可被 gum 查询（OS 层线程名有 15 字节上限）。
- **改动位置**
  - `glib/glib/ms-thread-name.{h,c}`（新增）、`glib/glib/gthread-posix.c`、`glib/glib/gthread-win32.c`、`glib/glib/gthread.c`、`glib/glib/meson.build`
  - `frida-gum/gum/backend-linux/gumprocess-linux.c`
  - `frida-core/src/android-helper/re/frida/Helper.java`、`frida-core/src/android-helper/Makefile`
  - `frida-core/src/linux/helpers/loader.c`
- **手法**
  1. `ms-thread-name` 模块维护进程内注册表 `GHashTable<tid, {logical_name[64], source_name[64]}>` + 全局自增索引：
     - `ms_thread_name_set_current(source)`：取索引 N → 逻辑名 `Jit thread pool worker thread N` → 截断 15 字节写 OS → 登记
     - `ms_thread_name_set_current_for_index(index, source)`：指定索引版本（供需要稳定编号的调用方）
     - `ms_thread_name_lookup(tid, buf, size)` → `gboolean`：按 tid 取逻辑全名
     - `ms_thread_name_unregister_current()`：线程退出清理
     - OS 写入优先级：`HAVE_PTHREAD_SETNAME_NP_*` 四种变体宏 → `__linux__` 的 `prctl(PR_SET_NAME)` → `G_OS_WIN32` 的 `SetThreadDescription` → no-op
     - tid 取值：Linux `syscall(SYS_gettid)`、Windows `GetCurrentThreadId()`、其它 `(guintptr)pthread_self()`
  2. `glib/glib/gthread-posix.c` 的 `g_system_thread_set_name` 整体替换为 `ms_thread_name_set_current(name)`
  3. `glib/glib/gthread-win32.c` 的 `g_system_thread_set_name` 同样替换为 `ms_thread_name_set_current(name)`（原生实现本就优先 `SetThreadDescription`）
  4. `glib/glib/gthread.c` 的 `g_thread_proxy`：去掉 `if (thread->name)` 守卫，始终调用 `g_system_thread_set_name(thread->name)`；线程结束处加 `ms_thread_name_unregister_current()`。**注意 `thread->name` 可能为 NULL，`ms_thread_name_set_current` 必须对 NULL 安全。**
  5. `frida-gum/gum/backend-linux/gumprocess-linux.c`
     - 顶部用 `#ifdef __has_include / #if __has_include(<glib/ms-thread-name.h>)` 探测注册表可用性（GLib 是可选依赖）
     - `gum_linux_thread_proc`：进入时 `ms_thread_name_set_current("gum-linux-thread")`，退出前 `unregister`
     - `gum_linux_query_thread_name`：先查注册表，命中返回逻辑全名；未命中回退 `/proc/self/task/<tid>/comm`
  6. `frida-core/src/android-helper/re/frida/Helper.java`（Java helper，Android 专用）
     - 引入 `OS_THREAD_NAME = "Jit thread pool"`、`AtomicInteger NEXT_WORKER_INDEX`、`ConcurrentHashMap<Integer,String> LOGICAL_THREAD_NAMES`
     - 新增 `createWorker(Runnable)` 工厂：线程名固定 `OS_THREAD_NAME`，`run()` 里用 `Process.myTid()` 登记 `Jit thread pool worker thread N`，`finally` 移除
     - 把 `new Thread("Connection Listener")` / `new Thread("Connection Handler")` 两处替换为 `createWorker(...)`
     - `Makefile` 把 `javac`/`jar`/`d8` 变量化（`JAVAC ?=` 等），便于脱离 Android SDK 默认路径自建
  7. `frida-core/src/linux/helpers/loader.c`：注入器 loader 运行在目标进程内，无法依赖自定义 GLib 注册表，直接 `syscall(SYS_prctl, PR_SET_NAME, "Jit thread pool")`
- **平台**：GLib 层全平台；`frida-gum` Linux worker 仅 linux/android；`loader.c` 仅 linux-family；Java helper 仅 android。
- **适配锚点**
  - `glib/glib/gthread.c` 的 `g_thread_proxy`（设置与清理时机）
  - `glib/glib/gthread-posix.c` / `gthread-win32.c` 的 `g_system_thread_set_name`
  - `frida-gum/gum/backend-linux/gumprocess-linux.c` 的 `gum_linux_thread_proc`、`gum_linux_query_thread_name`
  - `frida-core/src/android-helper/re/frida/Helper.java` 的 `new Thread(...)` 构造点
- **失败信号**
  - 线程名仍为 `frida-*` → glib 补丁未生效（检查 `__has_include` 探测是否命中，头文件必须装到 include 路径）
  - Android 上仍是 `Connection Listener` → **`helper.dex` 没重编**（见 §2.1，最常见的漂移点）
  - 出现空线程名 → `thread->name == NULL` 未被安全处理

---

### C3 agent 内存文件名

- **目的**：Linux/Android 的 agent 经 memfd 注入，`/proc/<pid>/maps` 会暴露 memfd 名；把 `frida-agent-*.so` 改为中性名。
- **改动位置**：`frida-core/src/linux/linjector.vala`
- **手法**：在 memfd 创建处外包一层命名映射：
  ```vala
  FileDescriptor fd = MemoryFileDescriptor.from_bytes (get_memfd_name (name), blob);
  ...
  private static string get_memfd_name (string name) {
      switch (name) {
          case "frida-agent-64.so":  case "frida-agent-32.so":
          case "frida-agent-arm64.so": case "frida-agent-arm.so":
          case "frida-agent.so":     return "msagent.so";
          default:                   return name;
      }
  }
  ```
- **平台**：linux-family。Windows 无 memfd，等价改造见 C9。
- **适配锚点**：`linjector.vala` 里 `MemoryFileDescriptor.from_bytes` 的调用点；agent 名的**产生处**（可能在 `AgentDescriptor` / `AssetLocation` / `agent.vala`）——升级后要把所有可能取值补进 `switch`。
- **失败信号**：`/proc/<pid>/maps` 仍显示 `frida-agent` → 官方新增了别的 agent 名变体，或改名逻辑被移到了 memfd 创建之前。

---

### C4 默认控制端口

- **目的**：避开默认端口指纹。
- **改动位置**：`frida-core/lib/base/socket.vala`
- **手法**：`DEFAULT_CONTROL_PORT` 常量 `27042` → 其它值（本文用 `27056`）。`DEFAULT_CLUSTER_PORT` 不动。
- **平台**：全平台（纯 Vala 常量）。
- **适配锚点**：`lib/base/socket.vala` 顶部常量区。
- **失败信号**：`ss -lntp` 仍监听旧端口 → 常量改名或被移到别处（全仓搜 `DEFAULT_CONTROL_PORT`）。

---

### C5 注入期冻结目标进程

- **目的**：目标 App 在其它线程检测 `TracerPid`；注入准备阶段若目标其它线程继续跑会被发现。让整个进程先 group-stop，再 attach/暂停线程，注入完成再恢复。
- **改动位置**：`frida-core/src/linux/frida-helper-backend.vala`
- **手法**
  1. `LinuxHelperBackend.open()`：
     ```text
     kill(pid, SIGSTOP); delay(200ms);
     SeizeSession.keep_group_stopped_during_init = true;
     yield session.init_async(...);
     scope = new ThreadSuspendScope(pid); scope.exclude(session.tid);
     yield scope.enable();
     session.group_stop_scope = scope; session.group_stop_enabled = true;
     SeizeSession.keep_group_stopped_during_init = false;
     kill(pid, SIGCONT);
     // 异常路径：清标志 → close session → SIGCONT（绝不能让目标永久停在 group-stop）
     ```
  2. 覆写 `close()`：先 `base.close()`（detach 执行线程）→ 再 `scope.disable()` → 最后 `SIGCONT`。**顺序关键**：若先恢复其它线程再 detach，目标线程会在窗口内看到 `TracerPid != 0`。
  3. `SeizeSession.attach` 增加静态标志 `keep_group_stopped_during_init`：目标已处于 group-stop 时只建立 ptrace 关系、**不等待额外 stop 事件**（否则 Android 上会卡住）
  4. 顺带把远程调用的等待信号集从 `{SEGV, STOP}` 扩为 `{SEGV, BUS, STOP}`，让 SIGBUS 能正常返回而不是挂住
- **平台**：linux-family。Windows 无 SIGSTOP 等价物，未实现（spawn 路径上游已有 `CREATE_SUSPENDED`）。
- **风险**：原为 Android TracerPid 检测设计；在 Linux 桌面/服务进程上等于"每次注入都冻结整进程 200ms+"，属默认开启的强副作用。若目标不是 Android 反调试场景，建议改为仅 Android 生效或加开关。
- **适配锚点**：`LinuxHelperBackend.open` / `close`、`SeizeSession.attach`（搜 `PTRACE_SEIZE`）、`ThreadSuspendScope` 类是否仍存在。
- **失败信号**
  - 注入后目标卡死 → `close()` 的 `SIGCONT` 路径没走到；若用 `new close()` 静态派发，注意它在父类引用下是否真的调用到（必要时改 `virtual/override`）
  - Android attach 超时 → `keep_group_stopped_during_init` 分支未生效

---

### C6 自研注入器与 code/so 注入

提供两个上游没有的工具：`frida-code-inject`（注入纯位置无关代码 blob）与 `frida-so-inject`（注入 .so，支持 load-only）。

- **目的**
  1. 不跑完整 agent 流程，直接把一段代码或一个 ELF 塞进目标执行
  2. code 注入不落地文件（对比 Windows 的 `LoadLibrary` 必须落地 DLL）
  3. so 注入支持"只 `dlopen` 不调入口"（`--entrypoint` 省略）
- **改动位置**
  - `frida-core/inject/code-inject.vala`、`frida-core/inject/so-inject.vala`（新增）
  - `frida-core/inject/meson.build`（加两个 executable + custom_target）
  - `frida-core/src/linux/helpers/code-hello.c`、`code-exec.c`、`code-commercial-wrapper.c`（新增）
  - `frida-core/src/linux/helpers/meson.build`（三个 payload 的 `shared_module` + `objcopy -O binary -j .payload`）
  - `frida-core/src/linux/helpers/inject-context.h`（新增 `FridaCodeContext`）
  - `frida-core/src/linux/helpers/loader.c`（支持空 entrypoint）
  - `frida-core/src/linux/frida-helper-backend.vala`（`inject_code` 与 `InjectCodeTask`）
  - `frida-core/src/linux/frida-helper-backend-types.c`（`G_STATIC_ASSERT` 对齐结构体大小）
  - `frida-core/src/meson.build`（arm64 时把三个 `code-*.bin` 加进内嵌资源）
- **注入机制**
  ```text
  inject_code(code[], data):
      code_size = round_to_page(len(code))
      data_size = round_to_page(sizeof(FridaCodeContext) + sizeof(FridaLibcApi) + len(data)+1)
      base = bootstrap(code_size + data_size)      // 复用上游 bootstrap：目标内分配内存+建栈
      write_memory(base, code)
      maybe_fixup_helper_code(base, code)          // 重定位修正
      code_ctx = { data: base+data_off, libc: base+libc_off }
      write_memory(base+ctx_off, code_ctx)
      write_memory(base+libc_off, bres.libc)        // 把 libc 函数表交给 payload
      write_memory_string(base+data_off, data)
      regs.sp = bres.stack_root
      result = RemoteCallBuilder(base, regs).add_argument(base + ctx_off)
                                             .build(this).execute()
      if result.status != COMPLETED:
          报错并带上崩溃偏移(相对 base)与寄存器快照
      finally: munmap(base, bres.allocation_size)
  ```
  payload 契约：
  - 入口必须 `__attribute__((section(".text.entrypoint")))` + `visibility("default")`，形如 `void frida_code_x (FridaCodeContext * ctx)`
  - **不得直接调用任何 libc 符号**，全部经 `ctx->libc`（`dlopen`/`dlsym`/`printf`… 的函数指针表）
  - 数据只能从 `ctx->data` 取
  - 结构体布局必须与 core 侧一致，用 `G_STATIC_ASSERT(sizeof(...) == sizeof(...))` 在编译期锁住
- **三个内置 payload**
  | payload | 作用 | 备注 |
  | --- | --- | --- |
  | `code-hello` | 经 `liblog.so` 的 `__android_log_print` 打 `hello <data> pid=<pid>` | 最小可用性验证 |
  | `code-exec` | `fork` + `setsid` + `execve("/system/bin/sh", {"sh","-c",data})`，只给固定 `PATH` | Android 路径与 PATH 写死 |
  | `code-commercial-wrapper` | 扫 `libUE4.so` 的 GNames/UWorld/ULevel/Actors，枚举目标类与位置后打日志 | **含硬编码偏移**，见 §5.6 |
- **so 注入的 load-only 语义（跨平台一致约束）**：`--entrypoint` 缺省时 entrypoint 为空串，目标侧必须做到
  - Linux/Android（`loader.c`）：`if (ctx->agent_entrypoint[0] != '\0')` 才 `dlsym`；为空时 `unload_policy = FRIDA_UNLOAD_POLICY_RESIDENT`；调用处 `if (impl != NULL)`
  - Windows（C9）：注入 stub 里判空跳转并置 `stay_resident`
- **平台**：linux-family。Windows 未接入（依赖 Linux helper 后端）。
- **适配锚点**
  - `frida-helper-backend.vala` 的 `InjectSession`、`bootstrap()`、`RemoteCallBuilder`、`compute_loader_layout`、`HelperLibcApi`——`inject_code` 全部复用这些
  - `frida-core/src/meson.build` 中 `helper_backend_inputs` / `helper_backend_input_args` 的 `@INPUTn@` 编号（**加输入必须连续重排编号**）
  - `src/linux/helpers/meson.build` 的 `extra_flags` / `extra_link_args` / `helper_lds` / `objcopy_flags`
  - `loader.c` 的 `frida_main` 加载流程
- **失败信号**
  - 报 target not found → meson target 名变了（`custom_target` 的输出名与 make 目标名不一定一致）
  - `Code payload crashed with signal ... at offset` → payload 与 core 的 ABI 不匹配，优先核对 `G_STATIC_ASSERT` 那几个结构体
  - 非 arm64 上报 `NOT_SUPPORTED` → 内嵌 `code-*.bin` 只在 arm64 注册，其它 ABI 走 `#if ARM64` 的 else 分支

---

### C7 Gum 运行时改造

- **目的**
  1. Android arm64 上 hook ART 的 `PrettyMethod`（函数头特殊/很短）时能正常插桩——上游 16 字节 redirect 不够，需要 24 字节变体
  2. `gum_elf_module_load` 改为整文件读入堆，规避 mmap 在特定场景下的行为
- **改动位置**：`frida-gum/gum/backend-arm64/guminterceptor-arm64.c`、`frida-gum/gum/gumelfmodule.c`
- **手法**
  1. 新增 `GUM_INTERCEPTOR_PRETTY_METHOD_REDIRECT_SIZE = 24` 与 `gum_is_art_pretty_method()`（`dladdr` 判模块名含 `libart.so` 且符号名含 `PrettyMethod`）
  2. `gum_interceptor_backend_prepare_trampoline`：命中且能以 24 字节重定位时 `data->redirect_code_size = 24`
  3. `_gum_interceptor_backend_activate_trampoline` 增加 `case 24`：先写两条占位指令（`0xD2400000`），再接 `ldr scratch, [on_enter]; br scratch`
  4. `gumelfmodule.c`：`g_mapped_file_new` + `g_mapped_file_get_bytes` → `g_file_get_contents` + `g_bytes_new_take`（整读入堆）；失败时 `g_clear_error` 后回退到进程内已有映射
- **平台**：ART 部分仅 Android arm64（该文件本身只在 arm64 编译，内层再叠加 `HAVE_ANDROID`）；`gumelfmodule` 改动全平台生效。
- **适配锚点**：`gum_interceptor_backend_prepare_trampoline`、`_gum_interceptor_backend_activate_trampoline`、`GUM_INTERCEPTOR_FULL_REDIRECT_SIZE`、`gum_elf_module_load`。
- **失败信号**：arm64 hook ART 崩溃/跑飞 → 24 字节分支未命中，或占位指令在新版 ART 上语义不对；ELF 加载内存翻倍 → 整读的预期代价，需评估是否值得。

---

### C8 exceptor 可选降级（不 inline hook sigaction）

- **目的**：加固壳会读函数前 12 字节判断是否 `paciasp`（是否被 inline hook）。Frida 的 exceptor 默认 inline hook `sigaction`/`signal`，暴露痕迹。该开关把 exceptor 降级为"只装信号处理器、不改机器码"。
- **改动位置**：`frida-core/lib/payload/libc-shim.c` 的 `frida_libc_shim_init()`
- **手法**
  ```c
  #if defined (HAVE_ANDROID)
    if (getenv ("MS_EXCEPTOR_HANDLER_ONLY") != NULL ||
        access ("/data/local/tmp/msexceptor.handler_only", F_OK) == 0)
      gum_exceptor_set_mode (GUM_EXCEPTOR_MODE_HANDLER_ONLY);
  #endif
  gum_init_embedded ();   // 必须在 set_mode 之后
  ```
  - 两种触发方式都要：环境变量对注入器自身生效；`frida-so-inject` 不向目标进程传环境变量，目标只能靠文件标记
  - 必须在 `gum_init_embedded()` **之前**：`set_mode` 内部断言 exceptor 尚未创建
  - 代价：目标之后调 `sigaction/signal` 会真实生效，可能覆盖已装处理器
  - 不覆盖：`exit/_exit/abort` 的 hook 属 `ExitMonitor`，要用 `attach(exit_monitor=False)` 单独关
- **平台**：**必须整段包在 `#if defined(HAVE_ANDROID)` 内**。原因：该段用了 `access()` 与 `<unistd.h>`，而 `libc-shim.c` 在 `HAVE_WINDOWS` 下排除 `<unistd.h>`，不加门限会导致 Windows 编译失败。**这个门限是 Windows 能编译的前提，不要移除。**
- **适配锚点**：`frida_libc_shim_init`、`gum_exceptor_set_mode`、`GUM_EXCEPTOR_MODE_HANDLER_ONLY`。
- **失败信号**：Windows 构建报 `access` 未声明 → 门限被破坏；开关无效 → 模式枚举改名。

---

### C9 Windows 可见标识改名与 load-only 修复

- **目的**
  1. Windows 无 memfd，agent 以**临时 DLL 文件**注入，路径/文件名/管道名是固定指纹 → 全部改为中性前缀
  2. 修复 load-only 注入（空 entrypoint）在目标进程内 `call NULL` 崩溃
- **改动位置与手法**
  | 文件 | 改动 |
  | --- | --- |
  | `frida-core/src/windows/winjector.vala` | 临时 blob 名 `blob%u.dll` → `msagent%u.dll` |
  | `frida-core/src/windows/windows-host-session.vala` | agent 资源模板 `<arch>\frida-agent.dll` → `<arch>\msagent.dll` |
  | `frida-core/src/windows/frida-helper-process.vala` | 临时 helper exe `frida-helper-$name.exe` → `ms-helper-$name.exe`；线程名 `frida-helper-factory` → `ms-helper-factory` |
  | `frida-core/lib/pipe/pipe-windows.c` | 管道前缀 `\\.\pipe\frida-` → `\\.\pipe\ms-` |
  | `frida-core/src/system.vala` | 临时目录名前缀 `frida-` → `ms-` |
  | `frida-core/src/windows/frida-helper-backend-glue.c` | 注入 stub 增加空 entrypoint 判空 |
- **load-only 修复**：在 `frida_remote_worker_context_emit_payload` 的 x86/x86_64 分支，`GetProcAddress` 之后插入
  ```text
  test rax, rax
  je   skip_entrypoint_call
  ...原调用 entrypoint...
  jmp  entrypoint_call_done
  skip_entrypoint_call:
  mov dword [rbx + offsetof(FridaRemoteWorkerContext, stay_resident)], 1   ; 置常驻，避免随后 FreeLibrary
  entrypoint_call_done:
  ```
  与 C6 里 Linux `loader.c` 的 `if (ctx->agent_entrypoint[0] != '\0')` 语义对齐。
- **平台**：仅 windows。arm64 版 stub 未加该判空（若支持 windows-arm64 需补 `#ifdef HAVE_ARM64` 分支）。
- **适配锚点**：上述 6 个文件的字符串常量；`frida_remote_worker_context_emit_payload` 的 `GumX86Writer` 指令序列与标签名（`loadlibrary_failed`/`skip_unload`/`return_result` 附近）。
- **失败信号**：产物里仍出现 `frida-agent.dll` / `frida-helper-` / `\\.\pipe\frida-` → 全仓搜 `"frida-` 找遗漏点；load-only 注入崩溃 → stub 判空未生效，或 `stay_resident` 偏移算错。

---

### C10 观测日志（仅 debug）

- **目的**：debug 构建时观察 gum 初始化、trampoline、ELF 加载、JS scheduler 的关键路径。
- **改动位置**：`frida-gum/gum/gum.c`、`frida-gum/gum/gumelfmodule.c`、`frida-gum/gum/backend-arm64/guminterceptor-arm64.c`、`frida-gum/bindings/gumjs/gumscriptscheduler.c`
- **手法**：每个文件定义
  ```c
  #define MY_OBS_LOG(...) g_log ("MYOBS", G_LOG_LEVEL_INFO, __VA_ARGS__)
  ```
  在关键点打日志。**统一走 `g_log`**：GLib 默认路由在 Android 走 logcat、Linux 走 stderr、Windows 走 `OutputDebugString`，一份代码三平台可观测。不要用 `__android_log_print`（那会把 debug 能力绑死在 Android）。
- **平台**：全平台（仅 debug 构建）。
- **适配锚点**：`gum_init_embedded`、`gum_elf_module_load`、`prepare_trampoline`/`activate_trampoline`、`gum_script_scheduler_start`/`stop`。
- **失败信号**：debug 产物搜不到 `MYOBS` → 补丁未进；有字符串但无输出 → 被 gum 自己的 `g_log_set_default_handler` 吞掉，需要确认该 handler 是否转发。

---

### C11 二分停止点（仅 debug）

- **目的**：注入后在指定阶段主动停下，用于定位"哪个初始化阶段触发崩溃/检测"。
- **改动位置**：`frida-core/lib/gadget/gadget-glue.c`、`frida-core/lib/gadget/gadget.vala`、`glib/gio/gtask.c`
- **手法**
  - C 侧 `frida_gadget_bisect_stop_after(stage)`：检查 `<标记目录>/mygadget.stop.<stage>` 是否存在，存在则提前 `return`
  - Vala 侧同名 `stop_after(stage)` 覆盖 `load()` 全流程各阶段；另有全局短路文件 `mygadget.nop`（只验证 dlopen、不做任何初始化）
  - 阶段名清单（可扩展）：`glue-gio-init`、`glue-garbage-handler`、`glue-script-backend-type`、`glue-error-quark`、`glue-worker-context`、`glue-worker-loop`、`glue-worker-thread`、`glue-worker-entry`、`glue-worker-push-context`、`glue-worker-loop-return`、`environment-init`、`detect-location`、`load-config`、`process-policy`、`cloak-range`、`interceptor-obtain`、`interceptor-begin`、`exceptor-obtain`、`controller-create`、`interceptor-end`、`resume`、`start`、`start-before-idle-source`、`start-idle-callback`、`start-before-attach`、`perform-start-*`、`gtask-after-*`
- **平台**：全平台可编译，但标记目录若沿用 Android 的 `/data/local/tmp`，Linux/Windows 上永不触发。想让 debug 三平台可用，改用 `g_get_tmp_dir()` 或平台命名事件。
- **适配锚点**：`gadget-glue.c` 的 `frida_gadget_environment_init`、`run_worker_loop`；`gadget.vala` 的 `load()`、`start()`、`perform_start()`；`gtask.c` 的 `g_task_new`。
- **失败信号**：release 产物出现 `mygadget.stop.` → debug 改动漏进 release（产物门禁应拦）。

---

## 2. 预编译产物的一致性约束

C2、C6、C9 涉及"源码改动 + 预编译二进制"两处，二者必须同步，否则改源码**不会生效且不会报错**。

### 2.1 Android Java helper（`helper.dex`）

- 上游 `frida-core/src/android-helper/helper.dex` 是**预编译 dex**，构建期不重编 Java。
- 改了 `Helper.java`（C2 的线程名改造）后**必须重编 dex**，否则 Android 上 helper 线程名不变。
- 重编：在 `frida-core/src/android-helper/` 执行 `make helper.dex`（`Makefile` 需 `JAVAC`/`JAR`/`D8` 与 android.jar），替换该 dex。
- 校验：`strings -a helper.dex | grep "Jit thread pool"` 有命中即已同步。

### 2.2 Linux helper payload（`frida-core/src/linux/helpers/artifacts/native/<abi>/`）

上游自带这些预编译 blob，主构建**只消费、不生成**：

| 文件 | 来源 | 说明 |
| --- | --- | --- |
| `bootstrapper.bin` | 由 `bootstrapper.c` 等编出 | 上游已有 |
| `loader.bin` | 由 `loader.c` 编出 | **含 C2 的 `PR_SET_NAME` 改动时必须重编** |
| `zymbiote.elf` | 由 `zymbiote.c` 编出 | 上游已有 |
| `code-hello.bin` / `code-exec.bin` / `code-commercial-wrapper.bin` | 由 C6 新增的 `.c` 编出 | 上游没有，必须自己生成 |

- 编法：`frida-core/src/linux/helpers/` 是**独立 meson 工程**（`meson.build` 里自带 `project()`），可单独 `meson setup build && ninja -C build`，产物即 `artifacts/native/<abi>/`。上游还提供 `Makefile` / `rebuild.sh` 入口。
- 约束：改了 `loader.c` / `code-*.c` 后必须重编对应 `.bin`，否则主构建用的还是旧 blob。
- 现状提醒：通常只有被实际验证过的 ABI（如 `arm64`）有重编产物，其它 ABI 仍是上游原始 blob → 对应平台上 C2 的 loader 线程名、C6 的 load-only so 注入会退化到上游行为。

---

## 3. 构建约束（与上游构建系统相关）

以下都是在 Frida 上游构建系统上实测得出的约束，与任何特定仓库的脚本无关。

### 3.1 必须从源码构建 GLib

C1、C2、C11 改的是 `glib/`，而上游 `sdk-<host>` 预编译包里已含 GLib 静态库。因此**必须从源码构建 GLib 并覆盖 SDK**：

```bash
# 1. 克隆固定 commit 的 glib fork，应用 C1/C2/C11 的改动
git clone https://github.com/frida/glib.git glib-src
git -C glib-src checkout <GLIB_COMMIT>
# ...在 glib-src 里落实 C1/C2/C11 的源码改动...

# 2. 自建 SDK bundle（只含 glib 链路，产物 sdk-<host>.tar.xz）
FRIDA_DEPS=<tmpdir> python3 releng/deps.py build \
    --bundle=sdk --build=<build-host> --host=<target-host> --only=glib -v

# 3. 覆盖到依赖目录（注意先让 configure 拉全量 SDK，再覆盖，不要反过来）
tar -xJf <tmpdir>/sdk-<host>.tar.xz -C deps/sdk-<host>/
```

注意：
- `--only=glib` 产出的包**只含 glib + pcre2 + libffi + zlib**；直接解到一个空目录会让后续 configure 缺 v8/libsoup 等。正确顺序是"先全量 sync，再覆盖"。
- `deps.py build` 用的是 `bootstrap_version`（不是 `deps_version`），会额外下载对应版本的 toolchain。
- `deps.py` 用 `FRIDA_DEPS` 决定依赖缓存目录。**自建完必须清除该变量**再跑主 configure，否则主 configure 会去临时目录找 SDK，报缺 `libngtcp2` 之类。

### 3.2 native 构建必须显式开启产物

根 `frida/meson.build` 的 auto 规则在 `build == host`（native 构建）时会把 server/gadget/inject **关闭**，交叉构建才默认开启。所以 Linux/Windows 本机构建必须显式：

```text
./configure --host=<host> --prefix=<prefix> \
    --enable-server --enable-gadget --enable-inject \
    --disable-frida-tools --disable-frida-python \
    -- -Dlibdir=lib [平台附加项]
```

平台附加项：

| 平台 | 附加选项 | 原因 |
| --- | --- | --- |
| Linux | `-Dfrida-core:compat=disabled` | compat 是 32 位 legacy helper/agent，需要额外的 32 位 SDK（`sdk-linux-x86`）与 32 位工具链 |
| Windows | `-Dfrida-core:compat=disabled -Dfrida-core:compiler_backend=disabled -Dfrida-core:barebone_backend=disabled` | compat 同上；compiler_backend 要 Go ≥1.24；barebone_backend 要 node + quickjs/lzfse |

### 3.3 各平台构建要点

| 平台 | 编译器/bundle | 额外要点 |
| --- | --- | --- |
| Android cross | NDK r29 + `sdk-android-<arch>` + `toolchain-linux-x86_64` | 构建期不重编 Java，`helper.dex` 走 §2.1 |
| Linux native | 系统 gcc + `sdk-linux-x86_64` + `toolchain-linux-x86_64` | 关 compat |
| Windows native | MSVC（runner/本机自带）+ `sdk-windows-x86_64-mt` + `toolchain-windows-x86` | 见下 |

Windows 三个坑：
1. GLib 的 `gdbus-codegen` 仍 `import distutils`，Python 3.12 已移除 → 需 `pip install setuptools` 提供兼容层
2. `make frida-code-inject` 这类目标名在 Windows 上可能报 target not found（`custom_target` 名与 make 目标名不一致）→ 用 `make.bat` 全量构建后按路径取产物
3. SDK bundle 名带 CRT 后缀：`sdk-windows-x86_64-mt`（toolchain 则固定映射到 `toolchain-windows-x86`）

### 3.4 产物命名

OS 可见的进程映像名由**产物文件名**决定。Windows 上 `EPROCESS.ImageFileName` 用户态改不了，必须在命名上解决：

| 平台 | 建议产物名 |
| --- | --- |
| Android / Linux | `ms_server`、`gadget.so`、`frida-code-inject`、`frida-so-inject` |
| Windows | `ms_server.exe`、`gadget.dll`、`frida-inject.exe`（自研 code/so 注入依赖 Linux helper，Windows 不产出） |

## 4. 跨版本适配流程

```text
开始
 │
 ├─ 1. 确定目标版本与四个 commit（root / frida-core / frida-gum / glib），记录新旧版本便于回溯
 │
 ├─ 2. 逐条落实 C1–C11
 │       ├─ 语义未变、只是位置漂移 → 按"适配锚点"在新源码里重新定位插入点
 │       ├─ 符号被改名/移除        → 在新版找等价物（优先看上游是否已内置该能力）
 │       └─ 官方已解决            → 按 §4.1 判断可否删掉该项
 │
 ├─ 3. 预编译产物同步（§2）
 │       ├─ 改过 loader.c / code-*.c → 重编 artifacts/native/<abi>/*.bin
 │       └─ 改过 Helper.java         → 重编 helper.dex
 │
 ├─ 4. 编一遍（release + debug 各一次）
 │       └─ 失败先查 §3 构建约束，再查 §5 技术债
 │
 ├─ 5. 产物门禁核对（§4.2）
 │
 ├─ 6. 运行时验证
 │       ├─ Linux：起 server → /proc/<pid>/comm、线程名、监听端口、
 │       │         注入后 /proc/<pid>/maps 里的 memfd 名
 │       ├─ Windows：server 起来、产物无 frida-* 残留、load-only 注入不崩
 │       └─ Android：真机 attach → memfd 名、helper 线程名
 │
 └─ 7. 文档同步：C1–C11 的"适配锚点/失败信号"如已变化必须更新
```

### 4.1 每项能力"还需不需要"的判断

升级后**不要默认所有改动仍然必要**：

| 能力 | 可以删掉的情形 |
| --- | --- |
| C1 进程可见名 / C2 线程名 / C3 agent 名 / C4 端口 / C9 Windows 标识 | 上游已改名或已提供配置项 |
| C8 exceptor 降级 | 上游 exceptor 支持"不 hook sigaction"的配置 |
| C5 注入期冻结 | 上游注入流程已自带冻结策略 |
| C6 自研注入器 | 上游提供等价的 code/so 注入工具 |
| C7 PrettyMethod 24 字节 | 上游 arm64 redirect 已能处理短函数头 |
| C7 ELF 整读 | 确认上游已不需要规避 mmap 行为 |
| C10 / C11 | 一直保留（仅 debug） |

### 4.2 产物门禁

| 检查 | release | debug |
| --- | --- | --- |
| 产物存在且非空 | ✓ | ✓ |
| 文件类型正确（ELF 可 `readelf -h`；PE 有 `MZ` 头） | ✓ | ✓ |
| 含 `gogogo` | ✓ | ✓ |
| 含 `msagent` | ✓ | ✓ |
| 含 `Jit thread pool worker thread` | ✓ | ✓ |
| 含 `MYOBS` | **不得含** | ✓ |
| 含 `mygadget.stop.` / `mygadget.nop` | **不得含** | ✓ |
| 含 `Connection Listener` / `Connection Handler` | 不得含 | 不得含 |

### 4.3 适配动作的判定顺序

1. **先判是否纯位置漂移**：对比报错位置与新源码实际内容，语义一致就只挪插入点。
2. **再判符号是否还在**：patch 引用的函数/结构/常量（`gum_exceptor_set_mode`、`HelperLibcApi`、`ThreadSuspendScope`、`GUM_INTERCEPTOR_FULL_REDIRECT_SIZE`…）在新版是否改名或移除。
3. **最后判语义是否变**：例如上游把 `g_thread_proxy` 的 NULL 判断加回来、或把 `g_system_thread_set_name` 改成宏——此时不是挪位置，而是要在新结构里找等价插入点并复核 C2 的 NULL 安全性。

## 5. 技术债与陷阱

按"踩到会浪费最多时间"排序：

1. **`G_OS_LINUX` 不存在**。GLib 只定义 `G_OS_UNIX` / `G_OS_WIN32`（见 `glib/meson.build` 的 `glib_os` 生成逻辑）。"只在 Linux 生效"的分支必须用 `__linux__`；用 `G_OS_LINUX` 会**编译通过但行为为空**。

2. **`g_set_prgname` 不是免探测手段**。它只改 GLib 进程内静态字符串。必须"GLib 内部状态 + 平台后端（`prctl` / `SetThreadDescription`）"两件事都做。

3. **预编译产物与源码的静默漂移**。主构建消费的是 `artifacts/native/<abi>/*.bin` 和 `helper.dex`；改源码不重编这些，行为完全不变**且构建不报错**。见 §2。

4. **`@INPUTn@` 编号要手改**。给 `helper_backend_inputs` 加输入时，`helper_backend_input_args` 编号必须从 1 连续排到 N；漏改会错位传参（**编过、跑挂**）。

5. **`gum-runtime` 类改动容易夹带噪声**。空 `#ifdef`/空 `else`/空 `if-elseif` 分支、多余空行，功能无影响但会持续增大后续适配时的失败概率。清理时逐段确认没有真逻辑被删。

6. **业务 payload 是目标特化的**。`code-commercial-wrapper.c` 硬编码 `0x14e33c18`（GNames）、`0x15772758`（UWorld）、`libUE4.so`、目标类名等，只对特定游戏版本有效。换目标必须重算偏移，不能当通用组件。

7. **注入期冻结在桌面环境是强副作用**。每次注入冻结整进程 200ms+，`close()` 时再恢复。若 `close()` 的静态派发失效会漏发 `SIGCONT`，目标残留 group-stop。非 Android 反调试场景建议改为条件启用。

8. **Windows 进程名只能做到文件名级**。`EPROCESS.ImageFileName` 由 exe 文件名决定，用户态改不了；`SetThreadDescription` 只影响线程描述。不要承诺运行期完全伪装；PEB 改写也只覆盖自查询面。

9. **Windows 的 make 目标名不可靠**。`custom_target` 的输出名与 make 目标名不一定一致，按目标名构建可能 target not found。稳妥做法是全量 `make` 后按产物路径取。

10. **`FRIDA_DEPS` 会污染主 configure**。自建 GLib 时设了它，之后必须清除再跑主 configure，否则会去临时目录找 SDK。

11. **二分停止点的标记路径**。若沿用 Android 的 `/data/local/tmp`，Linux/Windows 上永不触发。要三平台可用需改用 `g_get_tmp_dir()` 或平台命名事件。

12. **未覆盖的能力**：Windows 上的 code/so 注入、注入期 suspend-all、PEB 身份改写、arm64 stub 的空 entrypoint 判空。若扩展到 windows-arm64 或需要这些能力，需按 C6/C9 的结构自行补齐。

## 6. 快速索引

| 想改什么 | 看哪里 |
| --- | --- |
| 进程名 / 线程名 / agent 名 | C1、C2、C3、C9 |
| 端口与网络指纹 | C4 |
| 注入时序与反调试 | C5、C8 |
| 自研注入工具与 payload | C6、§2.2 |
| hook 引擎行为 | C7 |
| 预编译产物同步 | §2 |
| 构建失败 | §3、§5 |
| 升版适配 | §4 |
