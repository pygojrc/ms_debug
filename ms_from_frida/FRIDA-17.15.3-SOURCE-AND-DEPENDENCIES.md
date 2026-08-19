# Frida 17.15.3 源码树与构建依赖

## 1. 不可变源码锁定

本项目不再把 tag 作为唯一源码标识。`scripts/fetch_frida.sh` 会直接 checkout 以下 root commit，并在源码准备后再次校验：

| 项目 | 固定值 |
|---|---|
| 上游仓库 | `https://github.com/frida/frida.git` |
| 人类可读版本 | `17.15.3` |
| Frida root commit | `831acfffc87483c4a1d665b9b6ae89e66bcefaa2` |
| frida-core | `e0ec2bee624b6ea11b72d5cc74639132449789c2` |
| frida-gum | `e5b0d7d6a9a83da1750b6fc654006a714b81a890` |
| GLib | `92d65736b198c2cf131f691dd83db0b25f7b02d2` |
| libffi | `c06a577933f07c76c3f536c9e4ba0f7d9c1e8c4d` |
| libiconv | `bbbf4561da4847bf95ce9458da76e072b77cabd1` |
| termux-elf-cleaner | `ab933ec128c6538067cdf3907ebbbc3bc35f1c55` |

root commit 会进一步锁定官方 Git submodule 的 tree。当前 17.15.3 源码树中的主要模块包括：`frida-core`、`frida-gum`、`frida-clr`、`frida-go`、`frida-node`、`frida-python`、`frida-qml`、`frida-swift`、`frida-tools`，以及 `releng/meson`、`releng/tomlkit`。Android 交叉编译实际启用的主链是 `frida-gum` → `frida-core`，其它语言绑定默认因 cross build 被关闭。

## 2. 源码树分层

| 路径 | 作用 | Android arm64/x86_64 构建关系 |
|---|---|---|
| `meson.build`、`meson.options` | 顶层工程和 feature 开关 | 选择 gum、core、gadget、server、inject |
| `subprojects/frida-gum` | Gum 引擎、代码探测/修改、JavaScript runtime | 构建 `frida-gum-1.0`、`frida-gumjs-1.0` 等静态库 |
| `subprojects/frida-core` | 协议、agent、gadget、server、inject、平台 backend | 生成 `frida-server`、`frida-gadget`、`frida-code-inject`、`frida-so-inject` |
| `subprojects/glib` | GLib/GObject/GIO 基础库 | 直接参与 gum/core，且受 ms_debug 的 `.a` 线程名修补影响 |
| `subprojects/libffi` | FFI 调用支持 | gum/core 间接依赖 |
| `subprojects/libiconv` | 字符集转换 | GLib 依赖链 |
| `subprojects/termux-elf-cleaner` | Android ELF 清理辅助 | Android 产物后处理/构建输入 |
| `releng` | Frida 的依赖下载、Meson 配置、机器文件和构建编排 | 决定 SDK、host toolchain、交叉编译器和 Ninja 的来源 |
| `deps/sdk-*` | Frida 预构建 Android SDK 静态库、Vala metadata 和工具 | 每个 host 架构一份，当前为 arm64、x86_64 |
| `deps/toolchain-linux-x86_64` | Linux host 构建工具和 Meson/Ninja/Vala 相关工具 | 在 Linux CI 和本地 Linux 构建使用 |

源码树中可观察到的最终目标包括 `frida-gum-1.0`、`frida-gumjs-1.0`、`frida-agent`、`frida-gadget`、`frida-helper`、`frida-core`、`frida-server`、`frida-inject`、`frida-so-inject` 和 `frida-code-inject`。

## 3. 构建工具链

