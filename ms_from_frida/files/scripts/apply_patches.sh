#!/usr/bin/env bash
set -euo pipefail

# 当前目录已经提交了 MyFrida 17.15.3 当前源码态；本脚本保留为版本专用补丁入口。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_DIR="${VERSION_ROOT}/patches"

if [[ ! -d "${PATCH_DIR}" ]]; then
  echo "补丁目录不存在：${PATCH_DIR}" >&2
  exit 1
fi

echo "MyFrida v17.15.3 当前源码态已在本版本仓库提交。"
echo "历史补丁资产位置：${PATCH_DIR}"
echo "如需从官方快照重新生成补丁，请基于本仓前两个提交比较。"
