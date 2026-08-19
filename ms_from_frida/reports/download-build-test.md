# 下载与构建测试记录

## 已完成

执行：

```bash
FRIDA_HOSTS='android-arm64 android-x86' \
  bash scripts/fetch_frida.sh work/frida
bash scripts/apply_patches.sh work/frida
```

结果：

- Frida `17.15.3` 主仓库：成功；
- 官方递归子模块：成功；
- `frida/glib@92d65736b198c2cf131f691dd83db0b25f7b02d2`：成功；
- `frida/libffi@c06a577933f07c76c3f536c9e4ba0f7d9c1e8c4d`：成功；
- `frida/libiconv@bbbf4561da4847bf95ce9458da76e072b77cabd1`：成功；
- `frida/termux-elf-cleaner@ab933ec128c6538067cdf3907ebbbc3bc35f1c55`：成功；
- Android SDK `android-arm64`：成功；
- Android SDK `android-x86`：成功；
- Linux host toolchain：成功；
- 下载目录总大小：约 1.7 GB；
- `001`、`002`、`005`、`006`、`007`：成功应用；
- 构建辅助脚本：成功安装。

随后执行完整入口：

```bash
FRIDA_HOSTS='android-arm64 android-x86' \
  bash scripts/build_ms_debug.sh work/frida

## 后续完成记录

上面的 NDK 阻断记录是早期测试结果。随后已由 `scripts/download_ndk.sh` 下载并校验 Android NDK r29，并改用 Release 对应的 `android-x86_64` host 完成双架构构建；最终结果见 `build-result-android-arm64-x86.md` 和 `compare-arm64.md`、`compare-x86_64.md`。
```

脚本能够复用已下载源码和依赖，并重新识别已应用 patch；最后在 NDK 检查处停止。

## 构建测试

执行构建入口后，脚本报告：

```text
依赖和 patch 已准备，但请设置 ANDROID_NDK_ROOT，并指向 Android NDK r29
```

当前工作环境没有 Android NDK r29，因此尚未产生 `frida-server` 的 ARM64/x86 二进制，也不能进行最终产物和运行时行为对比。这个结果是环境阻断，不是源码 patch 应用失败。

准备 NDK 后执行：

```bash
export ANDROID_NDK_ROOT=/path/to/android-ndk-r29
FRIDA_HOSTS='android-arm64 android-x86' \
  bash scripts/build_ms_debug.sh work/frida
```
