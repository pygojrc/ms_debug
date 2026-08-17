# frida-code-inject code-only hello 注入记录

## 结论

`frida-code-inject` 是 Android arm64 本地可执行工具，不连接 `frida-server`，不运行 JS，不加载用户 `.so`。它复用 Linux helper backend 的 ptrace、远程 `mmap`、写内存和 remote call 能力，把内置 `code-hello.bin` raw payload 写入目标进程匿名可执行内存并直接执行。

普通 NDK `.so` 不能简单提取 `.text` 当 payload 使用，因为 `.so` 依赖 ELF relocation、GOT/PLT 和外部符号解析。v1 因此只支持内置 hello raw payload。

## 实现要点

- `src/linux/helpers/code-hello.c` 使用 loader 同款 `.payload` 链接方式生成 `code-hello.bin`。
- `src/linux/helpers/inject-context.h` 新增 `FridaCodeContext`，只传入 `data` 和 `FridaLibcApi`。
- `LinuxHelperBackend.inject_hello_code()` 在 arm64 下读取内置 `code-hello.bin` 资源，执行 `inject_code_blob()`。
- `frida-code-inject` CLI hello 模式接收 `--pid/-p`、`--data/-d`、`--version`。
- payload 在目标进程中通过 `dlopen("liblog.so")` 和 `dlsym("__android_log_print")` 解析日志函数，然后打印 `hello <data> pid=<pid>`。

`--exec/-x` 命令执行模式见 `docs/code_only_exec_injection.md`。`--commercial-wrapper` PUBG/UE4 扫描模式见 `docs/code_only_commercial_wrapper_injection.md`。hello 模式、exec 模式和 commercial-wrapper 模式互斥，避免同一次注入里混合多种 payload 语义。

## 使用示例

```bash
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
adb push build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject /data/local/tmp/frida-code-inject
adb shell chmod 755 /data/local/tmp/frida-code-inject
PID="$(adb shell pidof com.miui.notes | tr -d '\r')"
adb shell su -c "/data/local/tmp/frida-code-inject -p ${PID} -d nihao"
adb logcat -s HELLO_INJECT
```

预期日志：

```text
HELLO_INJECT: hello nihao pid=<notes pid>
```

## 验证关注点

- `file build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject` 应为 Android arm64 ELF。
- `frida/subprojects/frida-core/src/linux/helpers/artifacts/native/arm64/code-hello.bin` 是 raw data，不是 ELF shared object。
- 注入前后采集目标进程 `maps`、`fd`、`task`，确认没有 `/data/local/tmp/libhello_inject.so` 这类用户 payload `.so` 映射。
- `pid` 不存在、权限不足时应返回非 0 并打印错误。

## 2026-06-22 真机验证

设备：`192.168.31.10:5555`，`Mi_10_Pro`。目标：`com.miui.notes`，pid `31127`。SELinux：`Enforcing`。

构建与产物：

```text
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject: ELF 64-bit LSB shared object, ARM aarch64, interpreter /system/bin/linker64, for Android 21
frida/subprojects/frida-core/src/linux/helpers/artifacts/native/arm64/code-hello.bin: data
```

执行：

```text
adb shell su -c "/data/local/tmp/frida-code-inject -p 31127 -d nihao"
injected code pid=31127
```

logcat：

```text
06-22 18:39:21.350 31127 31127 I HELLO_INJECT: hello nihao pid=31127
```

运行态基线：

```text
before maps lines=2360 fd=93 task=19
after maps lines=2360 fd=93 task=19
payload map grep after: <empty>
```

原始观察文件位于 `tmp/code_inject_runtime/`，包含注入前后的 `maps`、`fd`、`task` 和 `logcat` 输出。注入后 `maps` 未出现 `libhello_inject`、`frida-code-inject` 或 `code-hello`。

失败场景：

```text
/data/local/tmp/frida-code-inject --version -> 17.9.11-dev.5, exit 0
/data/local/tmp/frida-code-inject -p 999999 -d nihao -> Process not found, exit 3
/data/local/tmp/frida-code-inject -d nihao -> PID must be specified and greater than zero, exit 2
```
