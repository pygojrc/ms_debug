# Frida 17.15.3 改动说明

> 本仓库布局说明：`ms_debug/frida/` 已经是「官方 Frida 17.15.3 源码快照 + 下列 MyFrida 补丁」合并后的整树（已去除 `.git`）。
> 因此 `patchs/` 仅作为 **diff 记录** 留存，构建时**不需要**再 `git apply`。
> 如需从官方 `17.15.3` 重新生成这些补丁，可基于 MyFrida 仓库 `my_frida/v17.15.3` 的 `base_commit..patch_commit` 两次提交比较得到。

本目录记录当前分支 `ms_17.15.3` 相对 Frida `17.15.3` 的本地改动。当前 17.9.10 修改版已保存在 `ms_17.9.10` 分支。

## 可复现基线

- Frida 主仓库：`17.15.3`
- `frida/subprojects/frida-core`：`9492205c6a968133dbd50f1fe0455e39a3e6fd70`
- `frida/subprojects/frida-gum`：`befbceab8f9c4f5d4a5e939f675df5c669b44510`
- `frida/subprojects/glib`：`92d65736b198c2cf131f691dd83db0b25f7b02d2`
- Android NDK：r29，项目默认位置为 `/data/opt/android-ndk-r29`

## 应用方式

推荐使用：

```bash
bash patchs/apply_frida_17_15_3_patches.sh
FRIDA_TARGET=frida-server bash scripts/run_podman.sh
```

生产版如需移除二分停止点和 Android log 观测，再执行：

```bash
bash patchs/apply_production_cleanup_patches.sh
FRIDA_TARGET=frida-server bash scripts/run_podman.sh
```

补丁目标目录不同，不能直接 `git apply patchs/*.patch`。

## Patch 状态

### 001-frida-core-gadget-bisect.patch

- 范围：`frida-core/lib/gadget/gadget.vala`、`gadget-glue.c`
- 状态：已直接迁移到 17.15.3。
- 内容：保留 `/data/local/tmp/mygadget.nop`、`/data/local/tmp/mygadget.stop.<stage>` 二分开关，并将 gadget worker 线程名改为 `mygadget-worker`。

### 002-glib-gio-thread-name-and-gtask-bisect.patch

- 范围：`glib/gmain.c`、`glib/gthreadpool.c`、`gio/gdbusprivate.c`、`gio/gtask.c`
- 状态：已在 GLib `92d65736...` 上直接迁移。
- 内容：保留 `gmain -> ms-gm`、`gdbus -> ms-db`、`pool-spawner -> mspl-spawner`，以及 `g_task_new()` 二分停止点。

### 003-project-build-temporary-sdk-patch.patch

- 范围：项目构建入口脚本。
- 状态：已迁移到 17.15.3。
- 内容：构建前临时修补 `frida/deps/sdk-${FRIDA_HOST}/lib/libglib-2.0.a` 和 `libgio-2.0.a`，构建结束反向恢复；版本检查改为 `17.15.3`。

### 004-project-thread-name-patcher-script.patch

- 范围：`scripts/修补_ms线程名.py`
- 状态：无需代码改动，已用正向/反向最小样例验证。
- 内容：保留等长字节替换与 `--reverse` 恢复能力。

### 005-frida-server-group-stop-inject.patch

- 范围：`frida-core/src/linux/frida-helper-backend.vala`
- 状态：已直接迁移到 17.15.3。
- 内容：保留 `SIGSTOP + PTRACE_SEIZE + ThreadSuspendScope` 注入窗口控制，close 时先 detach 执行线程再恢复其它线程。

### 006-frida-gum-runtime-and-pretty-method.patch

- 范围：`frida-gum` 的 JS scheduler、ELF module、`gum.c`、ARM64 interceptor。
- 状态：已按 17.15.3 新版 ARM64 interceptor 结构重写适配。
- 内容：保留 `MYOBS` 观测、`gogogo`/`my_loop` 标识改名、ELF 优先读入普通内存、`PrettyMethod` 24 字节 trampoline 特例。

### 007-frida-core-agent-memfd-name-msagent.patch

- 范围：`frida-core/src/linux/linjector.vala`
- 状态：从 `v17.15.3_dev_01` 提取的专用验证补丁。
- 内容：仅修改已知 agent `.so` 资源创建 memfd 时显示在 maps 中的名称，精确把 `frida-agent-64.so` 等白名单名称显示为 `msagent.so`。资源查找、blob 内容、fd 传递、文件 fallback 路径不变，用于验证 `/memfd:frida-agent-64.so (deleted)` 是否是触发点。

## 生产清理 rollback patch

`patchs/rollback/` 中的补丁只应用在已经打过 `001..006` 的源码树上，用于生产构建前移除诊断/验证代码：

- `001-remove-frida-core-gadget-bisect.patch`：移除 gadget 二分停止点和 `mygadget.nop`，保留 `mygadget-worker`。
- `002-remove-glib-gtask-bisect.patch`：移除 `g_task_new()` 二分停止点，保留 `ms-gm`、`ms-db`、`mspl-spawner`。
- `003-remove-frida-gum-android-log-observation.patch`：移除 `MYOBS` / `__android_log_print` 观测输出，保留 `my_loop`、`gogogo`、ELF 普通内存读取和 PrettyMethod 特例。

推荐使用 `bash patchs/apply_production_cleanup_patches.sh` 应用，脚本会按目标子仓库逐个检查和跳过已应用补丁。

## 验证状态

- 已完成：patch apply/reverse check、脚本 `bash -n`、线程名修补脚本最小样例。
- 已完成：`frida-server`、`frida-inject`、`frida-gadget` Android arm64 构建。
- 已完成：通过 `scripts/推送并启动_frida_service.sh` 推送并启动设备端 `frida-server`，`frida-ps -H 127.0.0.1:27056` 可连接。
- 已完成：QDReader 与 Notes 的最小 `Java.perform` 注入验证，分别输出 `JAVA_OK package=com.qidian.QDReader` 和 `JAVA_OK package=com.miui.notes`。
- 后续可补充：更完整的 app 运行时 maps/fd/thread、前台 Activity、PID、logcat 基线。
