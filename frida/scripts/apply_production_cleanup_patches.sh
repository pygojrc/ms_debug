#!/usr/bin/env bash
set -euo pipefail

# 生产清理 patch 仍保留在 patches/rollback，实际应用前需确认当前源码是否需要回滚诊断逻辑。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_DIR="${VERSION_ROOT}/patches/rollback"

if [[ ! -d "${PATCH_DIR}" ]]; then
  echo "生产清理补丁目录不存在：${PATCH_DIR}" >&2
  exit 1
fi

echo "生产清理补丁位置：${PATCH_DIR}"
echo "当前未自动应用，避免误删仍需验证的诊断代码。"
