# 编译结果对比

| 项目 | 结果 |
|---|---|
| 文件清单 |  |

## 逐文件分析

| 文件 | 类型/架构 | ELF 动态依赖 | 符号差异 | 内容哈希 | 综合判断 |
|---|---|---|---|---|---|
| `libfrida-gum-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `67f1f8832da33215351e74dae63df267fdd304ff4082e97c2bdc7244d90d8a67` / `67f1f8832da33215351e74dae63df267fdd304ff4082e97c2bdc7244d90d8a67` | `2438f4557423` / `4d3eea3c9113` | 结构/ABI等价，内容不同 |
| `libfrida-gumjs-1.0.a` | `current ar archive` / `current ar archive` | `` / `` | `53403c972eca5096f1fc144034feb0f08864c07241ba79617452f59ba4c472f6` / `53403c972eca5096f1fc144034feb0f08864c07241ba79617452f59ba4c472f6` | `ede062f37ba5` / `71b5c1349ace` | 结构/ABI等价，内容不同 |
| `ms_server` | `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` / `ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /system/bin/linker64, stripped` | `libc.so,libdl.so,liblog.so,libm.so,` / `libc.so,libdl.so,liblog.so,libm.so,` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` / `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `f19aebbec45a` / `f19aebbec45a` | 完全一致 |

## 判定原则

- 哈希仅用于确认完全一致，不作为唯一判定。
- 优先比较文件清单、文件类型、架构、ELF 依赖和导出符号。
- 对 ABI/符号一致但哈希不同的产物，继续检查 Build ID、编译路径、时间戳、debug 信息等可变字段。
- 最终发布前还应执行 frida-server 启动、客户端连接和最小注入行为测试。
