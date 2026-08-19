#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${ROOT_DIR}/work/frida}"
PATCH_DIR="${ROOT_DIR}/patchs"
FILES_DIR="${ROOT_DIR}/files"
FRIDA_DEBUG_BISECT="${FRIDA_DEBUG_BISECT:-0}"
FRIDA_GUM_DEBUG_LOGS="${FRIDA_GUM_DEBUG_LOGS:-0}"

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

if [[ "${FRIDA_DEBUG_BISECT}" == "1" ]]; then
  apply_one "${SRC}/subprojects/frida-core" 001-frida-core-gadget-bisect.patch
  apply_one "${SRC}/subprojects/glib" 002-glib-gio-thread-name-and-gtask-bisect.patch
else
  echo "FRIDA_DEBUG_BISECT=0：跳过 001/002 调试停止点 patch"
fi
apply_one "${SRC}/subprojects/frida-core" 005-frida-server-group-stop-inject.patch
apply_one "${SRC}/subprojects/frida-gum" 006-frida-gum-runtime-and-pretty-method.patch
if [[ "${FRIDA_GUM_DEBUG_LOGS}" == "1" ]]; then
  echo "FRIDA_GUM_DEBUG_LOGS=1：保留 006 中的 MYOBS 调试日志"
else
  python3 "${FILES_DIR}/scripts/disable_frida_debug_logs.py" \
    "${SRC}/subprojects/frida-gum"
fi
apply_one "${SRC}/subprojects/frida-core" 007-frida-core-agent-memfd-name-msagent.patch
apply_one "${SRC}/subprojects/frida-core" 008-frida-core-helper-injection.patch
apply_one "${SRC}/subprojects/frida-core" 012-frida-core-android-helper-descriptive-thread-name.patch
if [[ "${FRIDA_BUILD_GLIB:-1}" == "1" ]]; then
  apply_one "${SRC}/subprojects/glib" 009-glib-descriptive-thread-name.patch
  apply_one "${SRC}/subprojects/frida-gum" 010-frida-gum-descriptive-thread-name.patch
else
  echo "FRIDA_BUILD_GLIB=0：跳过依赖自构建专用的方案 A GLib/Gum patch"
fi
apply_one "${SRC}/subprojects/frida-core" 011-frida-core-loader-descriptive-thread-name.patch

# ms_debug carries several prebuilt helper payloads which are consumed by
# frida-core's resource bundling step and therefore cannot be represented by
# a text-only git patch. This also includes the architecture-independent
# helper.dex generated from patch 012.
if [[ -d "${FILES_DIR}/frida-core" ]]; then
  cp -a "${FILES_DIR}/frida-core/." "${SRC}/subprojects/frida-core/"
fi

mkdir -p "${SRC}/scripts"
# These are project-level build helpers, not official Frida submodule patches.
install -m 0755 "${FILES_DIR}/scripts/build_android.sh" "${SRC}/scripts/build_android.sh"
install -m 0755 "${FILES_DIR}/scripts/build_android_helper.sh" "${SRC}/scripts/build_android_helper.sh"
install -m 0755 "${FILES_DIR}/scripts/disable_frida_debug_logs.py" "${SRC}/scripts/disable_frida_debug_logs.py"
install -m 0755 "${FILES_DIR}/scripts/copy_outputs.sh" "${SRC}/scripts/copy_outputs.sh"
install -m 0755 "${FILES_DIR}/scripts/修补_ms线程名.py" "${SRC}/scripts/修补_ms线程名.py"
echo "已应用源码 patch，并安装构建辅助文件：${SRC}"
