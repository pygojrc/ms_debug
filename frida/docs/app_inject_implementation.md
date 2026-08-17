# app_inject 实现与验证

## 实现内容

- `app_inject/inject_so.py`：通用 so 注入 CLI，调用 Frida Python `Device.inject_library_file()`。
- `app_inject/hello_payload/src/hello_inject.cpp`：Android hello payload，导出 `hello_entry()`，打印 `hello <data> pid=<pid>`。
- `app_inject/hello_payload/CMakeLists.txt`：最小 Android so 构建配置。
- `app_inject/scripts/build_hello_payload.sh`：构建脚本，默认使用 `/data/opt/android-ndk-r29`。
- `app_inject/README.md`：构建、推送、注入和 logcat 示例。
- `frida/subprojects/frida-core/inject/so-inject.vala`：不依赖 frida-server 的本地 native so 注入 CLI，读取 `--library` 文件为 blob 后调用 Frida `Injector.inject_library_blob()`。

## 验证结果

已完成：

```bash
app_inject/inject_so.py --help
bash app_inject/scripts/build_hello_payload.sh --help
app_inject/inject_so.py --remote 127.0.0.1:27056 --target 12345 --library /data/local/tmp/libhello_inject.so --dry-run
bash app_inject/scripts/build_hello_payload.sh
git diff --check
```

新增 `frida-so-inject` 后已验证：

```bash
FRIDA_TARGET=frida-so-inject bash scripts/run_podman.sh
file build/frida-android-arm64/subprojects/frida-core/inject/frida-so-inject
```

真机 notes 验证已完成：

```bash
adb shell su -c '/data/local/tmp/frida-so-inject -p 31127 -l /data/local/tmp/libhello_inject.so -e hello_entry -d nihao'
adb logcat -s HELLO_INJECT
```

关键输出：

```text
injected id=1
HELLO_INJECT(31127): hello nihao pid=31127
```

构建产物：

```text
build/app_inject/hello_payload/out/libhello_inject.so
```

已执行真机注入验证，目标为 `com.miui.notes`。该路径不需要启动 frida-server。
