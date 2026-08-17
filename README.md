# ms_debug — MyFrida 化 frida 安卓构建仓库

本仓库把 [MyFrida](https://github.com/...) 对官方 frida 的“补丁化构建”能力沉淀为一份可独立构建、可自动发布的源码快照。

## 版本

- 基线：官方 **Frida 17.15.3**（注意：官方不存在 `17.5.3` 这个 tag）
- 补丁：MyFrida 的 7 个改动（gadget 二分/线程名、glib 线程名、`SIGSTOP+PTRACE_SEIZE` 注入保护、gum 运行时与 ART `PrettyMethod` 特例、agent memfd 名称等），见 `patchs/README.md`

## 目录结构

```
frida/    官方 17.15.3 源码 + MyFrida 补丁（已合并，去 .git）
patchs/   对应补丁的 diff 记录（构建不依赖，仅作透明留存）
.github/  GitHub Actions 构建/发布流程
```

> 说明：`frida/` 已经是“源码快照 + 补丁”合并后的整树，因此 `patchs/` 中的 `*.patch` **不需要**再 `git apply`。如需从官方 `17.15.3` 重新生成这些补丁，可基于 MyFrida 仓库 `my_frida/v17.15.3` 的 `base_commit..patch_commit` 两次提交比较。

## 本地构建（参考 MyFrida）

```bash
# 需要 Android NDK r29 与 JDK 17
cd frida
export ANDROID_NDK_ROOT=/path/to/android-ndk-r29
./configure --host=android-arm64 --prefix="$PWD/install"
# 按 MyFrida 方式修补 SDK 内 glib 线程名（可选，对应 patch 002/003）
python3 scripts/修补_ms线程名.py deps/sdk-android-arm64/lib/libglib-2.0.a deps/sdk-android-arm64/lib/libgio-2.0.a
make frida-server frida-gadget frida-code-inject frida-so-inject
```

## CI 构建与发布

推送到 `main` 触发构建验证；打 tag（如 `17.15.3`）并推送后，GitHub Actions 会构建安卓 `arm64` 与 `x86_64`，并把产物发布到 releases：

- `ms_server`（frida-server）
- `gadget.so`（frida-gadget）
- `frida-code-inject`
- `frida-so-inject`

`configure` 会自动从 frida 公共 S3 拉取 prebuilt SDK/toolchain（无需 AWS 密钥）；产物版本号使用 frida 官方版本号（即 git tag）。

## 参考来源

- 构建方式参考 `MyFrida/scripts/run_podman.sh` 与 `MyFrida/my_frida/v17.15.3/scripts/`
- 官方 CI 参考 `frida/.github/workflows/ci.yml` 的 `sdk-android-64` 任务与 `frida/.cirrus.yml`
