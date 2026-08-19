# 复现用 patch 清单

| 文件 | 应用目录 | 作用 |
|---|---|---|
| `001-frida-core-gadget-bisect.patch` | `frida/subprojects/frida-core` | Gadget 二分停止点和 worker 线程名 |
| `002-glib-gio-thread-name-and-gtask-bisect.patch` | `frida/subprojects/glib` | GLib/GIO 线程名与 GTask 二分点 |
| `003-project-build-temporary-sdk-patch.patch` | 历史记录 | 旧项目构建入口记录；当前复现使用 `files/scripts/` 中的版本化脚本 |
| `004-project-thread-name-patcher-script.patch` | 历史记录 | 线程名修补脚本记录；当前由 `files/scripts/修补_ms线程名.py` 安装 |
| `005-frida-server-group-stop-inject.patch` | `frida/subprojects/frida-core` | Android 注入线程暂停窗口 |
| `006-frida-gum-runtime-and-pretty-method.patch` | `frida/subprojects/frida-gum` | Gum scheduler、ELF、ARM64 interceptor 修改 |
| `007-frida-core-agent-memfd-name-msagent.patch` | `frida/subprojects/frida-core` | agent memfd 显示名修改，含最终作用域布局 |
| `008-frida-core-helper-injection.patch` | `frida/subprojects/frida-core` | `code-*` helper、inject 目标及资源打包 |
| `009-glib-descriptive-thread-name.patch` | `frida/subprojects/glib` | 默认方案 A：统一逻辑线程名为 `Jit thread pool worker thread N`，Android/Linux OS 层保留前 15 个字符 |
| `010-frida-gum-descriptive-thread-name.patch` | `frida/subprojects/frida-gum` | Gum Linux 直接 pthread worker 接入统一命名注册表，并优先返回完整逻辑名 |
| `011-frida-core-loader-descriptive-thread-name.patch` | `frida/subprojects/frida-core` | 远程 Linux loader 使用方案 A 的 OS 可见前缀 |
| `012-frida-core-android-helper-descriptive-thread-name.patch` | `frida/subprojects/frida-core` | Android helper 的 Java listener/handler 使用 `Jit thread pool` OS 名，并按 TID 保存完整逻辑名 |

`008` 之外的 ARM64 helper payload 位于 `../files/frida-core/`，脚本会复制到精确的 `frida-core/src/linux/helpers/artifacts/native/arm64/` 路径。多架构连续构建后应最后重新构建 ARM64。

`012` 的 `Helper.java` 修改需要重新生成架构无关的 `frida-core/src/android-helper/helper.dex`；`files/frida-core/src/android-helper/helper.dex` 提供已审计的方案 A fallback，`files/scripts/build_android_helper.sh` 在工具链完整时优先重新编译。

`003` 和 `004` 保留为历史 patch 记录，但它们的旧文件名/项目路径不适合直接应用到官方 17.15.3 checkout。`scripts/apply_patches.sh` 使用当前版本的构建脚本 overlay，避免误把旧 patch 应用到错误目录。

所有源码 patch 都先执行 `git apply --check`，检查通过后才应用。
