# Frida 17.15.3 统一线程命名方案

## 两套命名策略

设计上保留两套可以互相替换的命名策略。当前默认使用方案 A；方案 B 仅作为后续可选方案，不改变当前默认行为。

| 方案 | 默认状态 | OS/外部线程名 | 适用目标 |
|---|---|---|---|
| A：完整描述型 | 默认启用 | `Jit thread pool worker thread N`；Android/Linux 只保留前 15 个字符 `Jit thread pool` | 最大化保持用户指定格式和语义一致性 |
| B：`ms-tN` 紧凑型 | 默认关闭 | `ms-t0`、`ms-t1`、`ms-t2`…… | 短、稳定、可区分，适合 `/proc`、`ps -T` 和调试器直接查看 |

两套方案共用同一个线程编号分配器、来源记录、TID 注册表和直接 `pthread_create()` 封装。变化只发生在“编号/角色如何格式化为线程名”这一层，避免维护两套线程创建逻辑。

## 当前落地状态

当前只落地方案 A，使用独立 patch `009`、`010`、`011`：

- `009` 把 GLib `g_system_thread_set_name()` 接到统一注册表；包括未显式提供名称的 `g_thread_new(NULL, ...)` 在线程入口也会获得方案 A 名称。
- `010` 对 Gum Linux 的直接 `pthread_create()` worker 采用入口显式命名，并优先从注册表返回完整逻辑名；当前没有把 `ms_pthread_create()` 公共封装作为本 patch 的新增 API。
- `011` 对不能依赖 GLib 注册表的 Linux 远程 loader 设置 OS 可见前缀 `Jit thread pool`。
- 方案 B `ms-tN` 目前只保留设计文档，不进入源码、默认构建参数或当前 patch 集合。

## 目标

在不把线程名当作线程身份的前提下，将 GLib、GIO、Vala `Thread<T>`、GLib `ThreadPool` 以及 Frida/Gum 中直接调用 `pthread_create()` 的线程统一纳入同一套命名和观测方案。

默认逻辑名称格式：

```text
Jit thread pool worker thread 0
Jit thread pool worker thread 1
Jit thread pool worker thread 2
...
```

这里的 `N` 是进程内线程命名序号，不代表 TID，也不保证线程长期存在时序不变。线程的真实身份仍然使用 TID、`pthread_t`、Windows handle 或 Mach/LLDB thread ID。

### 方案 B：`ms-tN` 紧凑型

方案 B 使用 `ms-tN` 作为 OS 线程名和默认展示名：

```text
ms-t0
ms-t1
ms-t2
```

它不把原始 `gmain`、`gdbus`、`frida-agent-container` 等名称直接暴露到 OS 层，但命名注册表仍保存完整来源：

```text
os_name:      ms-t7
logical_name: ms-t7
source_name:  frida-agent-container
role:         agent-container
```

如果需要按角色查看，Frida/Gum 的线程详情或观测日志应显示 `source_name`/`role`；不能把角色再次拼接到 OS 名称中导致超过平台长度限制。方案 B 的核心价值是所有线程都能在 `/proc` 和调试器中清晰、稳定地区分，同时保留模块归属信息。

## 必须分层处理名称

Android/Linux 的 `pthread_setname_np()` 和 `/proc/<pid>/task/<tid>/comm` 通常只支持 16 字节缓冲区，其中包含结尾的 NUL，因此最多只能显示 15 个可见字符。完整名称：

```text
Jit thread pool worker thread 0
```

无法原样写入 OS 线程名。如果直接截断，所有线程都会变成类似 `Jit thread pool`，反而失去编号区分。

因此仍使用两层信息。方案 A 不构造缩写；方案 B 明确使用 `ms-tN` 紧凑格式：

| 层级 | 方案 A 默认值 | 方案 B 可选值 | 用途 |
|---|---|---|---|
| 逻辑名称 | `Jit thread pool worker thread N` | `ms-tN`，并附带 `source_name`/`role` | Frida/Gum 观测、日志、注册表 |
| Linux/Android OS 名称 | 前 15 个可见字符：`Jit thread pool` | `ms-tN` | `/proc/.../comm`、`ps -T`、debugger |

不生成 `Jit-wkr-*`、`jit-worker-*` 等替代名称。Android/Linux 通常只保留前 15 个可见字符，因此：

```text
逻辑名称：Jit thread pool worker thread 0
OS 名称：  Jit thread pool

逻辑名称：Jit thread pool worker thread 1
OS 名称：  Jit thread pool
```

方案 A 是用户指定规则的直接结果：OS 层只做长度截断，不缩写、不改写、不保留末尾编号。实现时应在调用 `pthread_setname_np()` / `prctl(PR_SET_NAME, ...)` 前主动取前 15 个可见字符，避免部分 libc 对超长名称直接返回 `ERANGE`。方案 B 则直接设置 `ms-tN`，不需要截断。两种方案都应结合完整线程详情和 TID 使用，不能把线程名当作线程身份。

## 统一命名分配器

新增一个进程内命名分配器，提供以下抽象接口：

