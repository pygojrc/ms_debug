# ms_from_frida Workflow 构建说明

本项目不提供本地构建入口。构建统一由 GitHub Actions 的手动 workflow 完成：

1. 打开 GitHub Actions，选择 `ms_from_frida build and release`。
2. 选择 `build_type`：默认 `release`；只有排查问题时选择 `debug`。
3. release 构建可选择是否发布 GitHub Release；debug 构建只上传 workflow artifact，不发布 Release。
4. 等待各目标完成，在对应任务下载产物。

## 构建目标

| host | 运行方式 | 产物 |
| --- | --- | --- |
| `android-arm64` / `android-x86_64` | `ubuntu-24.04` + x-tools 容器 + Android NDK r29 交叉 | `ms_server`、`gadget.so`、`frida-code-inject`、`frida-so-inject` |
| `linux-x86_64` | `ubuntu-24.04` + x-tools 容器本机构建 | 同上（ELF） |
| `windows-x86_64` | `windows-latest` + Visual Studio（MSVC）原生构建 | `ms_server.exe`、`gadget.dll`、`frida-inject.exe` |

linux/windows 的 native 构建必须显式 `--enable-server --enable-gadget --enable-inject`（根 meson 的 auto 规则在 native 构建下会关闭它们）；android 交叉构建同样显式传入以保持一致。

Windows 不应用 linux-family 的 `helper-injection` 补丁（自研 `frida-code-inject`/`frida-so-inject` 依赖 Linux helper 后端），因此 Windows 目标产出官方标准三件套：`ms_server.exe`、`gadget.dll`、`frida-inject.exe`。

## 平台补丁选择

`prepare-source.sh` 按 host 选择补丁集合：

- 所有平台：`thread-name`（glib 层统一的名字改造：线程名 + 进程可见名后端）、`process-name`（server 入口调用）、`control-port`、`gum-runtime`、`exceptor-handler-only`；debug 构建追加 `logging` 与 `bisect`。
- `android` / `linux`：追加 `agent-memfd-name`、`injection-group-stop`、`helper-injection`。
- `windows`：追加 `windows-identity`（agent/helper/管道等可见标识改名与注入修复）。
- `android` 额外复制 `files/frida-core/` 的 helper 资源；linux/windows 使用官方源码自带的 helper payload。

## 脚本

- `.github/workflows/ms-from-frida.yml`
- `.github/scripts/ms-from-frida/prepare-source.sh`：固定源码、同步依赖、按平台应用补丁。
- `.github/scripts/ms-from-frida/build-target.sh`：android/linux 构建（自建 patched GLib + configure + make）。
- `.github/scripts/ms-from-frida/build-windows.ps1`：windows-x86_64 构建。
- `.github/scripts/ms-from-frida/verify-artifacts.sh` / `verify-artifacts.ps1`：产物与 profile 门禁。

这些脚本会检查 `GITHUB_ACTIONS=true`，不能作为本地构建命令使用。旧 workflow 已移至 `docs/legacy-build-workflow.yml`，仅作历史记录。
