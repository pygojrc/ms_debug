# 从官方 Frida 17.15.3 复现 `ms_debug`

本目录用于从官方 `frida/frida` 的 `17.15.3` tag、递归子模块源码开始，应用 `ms_debug` 的源码 patch 和构建辅助文件，编译出与 `ms_debug/frida` 相同目标的产物。

源码实际按 `config/versions.env` 中的不可变 root commit checkout，而不是信任可移动 tag。源码树和构建依赖分析见 [`FRIDA-17.15.3-SOURCE-AND-DEPENDENCIES.md`](FRIDA-17.15.3-SOURCE-AND-DEPENDENCIES.md)。

统一线程命名方案见 [`THREAD-NAMING-DESIGN.md`](THREAD-NAMING-DESIGN.md)：默认严格采用 `Jit thread pool worker thread N`，Android/Linux OS 层仅保留前 15 个可见字符 `Jit thread pool`；另设计了默认关闭的 `ms-tN` 紧凑方案。

Patch 后线程名覆盖复核见 [`THREAD-NAMES-AUDIT-AFTER-PATCHES.md`](THREAD-NAMES-AUDIT-AFTER-PATCHES.md)。

## 快速开始

```bash
cd ms_debug/ms_from_frida
bash scripts/build_ms_debug.sh
```

默认自动准备 Android NDK r29，并同时编译 `android-arm64` 和 `android-x86_64` 的 `frida-server`。两个目标使用独立的 SDK、Meson build 目录和产物目录。可覆盖：

```bash
FRIDA_TARGET=frida-inject bash scripts/build_ms_debug.sh
FRIDA_HOSTS=android-arm64 FRIDA_TARGET=frida-gadget bash scripts/build_ms_debug.sh
FRIDA_HOSTS='android-arm64 android-x86_64' FRIDA_TARGET=frida-server bash scripts/build_ms_debug.sh
```

脚本会下载 `17.15.3`、递归初始化子模块，额外 checkout 被 `ms_debug` vendored 的 GLib/libffi/libiconv/termux-elf-cleaner，调用 Frida 的 `releng/deps.py` 下载 Android SDK 静态库和 Linux host toolchain，并默认使用 `deps.py --only=glib` 从固定源码重新构建 GLib/GObject/GIO，再覆盖到完整 SDK。这样 `002-glib...patch` 和方案 A 的 `009-glib...patch` 直接进入 GLib 编译结果，`010`、`011` 接入 Gum/loader，构建阶段不再编辑 `libglib-2.0.a`/`libgio-2.0.a`；设置 `FRIDA_BUILD_GLIB=0` 才回退到旧的预编译 `.a` 临时修补方案，同时跳过依赖自构建专用的 `009/010`。脚本还会校验主仓库 commit、应用其它子模块 patch，并安装构建辅助脚本。

如只想准备源码而暂时不下载预构建依赖，可设置：

```bash
FRIDA_DOWNLOAD_PREBUILT=0 bash scripts/fetch_frida.sh
```

如 NDK 已由外部环境提供，可设置 `ANDROID_NDK_ROOT=/path/to/android-ndk-r29`；如只测试现有 NDK 而不自动下载，设置 `FRIDA_DOWNLOAD_NDK=0`。

## Patch 目标

`001`、`005`、`007`、`008` 应用到 `frida/subprojects/frida-core`；`002` 应用到 `frida/subprojects/glib`；`006` 应用到 `frida/subprojects/frida-gum`。`008` 补充 `ms_debug` 独有的注入 helper 源码和构建集成；其配套 ARM64 二进制 payload 位于 `files/frida-core/`，由脚本复制。不同子模块的 patch 不能从 Frida 根目录直接一次性 `git apply`。

构建辅助脚本放在 `files/scripts/`，由 `scripts/apply_patches.sh` 安装到下载后的 Frida 根目录。它们负责 Android 构建、产物复制和 `.a` 临时线程名修补。

Android helper 的 `Helper.java` 由独立 `012-frida-core-android-helper-descriptive-thread-name.patch` 修改。主构建会先调用 `build_android_helper.sh` 重建架构无关的 `helper.dex`，需要 `ANDROID_SDK_ROOT/platforms/android-19/android.jar`、JDK 的 `javac/jar` 和 Android build-tools 的 `d8`；可用 `ANDROID_HELPER_API_LEVEL` 选择其它已安装 API。
`files/frida-core/src/android-helper/helper.dex` 同时保存了一份已经通过字符串审计的方案 A Dex，适合没有 Java/Android SDK 的 Frida x-tools workflow；脚本只在确认其中包含新逻辑名且不含旧 helper 名时使用它，工具链完整时仍会重新编译。

已下载并纳入对比的 GitHub Release 参考文件位于 `reference/release/`；其中 `ms_server.android-arm64` 与 `ms_server.android-x86_64` 用于和源码复现结果做同架构 ELF/ABI/符号对比。

## 结果判定

使用：

```bash
bash scripts/compare_outputs.sh <ms_debug产物目录> <复现产物目录> reports/compare-report.md
```

对比不把哈希作为唯一条件，而是综合文件清单、文件类型、架构、ELF 动态依赖、导出符号、静态库成员、可变构建字段和运行时行为。详见 `ANALYSIS.md`。
