# CI Release 验证

## 构建记录

- Workflow: `ms_from_frida build and release`
- Run: [32215216898](https://github.com/pygojrc/ms_debug/actions/runs/32215216898)
- 提交: `4888a4f1761dd6a5fac7b7e11a50d54a7ab8b82e`
- 结果: `success`
- 构建矩阵: Android `arm64`、`x86_64`
- Release: [17.15.3](https://github.com/pygojrc/ms_debug/releases/tag/17.15.3)
- 本地下载目录: `ms_from_frida/reference/ci-release/`

## 资产核对

下表将本次 CI Release 与本地保存的 `reference/release/` 资产对比。SHA-256 仅作为字节级一致性指标；最终结论同时考虑 ELF 类型、机器架构、动态依赖、段/节布局和导出符号。

| 资产 | CI 大小 | 参考大小 | ELF 架构 | NEEDED 集合 | SHA 是否相同 | 结论 |
|---|---:|---:|---|---|---|---|
| `ms_server.android-arm64` | 53,513,920 | 53,513,920 | AArch64 | libc/libdl/liblog/libm | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `ms_server.android-x86_64` | 111,504,480 | 111,504,480 | x86-64 | libc/libdl/liblog/libm | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `gadget.so.android-arm64` | 25,208,560 | 25,208,560 | AArch64 | libc/libdl/liblog/libm；SONAME 一致 | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `gadget.so.android-x86_64` | 26,561,752 | 26,561,752 | x86-64 | libc/libdl/liblog/libm；SONAME 一致 | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `frida-code-inject.android-arm64` | 7,963,376 | 7,963,376 | AArch64 | libc/libdl/liblog/libm | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `frida-code-inject.android-x86_64` | 9,297,952 | 9,297,952 | x86-64 | libc/libdl/liblog/libm | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `frida-so-inject.android-arm64` | 11,368,680 | 11,368,680 | AArch64 | libc/libdl/liblog/libm | 否 | ELF/ABI 外形一致，内容有可复现性差异 |
| `frida-so-inject.android-x86_64` | 15,378,016 | 15,373,920 | x86-64 | libc/libdl/liblog/libm | 否 | 架构/依赖一致；大小有 4,096 字节差异，需保留行为回归关注 |

## 判定

1. 8 个 Release 资产均已下载；workflow 的两个矩阵 job 均通过构建、验证和 artifact 上传。
2. 所有文件都是预期的 Android 动态 ELF，架构与文件名匹配，动态依赖集合一致；`gadget` 的 SONAME 也一致。
3. 所有资产 SHA-256 不同，不能据此判定功能不同。当前文件已 stripped，`nm -g --defined-only` 得到的导出符号集合为空，不能把“空符号集合相同”当作充分证明。
4. 参考资产与 CI 资产的差异主要应通过 ELF 头、Program Header、动态段、节布局、字符串/符号以及运行时行为判断。当前静态核对未发现架构或动态链接接口不一致；`frida-so-inject.android-x86_64` 的 4 KiB 大小差异应在设备上做实际注入回归。

## 后续建议

- 在 x86_64 和 arm64 Android 设备/模拟器上分别启动 `ms_server`，用对应 Frida 客户端枚举进程并执行最小脚本。
- 对 `gadget.so` 做加载测试，对两个 inject 产物分别做 code injection 和 so injection 测试。
- 若要求可复现字节级产物，应固定容器 digest、NDK/toolchain 版本、源码依赖版本，并启用 reproducible-build 选项；否则以本报告的 ABI/依赖/行为判定为准。