```c
typedef enum {
  MS_THREAD_NAME_MODE_DESCRIPTIVE,
  MS_THREAD_NAME_MODE_COMPACT,
} MsThreadNameMode;

typedef struct {
  uint32_t index;
  char logical_name[64];
  char os_name[16];
  char source_name[64];
  char role[32];
} MsThreadName;

void ms_thread_name_allocate (const char *source_name,
                              MsThreadName *result);
void ms_thread_name_set_current (const char *source_name);
void ms_thread_name_set_current_for_index (uint32_t index,
                                           const char *source_name);
void ms_thread_name_set_mode (MsThreadNameMode mode);
```

规则：

1. 第一次进入受管线程入口时分配序号；不要在调用方创建线程但线程尚未启动时分配，以免失败创建消耗序号。
2. `source_name` 只作为诊断输入和兼容信息保存，默认不影响统一逻辑名称。
3. 通过原子递增分配序号，避免多个线程同时启动时重复编号。
4. 以 Linux TID 或 `pthread_t` 建立逻辑名称注册表，线程退出时删除记录。
5. 命名失败不能导致线程创建失败；`pthread_setname_np()` 的错误只记录到调试日志。
6. 不使用线程名进行线程查找、同步、暂停、恢复或注入。

命名注册表应作为 GLib 增量构建的一部分编译进 `libglib`，并提供一个小型、可选的查询接口给 Gum：

```c
bool ms_thread_name_lookup (uint64_t tid,
                            char *buffer,
                            size_t buffer_size);
```

`gum_linux_query_thread_name()` 的查询顺序改为：

```text
GLib 命名注册表中的完整逻辑名
        ↓ 不存在
/proc/self/task/<tid>/comm 中的 OS 短名
```

查询接口将名称复制到调用方缓冲区，避免线程退出时注册表删除记录造成悬空指针。这样 `Process.enumerateThreads()` 可以返回完整的 `Jit thread pool worker thread N`。对于没有链接自定义 GLib 的独立 Gum 场景，使用弱符号或编译期开关关闭注册表查询，继续返回 `/proc` 短名。

## GLib 统一入口

修改 `frida/subprojects/glib/glib/gthread-posix.c` 中的 `g_system_thread_set_name()`：

```text
g_thread_proxy()
        ↓
g_system_thread_set_name(original_name)
        ↓
ms_thread_name_set_current(original_name)
        ├─ 分配逻辑名：Jit thread pool worker thread N
        ├─ 注册 TID → 逻辑名
        └─ 按当前策略设置 OS 名
```

这样可以覆盖：

- `g_thread_new()` 和 `g_thread_try_new()`；
- GIO/GDBus 后台线程；
- GLib `GMainContext` worker；
- GLib `GThreadPool` 的 `pool-%s` 工作线程和 `pool-spawner`；
- Vala `new Thread<T>()`，因为 Vala 最终调用 GLib 线程 API；
- Frida 中通过 GLib 创建的 agent、gadget、main-loop、scheduler 等线程。

### 是否保留源码中的原始名称

源码中的原始名称仍保留在 `source_name` 或调试映射中，用于故障定位，例如：

```text
logical_name: Jit thread pool worker thread 7
source_name:  frida-agent-container
os_name:      Jit thread pool
```

这样既能实现统一外观，又不会丢失“这个线程原本属于哪个模块”的分析信息。

为了让直接 `pthread_create()` 的线程也进入同一注册表，`ms_pthread_create()` 应调用 GLib 提供的命名分配接口；如果目标代码不能链接 GLib，则至少使用当前策略生成 `Jit thread pool` 前缀或 `ms-tN`，并由 hook 记录其来源。

## 直接 pthread_create 封装

对于 Frida/Gum 中不能经过 GLib 的线程，增加独立封装，不建议仅在调用点散落 `pthread_setname_np()`：

```c
int ms_pthread_create (pthread_t *thread,
                       const pthread_attr_t *attr,
                       void *(*start_routine) (void *),
                       void *arg,
                       const char *source_name);
```

实现方式是分配一个启动参数结构，由 trampoline 完成：

```text
ms_pthread_create()
        ↓
分配命名序号和 source_name
        ↓
pthread_create(ms_thread_trampoline, context)
        ↓
ms_thread_name_set_current_for_index(index, source_name)
        ↓
调用原始 start_routine(arg)
```

至少覆盖当前源码中的：

| 位置 | 处理方式 |
|---|---|
| `frida-gum/gum/backend-linux/gumprocess-linux.c:3956` | 替换为 `ms_pthread_create(..., "gum-linux-thread")` |
| `frida-core/src/linux/helpers/loader.c:64` | 在目标进程内使用等价的轻量 trampoline；不能依赖宿主进程的 GLib 私有符号 |
| `frida-core/src/fruity/helpers/upload-receiver.c:1042` | 非 Android 构建也使用封装 |
| 其它生产代码中的直接 `pthread_create()` | 按平台可用性逐项迁移 |

