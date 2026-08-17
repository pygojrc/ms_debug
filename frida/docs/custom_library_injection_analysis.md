# frida-server 通用 so 注入抽取分析

## 结论

可以抽取，而且 frida-core 已经把这层能力抽象成 `Frida.Injector`。

当前 frida-server 注入 agent 的底层不是只能加载 `frida-agent.so`，而是通用的：

1. 选择目标 pid。
2. 把任意 so 文件或 blob 传给 Linux/Android 注入器。
3. 在目标进程中 `dlopen()` 这个 so。
4. `dlsym()` 查找调用方指定的入口函数。
5. 按固定 ABI 调用入口函数。

入口函数签名需要兼容：

```c
void entrypoint(const char *data, int *unload_policy, void *injector_state);
```

因此可以做一个独立 CLI，例如 `frida-so-inject`，参数为：

```text
frida-so-inject -p <pid> -l /data/local/tmp/libhello_inject.so -e hello_entry -d "nihao"
```

## 源码依据

- `frida/subprojects/frida-core/src/frida.vala`：`Injector` 接口明确是 agent injection 下层的 shared library injection primitive，公开 `inject_library_file()` 和 `inject_library_blob()`。
- `frida/subprojects/frida-core/src/linux/linjector.vala`：Linux/Android 路径把 path/blob 转为 `UnixInputStream`，再传入 helper 的 `inject_library()`。
- `frida/subprojects/frida-core/src/linux/frida-helper-backend.vala`：`InjectSpec` 保存 `entrypoint` 和 `data`，loader 布局中会写入入口名和数据字符串。
- `frida/subprojects/frida-core/src/linux/helpers/loader.c`：目标进程内 loader 接收 so fd，通过 `/proc/<pid>/fd/<fd>` 执行 `dlopen()`，再用 `dlsym()` 查找入口并调用。

## hello world so 形态

最小 Android so 可以只导出一个入口，调用 logcat：

```c
#include <android/log.h>

__attribute__((visibility("default")))
void hello_entry(const char *data, int *unload_policy, void *injector_state) {
  __android_log_print(ANDROID_LOG_INFO, "HELLO_INJECT", "hello %s", data != 0 ? data : "nihao");

  if (unload_policy != 0)
    *unload_policy = 0;
}
```

`unload_policy = 0` 对应当前 loader 默认的 immediate 语义，适合一次性打印后让注入线程结束。

## 推荐实现路径

优先新增一个很薄的工具，而不是复制底层 ptrace/loader 代码：

1. 复用 `Frida.Injector.new()`。
2. 解析 `--pid --library --entrypoint --data`。
3. 读取 `library` 为 blob，调用 `inject_library_blob(pid, blob, entrypoint, data)`；这样 Android 目标进程不需要直接 mmap `/data/local/tmp` 的 `shell_data_file`。
4. `close_sync()` 清理 helper。
5. 单独提供 `hello_entry` 的 Android NDK 构建脚本和 adb/logcat 验证脚本。

这样后续注入其它程序只需要换 so、入口名和 data，不需要再改 frida-agent。

## 验证建议

1. 编译 `frida-server` 或新增的 `frida-so-inject`。
2. 编译 `libhello_inject.so`，推送到 `/data/local/tmp/`。
3. 启动目标 hello world Android 程序并取得 pid。
4. 执行注入命令。
5. 用 `adb logcat -s HELLO_INJECT` 验证出现 `hello nihao`。

## code-only hello 的边界

如果目标是不在进程 maps 中留下用户 `.so` 文件映射，应使用 `frida-code-inject` 这类 raw payload 注入路径，而不是从普通 NDK `.so` 直接提取 `.text`。

普通 `.so` 的 `.text` 通常依赖 `.got`、`.plt`、`.rela.dyn`、`.rela.plt` 和动态符号，例如 `__android_log_print`、`getpid` 等。直接把 `.text` 写入目标进程执行会缺少 relocation 和外部符号解析，不能作为稳定方案。

当前 v1 的 code-only 方案固定为 Android arm64 内置 hello payload：构建时生成 `code-hello.bin`，运行时由 `frida-code-inject -p <pid> -d nihao` 写入匿名可执行内存并调用。它不支持任意 `.so` 转 raw code。
