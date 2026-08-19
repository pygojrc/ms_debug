#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"
SRC="${1:-${ROOT_DIR}/work/frida}"
SRC="$(cd "${SRC}" && pwd)"
TARGET="${FRIDA_TARGET:-${FRIDA_TARGET_DEFAULT}}"
if [[ -n "${FRIDA_HOSTS:-}" ]]; then
  read -r -a HOSTS <<< "${FRIDA_HOSTS}"
elif [[ -n "${FRIDA_HOST:-}" ]]; then
  HOSTS=("${FRIDA_HOST}")
else
  HOSTS=(android-arm64 android-x86_64)
fi

command -v git >/dev/null || { echo '缺少 git' >&2; exit 1; }
command -v make >/dev/null || { echo '缺少 make' >&2; exit 1; }

FRIDA_HOSTS="${HOSTS[*]}" "${ROOT_DIR}/scripts/fetch_frida.sh" "${SRC}"
"${ROOT_DIR}/scripts/apply_patches.sh" "${SRC}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ROOT_DIR}/toolchains/android-ndk-r29}"
if [[ "${FRIDA_DOWNLOAD_NDK:-1}" != "0" ]]; then
  "${ROOT_DIR}/scripts/download_ndk.sh" "${ANDROID_NDK_ROOT}"
fi
[[ -f "${ANDROID_NDK_ROOT}/source.properties" ]] || {
  echo '依赖和 patch 已准备，但 Android NDK r29 不存在' >&2; exit 1;
}
grep -q '^Pkg.Revision = 29\.' "${ANDROID_NDK_ROOT}/source.properties" || {
  echo '依赖和 patch 已准备，但当前 NDK 不是 r29' >&2; exit 1;
}
for HOST in "${HOSTS[@]}"; do
  cd "${SRC}"
  BUILD_DIR="${SRC}/build/frida-${HOST}"
  INSTALL_PREFIX="${SRC}/build/install-${HOST}"
  if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
    mkdir -p "${BUILD_DIR}"
    MESON_BUILD_ROOT="${BUILD_DIR}" ./configure --host="${HOST}" --prefix="${INSTALL_PREFIX}"
  fi
  FRIDA_HOST="${HOST}" FRIDA_TARGET="${TARGET}" BUILD_DIR="${BUILD_DIR}" \
    INSTALL_PREFIX="${INSTALL_PREFIX}" bash "${SRC}/scripts/build_android.sh"
done
