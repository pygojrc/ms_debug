# ms_from_frida

本目录保存 Frida 17.15.3 的固定版本信息、按目的分类的 patch、helper 资源和 GitHub Workflow 构建资料。

## 使用 Workflow

请按 [`BUILD-WORKFLOW.md`](BUILD-WORKFLOW.md) 手动触发根目录的 `.github/workflows/ms-from-frida.yml`。默认 `build_type=release`，只有选择 `debug` 时才会加入打印日志和二分调试点。构建结果以 workflow artifact 提供；只有 release 构建允许发布 GitHub Release。

Workflow 会从 [`config/versions.env`](config/versions.env) 的固定 commit checkout 官方源码，下载对应的 SDK/toolchain，并始终从固定 GLib 源码构建 GLib/GObject/GIO。不会走本地脚本，也不会对预编译 `.a` 做线程名替换。

## 目录

- [`patches/`](patches/)：当前活动 patch，按 release/debug 和目的拆分。
- [`files/frida-core/`](files/frida-core/)：已审计的 Android helper 资源。
- [`config/versions.env`](config/versions.env)：Frida、子模块和依赖的固定 commit。
- [`reports/`](reports/)：既有构建/对比报告，仅作历史证据。
- [`docs/legacy-build-workflow.yml`](docs/legacy-build-workflow.yml)：已停用的旧 workflow 历史归档。

旧的 `patchs/` 和脚本目录仅保留在迁移期间作为历史资料，不会被当前 workflow 调用。
