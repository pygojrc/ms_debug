# frida-code-inject code-only exec 注入记录

## 结论

`frida-code-inject` 已新增 `--exec/-x <command>` 模式。该模式不连接 `frida-server`，不运行 JS，不加载用户 `.so`，而是把内置 `code-exec.bin` raw payload 写入目标进程匿名可执行内存并调用。

payload 在目标进程中解析 libc 的 `fork`、`setsid`、`execve`、`_exit`，fork 后由子进程执行：

```text
/system/bin/sh -c <command>
```

父 payload 立即返回，injector 随即退出；命令是否成功需要通过输出文件、`ps`、`ss`、`logcat` 或服务端口验证。

## 实现要点

- `src/linux/helpers/code-exec.c`：新增 raw exec payload。
- `src/linux/helpers/meson.build`：生成 `code-exec.bin`，与 `code-hello.bin` 使用同类 raw payload 构建路径。
- `src/meson.build`：把 arm64 `code-exec.bin` 打进 helper backend 资源。
- `src/linux/frida-helper-backend.vala`：新增 `inject_exec_code(pid, command)`。
- `inject/code-inject.vala`：新增 `--exec/-x` 参数，并与 `--data/-d` 互斥。

## 使用示例

```bash
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
adb push build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject /data/local/tmp/frida-code-inject
adb shell chmod 755 /data/local/tmp/frida-code-inject

PID="$(adb shell pidof com.miui.notes | tr -d '\r')"
adb shell su -c "/data/local/tmp/frida-code-inject -p ${PID} --exec '/system/bin/log -t CODE_EXEC_TEST exec_ok'"
adb logcat -s CODE_EXEC_TEST
```

预期包含：

```text
CODE_EXEC_TEST: exec_ok
```

## dropbear 与 linker64

在本机真机验证中，`/data/local/tmp/dropbear` 的文件标签是 `shell_data_file`，notes 的 `platform_app` 域不能直接执行，也不能让 linker mmap 该文件：

```text
sh: /data/local/tmp/dropbear: can't execute: Permission denied
error: "/data/local/tmp/dropbear" phdr mmap failed: Permission denied
```

可用路径是把 dropbear 放到 notes app data，并设置成目标 app uid 与 app data SELinux 标签：

```bash
adb push /data/projects/Zygisk/K80Pro/build/dropbear-android-arm64/dropbear /data/local/tmp/dropbear
adb shell su -c 'cp /data/local/tmp/dropbear /data/data/com.miui.notes/files/dropbear'
adb shell su -c 'chown u0_a259:u0_a259 /data/data/com.miui.notes/files/dropbear'
adb shell su -c 'chmod 755 /data/data/com.miui.notes/files/dropbear'
adb shell su -c 'chcon u:object_r:app_data_file:s0:c512,c768 /data/data/com.miui.notes/files/dropbear'
```

然后通过 `linker64` 启动：

```bash
PID="$(adb shell pidof com.miui.notes | tr -d '\r')"
adb shell "su -c '/data/local/tmp/frida-code-inject -p ${PID} --exec \"/system/bin/linker64 /data/data/com.miui.notes/files/dropbear -R -p 0.0.0.0:10099 -P /data/data/com.miui.notes/files/dropbear_10099.pid\"'"
adb shell su -c 'ss -ltnp | grep 10099'
```

本次验证成功监听：

```text
LISTEN 0 128 0.0.0.0:10099 0.0.0.0:* users:(("linker64",pid=28692,fd=3))
linker64 /data/data/com.miui.notes/files/dropbear -R -p 0.0.0.0:10099 -P /data/data/com.miui.notes/files/dropbear_10099.pid
```

注意：`u0_a259`、`c512,c768`、notes pid 和监听 pid 都是本次设备的实测值；换目标 app 时应按实际 `ps -A -o USER,LABEL,ARGS` 和文件标签调整。

## 2026-06-22 真机验证

设备：`192.168.31.10:5555`，`Mi_10_Pro`。目标：`com.miui.notes`，pid `31127`。SELinux：`Enforcing`。

构建与产物：

```text
FRIDA_TARGET=frida-code-inject bash scripts/run_podman.sh
build/frida-android-arm64/subprojects/frida-core/inject/frida-code-inject: ELF 64-bit LSB shared object, ARM aarch64, interpreter /system/bin/linker64, for Android 21
frida/subprojects/frida-core/src/linux/helpers/artifacts/native/arm64/code-exec.bin: data, 456 bytes
```

最小命令执行：

```text
adb shell su -c '/data/local/tmp/frida-code-inject -p 31127 --exec "/system/bin/log -t CODE_EXEC_TEST exec_ok"'
executed command pid=31127
06-22 18:46:10.848 28330 28330 I CODE_EXEC_TEST: exec_ok
```

目标权限上下文：

```text
adb shell su -c '/data/local/tmp/frida-code-inject -p 31127 --exec "id | /system/bin/log -t CODE_EXEC_ID"'
executed command pid=31127
uid=10259(u0_a259) gid=10259(u0_a259) groups=10259(u0_a259),1077(external_storage),3001(net_bt_admin),3002(net_bt),3003(inet),9997(everybody),20259(u0_a259_cache),50259(all_a259) context=u:r:platform_app:s0:c512,c768
```

运行态基线：

```text
before maps lines=2396 fd=93 task=24
after maps lines=2403 fd=93 task=25
payload map grep after: <empty>
```

`maps` 中未出现 `libhello_inject`、`frida-code-inject`、`code-exec`、`code-hello`。允许存在短暂 ptrace、远程调用、匿名可执行内存和 fork 出来的子进程行为。

失败场景：

```text
/data/local/tmp/frida-code-inject --version -> 17.9.11-dev.5, exit 0
/data/local/tmp/frida-code-inject -p 999999 --exec "id" -> Process not found, exit 3
/data/local/tmp/frida-code-inject -p 31127 -d nihao --exec id -> --data and --exec are mutually exclusive, exit 6
/data/local/tmp/frida-code-inject -p 31127 --exec "" -> Command must not be empty, exit 7
```
