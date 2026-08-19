#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${ROOT_DIR}/work/frida}"
PATCH_DIR="${ROOT_DIR}/patchs"
FILES_DIR="${ROOT_DIR}/files"

apply_one() {
  local repo="$1" patch="$2"
  if git -C "${repo}" apply --check "${PATCH_DIR}/${patch}"; then
    git -C "${repo}" apply "${PATCH_DIR}/${patch}"
  elif git -C "${repo}" apply --reverse --check "${PATCH_DIR}/${patch}"; then
    echo "已应用，跳过：${patch}"
  else
    echo "无法应用或识别已应用状态：${patch}" >&2
    exit 1
  fi
}

apply_one "${SRC}/subprojects/frida-core" 001-frida-core-gadget-bisect.patch
apply_one "${SRC}/subprojects/glib" 002-glib-gio-thread-name-and-gtask-bisect.patch
apply_one "${SRC}/subprojects/frida-core" 005-frida-server-group-stop-inject.patch
apply_one "${SRC}/subprojects/frida-gum" 006-frida-gum-runtime-and-pretty-method.patch
apply_one "${SRC}/subprojects/frida-core" 007-frida-core-agent-memfd-name-msagent.patch
apply_one "${SRC}/subprojects/frida-core" 008-frida-core-helper-injection.patch

# ms_debug carries several prebuilt ARM64 helper payloads which are consumed
# by frida-core's resource bundling step and therefore cannot be represented
# by a text-only git patch.
if [[ -d "${FILES_DIR}/frida-core" ]]; then
  cp -a "${FILES_DIR}/frida-core/." "${SRC}/subprojects/frida-core/"
fi

mkdir -p "${SRC}/scripts"
# These are project-level build helpers, not official Frida submodule patches.
install -m 0755 "${FILES_DIR}/scripts/build_android.sh" "${SRC}/scripts/build_android.sh"
install -m 0755 "${FILES_DIR}/scripts/copy_outputs.sh" "${SRC}/scripts/copy_outputs.sh"
install -m 0755 "${FILES_DIR}/scripts/修补_ms线程名.py" "${SRC}/scripts/修补_ms线程名.py"
echo "已应用源码 patch，并安装构建辅助文件：${SRC}"
