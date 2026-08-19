# 缺失内容与复现分析

## 必须保留的内容

现有 `ms_debug/patchs/001..007` 覆盖了主要调试逻辑，但从官方 Frida 递归源码重新构建时还必须处理：

1. Patch 的目标子仓库路径；
2. `scripts/修补_ms线程名.py` 等新增构建辅助文件；
3. Android NDK r29、两个目标的 SDK 预构建依赖和 `deps/sdk-android-arm64/lib/`、`deps/sdk-android-x86_64/lib/`；SDK 依赖由 Frida `releng/deps.py sync sdk <host>` 下载，NDK 由 `download_ndk.sh` 下载；它们都不是 Git submodule；
4. 构建前临时修改 `libglib-2.0.a`、`libgio-2.0.a`，并在退出时恢复；
5. `build_android.sh` 的 host/target、Meson build root 和产物复制逻辑；
6. 子模块 commit 与 `ms_debug` vendored 源码版本的对应关系。

源码依赖和预构建依赖由两条路径获取：GLib 等需要打 patch 的依赖使用固定 commit 的 Git clone；PCRE2、zlib、SELinux、Vala、Ninja 等由官方 `releng/deps.py` 根据 `releng/deps.toml` 解析并下载对应 bundle/toolchain。

## 不能简单复制的全量 diff

`ms_debug` 把 Frida 主仓库及子模块作为普通文件提交，而官方仓库使用 Git submodule。全量 diff 因而包含大量子模块文件、测试数据、符号链接和版本布局差异。直接把全量 diff 当作一个根目录 patch，不能可靠复现 Git submodule 的 checkout 状态。

本目录采用“按子仓库应用源码 patch + 安装项目级构建文件”的方式，路径明确、可检查，也能避免把 `.git`、`.gitmodules` 或子模块元数据错误地写入源码。

## `.a` 的处理

`.a` 静态库没有作为源码文件提交；真正的修改发生在构建阶段。`build_android.sh` 在链接前对 SDK 中的 `libglib-2.0.a` 和 `libgio-2.0.a` 执行等长线程名替换，退出时反向恢复。因此复现脚本必须保证：

- 使用同一份 SDK 静态库；
- patch 操作具备 `--reverse`；
- 即使构建失败也通过 `trap` 恢复依赖；
- 不把已修改的 `.a` 作为下一次构建的输入。

## 编译结果异同判定

建议按以下层级判定：

| 层级 | 检查内容 | 作用 |
|---|---|---|
| L1 | 相对路径、文件数量、文件类型、权限 | 检查产物是否缺失或多出 |
| L2 | ELF 位数、架构、ABI、入口、SONAME | 检查目标平台是否一致 |
| L3 | NEEDED 动态库、RPATH/RUNPATH、导出/导入符号 | 检查 ABI 和链接结果 |
| L4 | 静态库成员列表、符号表、关键字符串 | 检查 `.a` 和关键修改是否进入产物 |
| L5 | Build ID、编译路径、时间戳、debug 信息 | 解释哈希不同的非功能原因 |
| L6 | `frida-server` 启动、连接、最小注入和 JavaScript API | 检查实际行为 |
| L7 | SHA-256 | 仅用于确认完全一致，不作为唯一结论 |

如果 L2～L4 和 L6 一致而 L7 不同，应判定为“功能/ABI 等价但二进制不完全相同”；只有所有层级均一致才判定为“完全一致”。未统一源码绝对路径时，生成对象会嵌入 `work/frida`、`reference/frida` 等路径，导致 x86_64 产物尺寸和哈希不同；这属于可解释的构建环境差异。

## 已识别的新增内容

| 位置 | 内容 | 处理方式 |
|---|---|---|
| `frida-core/inject/` | `code-inject.vala`、`so-inject.vala` 及 Meson 集成 | `008-frida-core-helper-injection.patch` |
| `frida-core/src/linux/helpers/` | `code-hello.c`、`code-exec.c`、`code-commercial-wrapper.c` | `008-frida-core-helper-injection.patch` |
| `frida-core/src/linux/` | helper backend、loader、inject-context、Meson 资源输入 | `008-frida-core-helper-injection.patch` |
| `frida-core/src/linux/linjector.vala` | memfd 显示名为 `msagent.so` 的最终布局 | `007-frida-core-agent-memfd-name-msagent.patch` |
| `frida-core/src/linux/helpers/artifacts/native/arm64/` | ARM64 helper payload 和三个 code payload | `files/frida-core/` 复制 overlay |
| SDK `lib/*.a` | GLib/GIO 线程名修补 | 构建前临时修补，退出恢复 |
