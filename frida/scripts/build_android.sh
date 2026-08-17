#!/usr/bin/env bash
set -euo pipefail

# Android 构建入口。脚本只依赖当前 v17.15.3 目录，便于多版本并存。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${VERSION_ROOT}/../.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/tmp/running.md"

FRIDA_HOST="${FRIDA_HOST:-android-arm64}"
FRIDA_TARGET="${FRIDA_TARGET:-frida-server}"
BUILD_DIR="${BUILD_DIR:-${VERSION_ROOT}/build/frida-${FRIDA_HOST}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${VERSION_ROOT}/build/install-${FRIDA_HOST}}"

mkdir -p "$(dirname "${LOG_FILE}")"
{
  echo ""
  echo "- $(date '+%F %T') v17.15.3 开始编译：host=${FRIDA_HOST}, target=${FRIDA_TARGET}, build=${BUILD_DIR}"
} >> "${LOG_FILE}"

if [[ ! -d "${VERSION_ROOT}/.git" ]]; then
  echo "当前版本目录不是独立 git 仓库：${VERSION_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${ANDROID_NDK_ROOT:-}/source.properties" ]]; then
  echo "ANDROID_NDK_ROOT 未正确设置，当前值：${ANDROID_NDK_ROOT:-<empty>}" >&2
  exit 1
fi

NDK_REVISION="$(sed -n 's/^Pkg.Revision = //p' "${ANDROID_NDK_ROOT}/source.properties" | head -n 1)"
NDK_MAJOR="${NDK_REVISION%%.*}"
if [[ "${NDK_MAJOR}" != "29" ]]; then
  echo "Frida 17.15.3 需要 Android NDK r29，当前为：${NDK_REVISION}" >&2
  exit 1
fi

CONFIGURE_OPTIONS=()
MESON_OPTIONS=()
if [[ -n "${FRIDA_CONFIGURE_OPTIONS:-}" ]]; then
  read -r -a EXTRA_CONFIGURE_OPTIONS <<< "${FRIDA_CONFIGURE_OPTIONS}"
  CONFIGURE_OPTIONS+=("${EXTRA_CONFIGURE_OPTIONS[@]}")
fi
if [[ -n "${FRIDA_MESON_OPTIONS:-}" ]]; then
  read -r -a EXTRA_MESON_OPTIONS <<< "${FRIDA_MESON_OPTIONS}"
  MESON_OPTIONS+=("${EXTRA_MESON_OPTIONS[@]}")
fi

cd "${VERSION_ROOT}"

if [[ ! -f releng/meson/meson.py ]]; then
  echo "releng/meson 缺失，当前版本目录不完整。" >&2
  exit 1
fi

if [[ ! -d "deps/sdk-${FRIDA_HOST}" ]]; then
  echo "deps/sdk-${FRIDA_HOST} 不存在；如需离线加速，请先准备当前版本 deps。" >&2
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
  mkdir -p "${BUILD_DIR}"
  MESON_BUILD_ROOT="${BUILD_DIR}" ./configure \
    --host="${FRIDA_HOST}" \
    --prefix="${INSTALL_PREFIX}" \
    "${CONFIGURE_OPTIONS[@]}" \
    -- \
    "${MESON_OPTIONS[@]}"
fi

PATCHED_FRIDA_DEPS=()
restore_frida_deps() {
  if [[ "${#PATCHED_FRIDA_DEPS[@]}" -gt 0 ]]; then
    python3 "${SCRIPT_DIR}/修补_ms线程名.py" --reverse "${PATCHED_FRIDA_DEPS[@]}" >/dev/null || true
  fi
}

SDK_LIB_DIR="${VERSION_ROOT}/deps/sdk-${FRIDA_HOST}/lib"
PATCHED_FRIDA_DEPS=(
  "${SDK_LIB_DIR}/libglib-2.0.a"
  "${SDK_LIB_DIR}/libgio-2.0.a"
)
python3 "${SCRIPT_DIR}/修补_ms线程名.py" "${PATCHED_FRIDA_DEPS[@]}"
trap restore_frida_deps EXIT

make -C "${BUILD_DIR}" "${FRIDA_TARGET}"

restore_frida_deps
trap - EXIT

FRIDA_HOST="${FRIDA_HOST}" FRIDA_TARGET="${FRIDA_TARGET}" BUILD_DIR="${BUILD_DIR}" \
  bash "${SCRIPT_DIR}/copy_outputs.sh"

{
  echo "- $(date '+%F %T') v17.15.3 编译完成：target=${FRIDA_TARGET}, bin=${VERSION_ROOT}/bin/${FRIDA_HOST}"
} >> "${LOG_FILE}"