远程注入 loader 是特殊情况：它运行在目标进程中，代码体积和可用 API 受限制，应使用 `prctl(PR_SET_NAME, ...)` 或目标进程已经解析出的 `pthread_setname_np`，并使用当前选择的策略；不能直接链接宿主侧的完整命名注册表。

## 可选 pthread_setname_np hook

hook 不作为主命名机制，只承担观测和兜底：

| 模式 | 行为 |
|---|---|
| 默认 | 记录调用来源、传入名称、TID 和最终 OS 名称；不覆盖第三方库主动设置的名称 |
| 观测模式 | 输出名称变化事件，帮助发现未迁移的直接 `pthread_create()` 或第三方线程 |
| 兜底模式 | 对没有经过 GLib/`ms_pthread_create` 的线程分配统一编号，并设置完整名称的前 15 个可见字符 |
| 强制重写模式 | 将所有 `pthread_setname_np` 请求映射到统一方案；仅用于专门验证，不作为默认发布配置 |

hook 必须防止递归：内部设置 OS 名称时使用真实 libc 地址或一次性递归保护标志。hook 失败、符号不存在或平台签名不同，都不能阻止线程创建。

## 方案选择方式（暂不定案）

方案选择暂时不绑定到某一种机制，后续根据发布和调试需求决定：

| 选择方式 | 可能实现 | 优点 | 代价 |
|---|---|---|---|
| 运行时开关 | 例如 `MS_THREAD_NAME_MODE=descriptive` 或 `compact` | 同一个构建产物可切换和对比 | 需要保留配置读取、启动时序和测试分支 |
| 编译时开关 | Meson/构建参数选择 `descriptive` 或 `compact` | 产物行为固定，运行时更简单 | 同一源码需要构建两个变体 |
| 两套 patch | 默认 patch 与 `ms-tN` patch 分开维护 | 最清晰，便于独立发布和回滚 | 两套 patch 需要同步维护 |

当前约定：方案 A 是默认方案，方案 B 默认不启用；在开关方式确定前，不将 `ms-tN` 写入默认源码 patch，也不让两种策略在同一个进程中混用。构建产物和验证报告应记录实际使用的策略。

## Apple/Fruity 兼容边界

不能把所有平台的线程名无条件改成统一短名。当前 `frida-core/src/fruity/injector.vala` 会匹配：

```text
frida-gadget-tcp-<port>
```

这个名称在 Apple/Fruity 路径中承担 Gadget 发现和端口传递作用。因此：

1. Android 默认使用完整的 `Jit thread pool worker thread N` 和逻辑名称注册表；如果选择方案 B，则使用 `ms-tN`，但仍保留 `source_name`/`role`；
2. Apple/Fruity 保留 `frida-gadget-tcp-<port>` 这一协议名称；
3. 如果未来要统一 Apple 名称，必须同时修改 Fruity.Injector 的匹配规则；
4. `frida-gadget-unix` 当前没有发现同等的端口提取逻辑，但仍应暂时保留。

## 编号和重启语义

- 编号是单进程运行期间的递增序号，不是稳定线程 ID。
- 线程退出后不复用编号，避免日志中两个生命周期不同的线程产生相同名称。
- 进程重启后从 0 开始。
- 如果产品需要跨进程区分，可在完整逻辑名之外增加 PID 或进程实例 ID；不要修改用户指定的线程名格式。

## 验证方案

不能只比较最终文件哈希，应至少验证以下层次：

1. **源码覆盖**：扫描生产源码，确认 GLib、Vala、ThreadPool 和直接 `pthread_create()` 均进入统一入口或明确豁免列表。
2. **符号/字符串**：按当前策略检查产物中是否仍存在未豁免的原始线程名；方案 A 检查 `Jit thread pool worker thread N`，方案 B 检查 `ms-tN`。
3. **运行时枚举**：在 Android 16 x86_64 和 arm64 上读取 `/proc/<pid>/task/*/comm`；方案 A 确认 OS 名称为 `Jit thread pool`，方案 B 确认名称为 `ms-tN`；两者都通过 Frida/Gum API 检查完整信息和编号。
4. **Frida API**：用 `Process.enumerateThreads()` 检查逻辑名称是否可观测，确认 TID、状态和线程控制仍正常。
5. **行为回归**：验证 Gadget、server、agent、Gum JS scheduler、ThreadPool、注入、暂停/恢复和退出流程。
6. **外部兼容**：检查 `ps -T`、调试器和已有按名称过滤的用户脚本；Apple/Fruity 单独运行协议发现测试。

## 推荐落地顺序

1. 先新增命名分配器和 Linux/Android 短名转换函数。
2. 修改 GLib `g_system_thread_set_name()`，覆盖所有 GLib/Vala/ThreadPool 线程。
3. 增加 `ms_pthread_create()`，迁移 Frida/Gum 直接 pthread worker。
4. 给远程 loader 增加独立、无 GLib 依赖的轻量命名 trampoline。
5. 最后增加默认关闭的 `pthread_setname_np` 观测 hook。
6. 在 x86_64 和 arm64 Android 构建、运行并生成线程名覆盖报告。
