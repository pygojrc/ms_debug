# ms_from_frida Workflow 构建说明

本项目不提供本地构建入口。构建统一由 GitHub Actions 的手动 workflow 完成：

1. 打开 GitHub Actions，选择 `ms_from_frida build and release`。
2. 选择 `build_type`：默认 `release`；只有排查问题时选择 `debug`。
3. release 构建可选择是否发布 GitHub Release；debug 构建只上传 workflow artifact，不发布 Release。
4. 等待 `arm64` 和 `x86_64` 两个矩阵任务完成，在对应任务下载产物。

Workflow 会从 `config/versions.env` 的固定 commit 准备 Frida 17.15.3，按 [`patches/README.md`](patches/README.md) 应用补丁，并始终从固定 GLib 源码重新构建 GLib/GObject/GIO。默认 release 不包含 `MYOBS` 日志和二分停止点。

当前唯一可执行构建入口是：

- `.github/workflows/ms-from-frida.yml`
- `.github/scripts/ms-from-frida/prepare-source.sh`
- `.github/scripts/ms-from-frida/build-android.sh`
- `.github/scripts/ms-from-frida/verify-artifacts.sh`

这些脚本会检查 `GITHUB_ACTIONS=true`，不能作为本地构建命令使用。旧 workflow 已移至 `docs/legacy-build-workflow.yml`，仅作历史记录。
