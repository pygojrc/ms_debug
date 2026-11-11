# Android `JNI_CreateJavaVM` 失败待处理计划

状态：待处理（本次仅记录计划，不触发构建）

## 现象

在 Android 设备上运行 `ms_server` 时，服务在启动 Android helper 阶段中止：

```text
Frida:ERROR:.../linux-host-session.vala:704:frida_android_helper_service_do_start:
assertion failed: (res == OK)
Bail out!
Aborted
```

重复启动得到相同结果。

## 当前定位

失败位置是 `frida-core/src/linux/linux-host-session.vala` 中的：

```vala
var res = create_java_vm (out vm, out env, args);
assert (res == OK);
```

该位置发生在 `HelperBackend` 类加载、`Helper.java` 线程创建和线程命名之前。因此，当前错误不能直接归因于：

- `Jit thread pool worker thread N` 命名方案；
- `g_set_prgname("gogogo")`；
- `PrettyMethod` 修改；
- `MYOBS` 调试日志开关；
- `Helper.java` worker 线程实现。

`JNI_CreateJavaVM` 的返回值目前被断言吞掉，必须先取得具体返回码以及 ART 的 logcat 信息。AOSP 实现中，JNI 版本错误返回 `JNI_EVERSION`，ART runtime 创建或启动失败返回 `JNI_ERR`。

## 待处理步骤

### 1. 采集设备环境

在设备上执行：

```sh
getprop ro.build.version.sdk
getprop ro.product.cpu.abilist
uname -m
id
getenforce
```

确认 Android API、设备 ABI、运行身份和 SELinux 状态。

### 2. 采集 ART/JNI 原因

```sh
logcat -c
./ms_server 2>&1 | tee /data/local/tmp/ms_server.log
logcat -d -b all -v threadtime | grep -iE \
  'art|runtime|jni|nativeloader|dex|classloader|frida|ms_server'
```

重点检查 `Runtime::Create`、`Runtime::Start`、native loader、Dex/classpath 和 SELinux 相关错误。

### 3. 检查 helper DEX

```sh
ls -l /data/local/tmp/frida-helper-*.dex 2>/dev/null
```

确认 helper DEX 已生成、可读，并且与当前 native `ms_server` 使用同一份源码快照生成。若进程异常退出遗留旧文件，清理后重试：

```sh
rm -f /data/local/tmp/frida-helper-*.dex
```

### 4. 临时输出 JNI 返回码

若 logcat 不能确定原因，将断言改为错误传播或显式日志，例如：

```vala
if (res != OK)
    throw new Error.FAILED ("JNI_CreateJavaVM failed: %d", res);
```

建议保留原始返回值，不要直接绕过断言或强制继续执行。

### 5. 分层验证

按以下顺序验证，避免把 VM 初始化问题误判为线程命名或 helper 类加载问题：

1. 原始 Frida 17.15.3、同一设备、同一启动方式；
2. 当前 patch 但使用原始 `helper.dex`；
3. 当前 patch 与当前生成的 `helper.dex` 配套版本；
4. 确认 `JNI_CreateJavaVM` 成功后，再检查 `registerFrameworkNatives`、`find_class` 和 `HelperBackend` 初始化。

## 完成判定

- `ms_server` 不再在 `linux-host-session.vala:704` 中止；
- logcat 中没有 ART runtime/native loader 初始化错误；
- helper 服务能够完成启动并响应一次 Android helper 请求；
- `g_set_prgname("gogogo")`、`PrettyMethod` 和目标线程命名行为仍然保留；
- ARM64 与 x86_64 Android 构建产物分别在匹配 ABI 的设备或 AVD 上完成启动验证。

## 当前决策

本问题暂不通过删除断言、绕过 `JNI_CreateJavaVM` 或修改线程命名逻辑解决。先记录返回码和 logcat，再决定是否需要针对 Android 16/API 36、ART namespace、helper DEX classpath 或构建产物配套关系增加修复 patch。
