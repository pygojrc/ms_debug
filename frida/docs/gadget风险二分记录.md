# gadget 风险二分记录

## 2026-05-18 3 秒窗口结论

- 判断窗口已统一改为 3 秒；启动命令不使用 `am start -W`，避免白屏时阻塞。
- 脚本：`scripts/定位_gadget_worker循环.sh`
- 证据目录：
  - `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-183220`
  - `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-183535`

## 已确认安全点

- `start-before-idle-source`：正常进入 `MainGroupActivity`。
- `start-idle-callback`：正常进入 `MainGroupActivity`。
- 说明：`g_main_loop_run(worker_loop)` 本身、worker 线程、IdleSource 挂载和回调触发，不足以导致白屏/死亡。

## 已确认危险点

- `perform-start-suspend`：3 秒内仍出现主进程循环死亡。
- `perform-start-enter`：3 秒内仍出现主进程循环死亡。
- `perform-start-before-controller-start`：3 秒内仍出现主进程循环死亡。
- `none`：3 秒内主进程反复 `SIGKILL`，停留在 `SplashActivity`。

## 当前定位到的具体代码行

源码位置：`frida/subprojects/frida-core/lib/gadget/gadget.vala`

```vala
source.set_callback (() => {
	if (stop_after ("start-idle-callback"))
		return false;

	perform_start.begin (request);
	return false;
});
```

当前分界：

- `start-idle-callback` 在 `perform_start.begin(request)` 前返回，app 正常。
- `perform-start-suspend` 已进入 `perform_start.begin(request)`，但在 async 函数内挂起 60 秒，不执行 `ThreadIgnoreScope` 和 `controller.start()`，app 仍异常。

因此，当前可复现的危险起点不是 `ThreadIgnoreScope`、不是 `controller.start()`、也不是 listen socket/gdbus 完整启动，而是 `perform_start.begin(request)` 触发的 Vala async/GTask 启动路径。

对应生成 C 代码位置：`build/frida-android-arm64/subprojects/frida-core/lib/gadget/libfrida-gadget-raw.so.p/gadget.c`

```c
_data_ = g_slice_new0 (FridaGadgetPerformStartData);
_data_->_async_result = g_task_new (NULL, NULL, _callback_, _user_data_);
g_task_set_name (_data_->_async_result, "Frida.Gadget.perform_start");
g_task_set_task_data (_data_->_async_result, _data_, frida_gadget_perform_start_data_free);
frida_gadget_perform_start_co (_data_);
```

运行表现：

- 安全点 `start-idle-callback` 仅看到 `mygadget-worker`。
- 进入 `perform_start.begin(request)` 后，即使挂起不继续执行，也会出现 `gmain` 线程，随后主进程约 0.4-0.7 秒内被 `SIGKILL`。

后续修复应优先围绕这条路径验证：避免 gadget 启动时创建可见 `gmain` 线程，或改写 `perform_start` 的 async/GTask 调度方式。

## 2026-05-18 perform_start.begin 内部二分

进一步在生成 C 文件中临时拆分 `perform_start.begin(request)`：

生成 C 位置：`build/frida-android-arm64/subprojects/frida-core/lib/gadget/libfrida-gadget-raw.so.p/gadget.c`

```c
_data_ = g_slice_new0 (FridaGadgetPerformStartData);
_data_->_async_result = g_task_new (NULL, NULL, _callback_, _user_data_);
g_task_set_name (_data_->_async_result, "Frida.Gadget.perform_start");
g_task_set_task_data (_data_->_async_result, _data_, frida_gadget_perform_start_data_free);
_tmp0_ = _gee_promise_ref0 (request);
_data_->request = _tmp0_;
frida_gadget_perform_start_co (_data_);
```

证据目录：

- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-184149`
- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-184315`

结论：

- `perform-begin-after-alloc`：安全，app 正常进入 `MainGroupActivity`。
- `perform-begin-after-g-task-new-leak`：异常，即 `g_task_new()` 后不做清理、直接返回，仍会出现 `gmain`，随后主进程循环死亡。
- `perform-begin-after-g-task-new`：异常。
- `perform-begin-after-task-name` 及后续：异常。

因此新的精确分界为：

- 安全：`_data_ = g_slice_new0 (FridaGadgetPerformStartData);`
- 危险：`_data_->_async_result = g_task_new (NULL, NULL, _callback_, _user_data_);`

这说明异常不是任务名 `Frida.Gadget.perform_start`、不是保存 request、不是进入 `frida_gadget_perform_start_co()`，而是在创建 `GTask` 后就触发。运行日志也显示从该点开始出现 `gmain` 线程。

## 2026-05-18 继续向下二分：收敛到 `gmain` 线程名

本轮继续在生成 C 中临时拆 `g_task_new()` / `g_task_get_type()` 路径。相关证据目录：

- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-185118`
- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-185305`
- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-185554`
- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-185803`
- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-185905`

关键结论：

- `perform-begin-after-alloc`：安全，app 正常进入 `MainGroupActivity`。
- `g_task_get_type()` 后继续触发异常，说明危险已经早于 `g_object_new(GTask)`。
- 单独调用 `g_get_worker_context()` 可复现异常；日志中新增线程名 `gmain`，随后主进程约 0.6 秒内死亡并重启。
- 手动 `g_thread_new("ms-main", ...)`：安全，app 正常进入 `MainGroupActivity`。
- 手动 `g_thread_new("gmain", ...)`：异常，3 秒窗口内主进程循环死亡。

因此当前已经有明确、直接的最小复现：

```c
g_thread_new ("gmain", my_gadget_sleep_thread, NULL);
```

对应 GLib 源码位置：

```c
// frida/subprojects/glib/glib/gmain.c
static void
glib_worker_start (void)
{
  ...
  glib_worker_thread = g_thread_new ("gmain", glib_worker_main, NULL);
  ...
}

GMainContext *
g_get_worker_context (void)
{
  ...
  glib_worker_start ();
  ...
}
```

`g_task_get_type()` 触发该路径的原因是 `G_DEFINE_TYPE_WITH_CODE (GTask, ...)` 的 custom code 会执行 `g_task_thread_pool_init()`，其中调用 `GLIB_PRIVATE_CALL (g_get_worker_context ())` 来 attach `GTask thread pool manager` source。

当前判断：这次白屏/死亡循环的直接触发点不是普通新线程，也不是 GTask 对象构造本身，而是出现名为 `gmain` 的 GLib worker 线程。后续修复优先改 GLib worker 线程名，或避免 gadget 启动早期走 `g_get_worker_context()`。

## 2026-05-18 修复与验证

第一次只把 `gmain` 改为 `ms-gm` 后，完整 `none` 启动仍异常。复测边界：

- `perform-start-before-controller-start`：安全，进入 `MainGroupActivity`。
- `perform-start-after-controller-start`：异常。
- `none`：异常。

异常线程从 `gmain` 变为：

- `pool-gogogo`
- `gdbus`

因此继续做线程名修复：

- `frida/subprojects/glib/glib/gmain.c`：`gmain` => `ms-gm`
- `frida/subprojects/glib/gio/gdbusprivate.c`：`gdbus` => `ms-db`
- `frida/subprojects/glib/glib/gthreadpool.c`：`pool-spawner` => `mspl-spawner`
- 当前实际链接使用的预构建静态库也做等长替换：
  - `frida/deps/sdk-android-arm64/lib/libglib-2.0.a`
  - `frida/deps/sdk-android-arm64/lib/libgio-2.0.a`
  - `pool-%s` => `mspl-%s`

重建后最终 `frida-gadget.so` 字符串检查：

- 仅剩 `ms-gm`、`ms-db`、`mspl-%s`、`mspl-spawner`
- 未再出现 `gmain`、`gdbus`、`pool-%s`

验证目录：

- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-200739`

验证结果：

```json
{
  "stage": "none",
  "observeSeconds": 3,
  "pidAlive": true,
  "hasMainGroupActivity": true,
  "hasDeathOrFatal": false
}
```

日志中线程名变为：

- `mygadget-worker`
- `ms-gm`
- `mspl-gogogo`
- `ms-db`

并显示 `MainGroupActivity` 正常创建、绘制。额外延长 10 秒检查后，`pidof com.qidian.QDReader` 仍返回主进程 pid，焦点窗口仍为 `MainGroupActivity`。

## 2026-05-18 调整修复落点：构建脚本临时修补 SDK 静态库

`frida/deps/sdk-android-arm64/lib/libglib-2.0.a` 和 `libgio-2.0.a` 是 Frida 的预构建 SDK 依赖，不适合作为本项目源码改动保存。

已改为项目侧构建脚本临时处理：

- 新增 `scripts/修补_ms线程名.py`
- `scripts/build_frida_android.sh` 在每次 Frida 目标构建前临时修补 SDK 静态库，覆盖 `frida-server`、`frida-inject`、`frida-gadget` 等通过该脚本重新链接的目标
- 修补对象为：
  - `frida/deps/sdk-android-arm64/lib/libglib-2.0.a`
  - `frida/deps/sdk-android-arm64/lib/libgio-2.0.a`
- `make` 完成后通过 `--reverse` 恢复静态库，避免 `frida/deps` 长期保持本项目特定改动

修补规则仍为等长字节替换：

- `gmain` => `ms-gm`
- `gdbus` => `ms-db`
- `pool-%s` => `mspl-%s`
- `pool-spawner` => `mspl-spawner`

当前验证：

- `libglib-2.0.a` 仍包含原始 `gmain`、`pool-%s`、`pool-spawner`
- `libgio-2.0.a` 仍包含原始 `gdbus`
- 构建后的 `frida-gadget.so` 只包含修补后的 `ms-gm`、`ms-db`、`mspl-%s`、`mspl-spawner`

重新部署验证目录：

- `tmp/风险二分-20260518-白屏核查/worker循环定位3秒-202123`

结果：

```json
{
  "stage": "none",
  "observeSeconds": 3,
  "pidAlive": true,
  "hasMainGroupActivity": true,
  "hasDeathOrFatal": false
}
```