| 类别 | 依赖/工具 | 来源或锁定方式 |
|---|---|---|
| 构建编排 | Meson、Ninja、pkg-config | `releng` 内置 Meson；其余由 `releng/deps.toml` 的 toolchain bundle 提供 |
| 语言编译器 | C/C++、Vala、Python 3 | C/C++ 使用 Android NDK r29；Vala 和 Python 工具来自 host toolchain/系统 |
| host 生成工具 | gperf、基础 Unix 工具 | 部分依赖（如 libiconv）需要；Frida x-tools CI 镜像已提供 |
| Android 交叉编译 | Android NDK r29、LLVM/Clang、lld、sysroot | `ANDROID_NDK_ROOT`，脚本校验 `Pkg.Revision = 29.*` |
| 依赖定位 | Frida 定制 pkg-config、Vala compiler/vapi | `releng/env.py` 将 `deps/sdk-*` 和 toolchain 注入 Meson |
| 资源生成 | Frida resource compiler、Python 脚本、Vala custom target | 由 `frida-core/src/*/meson.build` 生成 helper、agent、gadget 数据 |
| 产物后处理 | strip/ELF cleaner、项目复制脚本 | NDK/Frida toolchain 与 `scripts/build_android.sh` |

## 4. `releng/deps.toml` 的依赖目录

`deps.toml` 是完整依赖索引，不代表每个目标都会被编译。Android server/gadget/inject 的直接有效依赖由 Meson feature 和平台条件裁剪；其余条目服务于其它平台、可选 backend、测试或发行工具。

### 工具链类

`ninja`、`pkg-config`、`vala`。

### 基础库与 Gum/Core 常用依赖

`libiconv`、`zlib`、`libffi`、`pcre2`、`glib`、`brotli`、`capstone`、`quickjs`、`lzfse`、`libunwind`、`libdwarf`、`sqlite`、`json-glib`、`libsoup`、`openssl`、`libcxx`。

### 平台、网络和可选 backend 依赖

`selinux`、`libbpf`、`libusb`、`lwip`、`usrsctp`、`libnice`、`glib-networking`、`ngtcp2`、`nghttp2`、`tinycc`、`v8`、`libgee`、`elfutils`、`xz`、`minizip-ng`、`libpsl`、`libxml2`。

这些依赖的固定 commit、下载 URL、构建 scope 和 bundle 规则以源码树中的 `releng/deps.toml` 为准；不要只根据发行版包名重新安装一套“相近版本”。

## 5. Android 目标的实际依赖链

```text
Android NDK r29 / Clang / lld / sysroot
              |
        Meson + Ninja + pkg-config + Vala
              |
  GLib + libffi + libiconv + capstone + QuickJS
              |
       frida-gum / frida-gumjs
              |
        frida-core + agent/helper
          /       |        \
   frida-server  gadget  inject targets
```

`frida-core` 的 Meson 文件还声明了 TLS、HTTP/2/QUIC、USB、SELinux、network、database 等条件依赖。对本项目的 Android 产物，最终是否进入链接结果必须以对应 build directory 的 Meson introspection、`readelf -d`、静态库成员和实际目标配置为准，而不是把整个 `deps.toml` 当作必需链接集合。

## 6. 与 ms_debug 复现流程的关系

1. `fetch_frida.sh` 下载并锁定 root commit、递归 submodule 和额外固定依赖。
2. `releng/deps.py sync sdk <host>` 下载对应 SDK bundle，另行下载 Linux host toolchain。
3. `apply_patches.sh` 按子仓库路径应用 patch，并复制无法由文本 patch 表示的 ARM64 helper payload。
4. `build_android.sh` 以 NDK r29 配置 Meson，临时修补 SDK 中的 GLib/GIO `.a`，编译目标后恢复原文件。
5. `copy_outputs.sh` 收集目标产物；`compare_outputs.sh` 通过 ELF/ABI/依赖/符号/行为层级核对，而不是只比较 SHA-256。

源码锁定配置位于 `config/versions.env`；如果升级 Frida，应同时更新 root commit、submodule/依赖 commit、patch 适用性和本文件的分析结论。
