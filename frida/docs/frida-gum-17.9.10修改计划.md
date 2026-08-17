# frida-gum 17.9.10 修改计划

参考文档：`/data/projects/Frida/Florida/docs/frida-gum改动复现.md`

目标版本：Frida `17.9.10`

## 当前结论

- 当前 GumJS 版 `_app.so` 会导致起点读书停在系统启动窗口，主进程反复 `exited cleanly (0)`。
- 删除设备上的 `_app.so` 后，起点读书能正常进入 `MainGroupActivity`。
- 因此后续修改需要每一步都推送 `_app.so` 到设备验证，不能只看编译结果。

## 涉及文件

```text
frida/subprojects/frida-gum/gum/gumelfmodule.c
frida/subprojects/frida-gum/gum/backend-arm64/guminterceptor-arm64.c
frida/subprojects/frida-gum/gum/gum.c
frida/subprojects/frida-gum/bindings/gumjs/gumscriptscheduler.c
```

## 执行顺序

1. 观测基线
   - 不改变 Gum 行为，只给上述候选代码路径添加 Android log。
   - `_app.so` 同时记录运行时 `/proc/self/maps`、`/proc/self/fd`、`/proc/self/task`，用于确认 mmap 文件、打开文件和线程名。
   - 重新编译 `libfrida-gum-1.0.a` / `libfrida-gumjs-1.0.a` 和 `_app.so`。
   - 推送 `_app.so` 到起点读书并启动，记录 Gum 初始化、ELF 读取、JS scheduler、ARM64 interceptor 决策是否执行。

2. 修改一：ELF 文件加载改为内存读取
   - 在 `gum_elf_module_load()` 中避免直接 `g_mapped_file_new()` mmap 文件。
   - 优先使用 `g_file_get_contents()` 读取 ELF 到普通内存，再用 `g_bytes_new_take()` 接管。
   - 继续把内存范围加入 `gum_cloak_add_range()`。
   - 推送验证 app 是否仍白屏、日志是否显示内存读取路径。

3. 修改二：标识改名
   - `gum_init_embedded()` 中 `g_set_prgname("frida")` 改成非默认值。
   - `gum_script_scheduler_start()` 中 JS 线程名由 `gum-js-loop` 改成非默认值。
   - 推送验证 app 状态，并确认线程名/程序名相关日志。

4. 修改三：ARM64 inline hook 24 字节优先
   - **暂停执行。**
   - **特别注释：未修改 ARM64 24 字节 trampoline 时，起点读书已经恢复正常，且 GumJS 可用。**
   - 当前恢复正常的已验证组合为：ELF 文件加载改为内存读取 + `g_set_prgname` / JS 线程名标识改名。
   - `gum_interceptor_backend_prepare_trampoline()` 优先尝试 24 字节重定位。
   - `_gum_interceptor_backend_activate_trampoline()` 增加 24 字节写入分支。
   - 后续如继续该步骤，需要单独作为新变量验证，不能和当前恢复结论混在一起。

5. 最终验证
   - 清理旧日志和旧进程。
   - 推送最终 `_app.so`。
   - 启动起点读书。
   - 判定条件：
     - 起点读书进入 `MainGroupActivity`。
     - `mCurrentFocus` 指向 `MainGroupActivity`。
     - `Activities >= 1`，`ViewRootImpl >= 1`。
     - logcat 中存在 `gumjs demo log` 和 `gumjs demo done`。
     - logcat 中存在 `runtime before-gum maps/fd/threads` 和 `runtime after-gumjs maps/fd/threads`。
     - 不再出现主进程反复 `exited cleanly (0)`。

## 风险点

- 现有异常是应用主动退出或自检触发，单个改动可能不足以恢复，需要逐步组合验证。
- `gum_elf_module_load()` 改读取方式可能增加内存占用，但 `_app.so` demo 当前只用于验证。
- ARM64 24 字节改动只影响 Interceptor patch 行为；当前已暂停，且已确认不需要该改动 app 也能恢复正常。
