# 编译结果对比

| 项目 | 结果 |
|---|---|
| 文件清单 |  |

## 逐文件分析

| 文件 | 类型/架构 | ELF 动态依赖 | 符号差异 | 内容哈希 | 综合判断 |
|---|---|---|---|---|---|
| `android-arm64/libfrida-gum-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `67f1f8832da33215351e74dae63df267fdd304ff4082e97c2bdc7244d90d8a67` / `67f1f8832da33215351e74dae63df267fdd304ff4082e97c2bdc7244d90d8a67` | `2438f4557423` / `4d3eea3c9113` | 内容相同 |
| `android-arm64/libfrida-gumjs-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `53403c972eca5096f1fc144034feb0f08864c07241ba79617452f59ba4c472f6` / `53403c972eca5096f1fc144034feb0f08864c07241ba79617452f59ba4c472f6` | `ede062f37ba5` / `71b5c1349ace` | 内容相同 |
| `android-arm64/ms_server` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `f19aebbec45a` / `f19aebbec45a` | 完全一致 |
| `android-x86/libfrida-gum-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `a8d4135267c997b4ad052dd9121c75be628a1c6d9c4c3a1c0a5f1ee16de83852` / `a8d4135267c997b4ad052dd9121c75be628a1c6d9c4c3a1c0a5f1ee16de83852` | `31377b63298a` / `5671260f9da5` | 内容相同 |
| `android-x86/libfrida-gumjs-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `2d2b77b87356587677e51d894eef5b697d5acf2419440864161f49b6930e50f9` / `2d2b77b87356587677e51d894eef5b697d5acf2419440864161f49b6930e50f9` | `3ece0f906104` / `dc4d688cea85` | 内容相同 |
| `android-x86/ms_server` | `ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped` / `ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `50cf33fa2cce` / `abf188b95773` | 内容相同 |
| `android-x86_64/libfrida-gum-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `a8d4135267c997b4ad052dd9121c75be628a1c6d9c4c3a1c0a5f1ee16de83852` / `a8d4135267c997b4ad052dd9121c75be628a1c6d9c4c3a1c0a5f1ee16de83852` | `ff61dc00780e` / `451ab8347ec4` | 内容相同 |
| `android-x86_64/libfrida-gumjs-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `0d0603687522c7c3b69e6f14d22474cc30ff4418427f39232f98bb0fc84ae1c8` / `0d0603687522c7c3b69e6f14d22474cc30ff4418427f39232f98bb0fc84ae1c8` | `64f4cc25b898` / `e5fa18cef90a` | 内容相同 |
| `android-x86_64/ms_server` | `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `8e5c446d7680` / `c4b7e1d38e12` | 内容相同 |

## 判定原则

- 哈希仅用于确认完全一致，不作为唯一判定。
- 优先比较文件清单、文件类型、架构、ELF 依赖和导出符号。
- 对 ABI/符号一致但哈希不同的产物，继续检查 Build ID、编译路径、时间戳、debug 信息等可变字段。
- 最终发布前还应执行 frida-server 启动、客户端连接和最小注入行为测试。
