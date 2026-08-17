# Frida 17.9.10 可复现构建说明

当前复现资料已经集中到 `patchs/`，使补丁目录本身尽量独立。

请优先查看：

- `patchs/可复现构建说明.md`
- `patchs/依赖信息.md`
- `patchs/README.md`
- `patchs/apply_frida_17_9_10_patches.sh`

推荐命令：

```bash
bash patchs/apply_frida_17_9_10_patches.sh
FRIDA_TARGET=frida-server bash scripts/run_podman.sh
```

当前默认构建镜像为 `localhost/ubuntu26:dev`，由 `docker.io/library/ubuntu:26.04` 安装依赖后保存得到。
