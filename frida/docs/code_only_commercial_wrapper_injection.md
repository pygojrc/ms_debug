# frida-code-inject code-only commercial wrapper 注入记录

## 结论

`frida-code-inject` 已新增 `--commercial-wrapper` 模式，用 raw C payload 移植 `/data/projects/Local/local_analyze/mock_pubg/native/commercial_wrapper_logger` 的核心扫描逻辑。该模式不连接 `frida-server`，不运行 JS，不加载 `libcommercial_wrapper_logger.so`。

payload 面向当前 PUBG/UE4 arm64 目标，硬编码扫描：

```text
libUE4.so
GNamesSlot = 0x14e33c18
UWorldSlot = 0x15772758
CurrentLevel = 0x0b0 / 0x0b00
Actors = ULevel + 0x0a0
BP_CommercialWrapper / BP_CommercialWrapper_LV4_C
```

## 实现要点

- 新增 `code-commercial-wrapper.bin`，通过 `.payload` 链接脚本和 `objcopy -O binary -j .payload` 生成。
- CLI 新增 `--commercial-wrapper`，与 `--data`、`--exec` 互斥。
- backend 新增 `inject_commercial_wrapper_code()`，只在 arm64 下启用。
- payload 用 C 固定数组和 `mmap` 工作区替代 C++ STL，不使用原 `.so` 的 constructor/relocation。
- commercial-wrapper 模式同步执行：payload 入口在当前 remote call 中直接扫描，最多等待 3 秒；完成或超时后返回，helper 释放匿名 code mapping。

## 使用示例

```bash
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
adb push build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject /data/local/tmp/frida-code-inject
adb shell chmod 755 /data/local/tmp/frida-code-inject

PID="$(adb shell pidof com.tencent.tmgp.pubgmhd | tr -d '\r' | awk '{print $1}')"
adb shell su -c "/data/local/tmp/frida-code-inject -p ${PID} --commercial-wrapper"
adb logcat -s CommercialWrapperLogger
```

预期在 `libUE4.so` 已加载时包含：

```text
CommercialWrapperLogger: raw payload started
CommercialWrapperLogger: libUE4 base=...
CommercialWrapperLogger: scan actorsNum=... matched=... focus=BP_CommercialWrapper_LV4_C count=...
CommercialWrapperLogger: - class=BP_CommercialWrapper... count=...
CommercialWrapperLogger: * i=... class=BP_CommercialWrapper_LV4_C actor=... loc=(..., ..., ...)m
```

如果目标进程尚未加载 `libUE4.so`，payload 会每秒打印 `waiting for libUE4.so`，3 秒后打印超时。

## 2026-06-22 真机验证

设备：`192.168.31.10:5555`，`Mi 10 Pro`，SELinux：`Enforcing`。目标包：`com.tencent.tmgp.pubgmhd`。

构建与产物：

```text
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject: ELF 64-bit LSB shared object, ARM aarch64, interpreter /system/bin/linker64, for Android 21
frida/subprojects/frida-core/src/linux/helpers/artifacts/native/arm64/code-commercial-wrapper.bin: data, 4484 bytes
```

CLI 验证：

```text
/data/local/tmp/frida-code-inject --help -> 包含 --commercial-wrapper
/data/local/tmp/frida-code-inject -p 2012 -d x --commercial-wrapper -> --data, --exec, and --commercial-wrapper are mutually exclusive, exit 6
```

注入验证：

```text
pid=6379
adb shell su -c '/data/local/tmp/frida-code-inject -p 6379 --commercial-wrapper'
injected commercial-wrapper pid=6379
```

logcat：

```text
06-22 21:24:09.210  6379  6379 I CommercialWrapperLogger: raw payload thread started
06-22 21:24:09.227  6379  6504 W CommercialWrapperLogger: waiting for libUE4.so
...
06-22 21:24:55.066  6379  6504 E CommercialWrapperLogger: scan timeout after 45 seconds
```

本轮 pid `6379` 的 maps 中没有 `libUE4.so`，因此未进入 actor 扫描阶段。注入前后观察：

```text
before maps=2408 fd=85 task=21
after  maps=2400 fd=85 task=20
payload map grep after: <empty for libcommercial_wrapper_logger/code-commercial-wrapper/frida-code-inject/CommercialWrapper/libUE4.so>
```

此前 45 秒同步等待版本曾在 pid `2012` 上触发 `Unexpectedly timed out while waiting for stop from process with PID 2012`；当前版本已改为同步执行但只等待 3 秒，避免 remote call 长时间等待。

## 边界

- v1 只支持 Android arm64 和当前偏移。
- 不加载原 `libcommercial_wrapper_logger.so`，不处理 ELF relocation/C++ constructor。
- commercial-wrapper 模式完成或超时后会释放匿名 code mapping。
- 目标必须已加载或在 3 秒内加载 `libUE4.so` 才能输出 actor 扫描结果。
