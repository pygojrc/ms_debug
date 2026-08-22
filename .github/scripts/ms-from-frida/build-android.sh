#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "build-android.sh 仅供 GitHub Actions 使用" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${ROOT_DIR}/ms_from_frida/config/versions.env"
BUILD_TYPE="release"
ARCH=""
SOURCE_DIR=""
usage() { echo "用法：$0 [-b release|debug] -a arm64|x86_64 -s <source-dir>" >&2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type) BUILD_TYPE="${2:?缺少 build type}"; shift 2 ;;
    -a|--arch) ARCH="${2:?缺少 arch}"; shift 2 ;;
    -s|--source) SOURCE_DIR="${2:?缺少 source dir}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ "${BUILD_TYPE}" == release || "${BUILD_TYPE}" == debug ]] || { usage; exit 2; }
[[ "${ARCH}" == arm64 || "${ARCH}" == x86_64 ]] || { usage; exit 2; }
[[ -n "${SOURCE_DIR}" ]] || { usage; exit 2; }
SOURCE_DIR="$(realpath -m "${SOURCE_DIR}")"
HOST="android-${ARCH}"
NDK_ROOT="${ANDROID_NDK_ROOT:-}"
[[ -f "${NDK_ROOT}/source.properties" ]] || {
  echo "ANDROID_NDK_ROOT 未指向 Android NDK r29" >&2; exit 1;
}
grep -q '^Pkg.Revision = 29\.' "${NDK_ROOT}/source.properties" || {
  echo "当前 NDK 不是 r29" >&2; exit 1;
}

# GLib/GObject/GIO 始终从锁定源码构建；不保留预编译 .a 的回退路径。
GLIB_BUILD="$(mktemp -d "${RUNNER_TEMP:-/tmp}/ms-glib-${ARCH}.XXXXXX")"
GLIB_SRC="${GLIB_BUILD}/src/glib"
git clone --no-checkout https://github.com/frida/glib.git "${GLIB_SRC}"
git -C "${GLIB_SRC}" checkout --detach "${GLIB_COMMIT}"
git -C "${GLIB_SRC}" apply --whitespace=nowarn \
  "${ROOT_DIR}/ms_from_frida/patches/release/thread-name/glib.patch"
if [[ "${BUILD_TYPE}" == debug ]]; then
  git -C "${GLIB_SRC}" apply --whitespace=nowarn \
    "${ROOT_DIR}/ms_from_frida/patches/debug/bisect/glib.patch"
fi
FRIDA_DEPS="${GLIB_BUILD}" python3 "${SOURCE_DIR}/releng/deps.py" build \
  --bundle=sdk --build=linux-x86_64 --host="${HOST}" --only=glib -v
GLIB_ARCHIVE="${GLIB_BUILD}/sdk-${HOST}.tar.xz"
[[ -f "${GLIB_ARCHIVE}" ]] || { echo "自构建 GLib SDK 未生成" >&2; exit 1; }
tar -xJf "${GLIB_ARCHIVE}" -C "${SOURCE_DIR}/deps/sdk-${HOST}"

cd "${SOURCE_DIR}"
BUILD_DIR="${SOURCE_DIR}/build/${HOST}"
INSTALL_PREFIX="${SOURCE_DIR}/install/${HOST}"
if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
  mkdir -p "${BUILD_DIR}"
  MESON_BUILD_ROOT="${BUILD_DIR}" ./configure --host="${HOST}" --prefix="${INSTALL_PREFIX}"
fi

# 一次 configure、一次 make，确保四类 Android 产物使用同一份 patched tree。
make -C "${BUILD_DIR}" frida-server frida-gadget frida-code-inject frida-so-inject

OUT_DIR="${ROOT_DIR}/out/${BUILD_TYPE}/${HOST}"
mkdir -p "${OUT_DIR}"
cp "${BUILD_DIR}/subprojects/frida-core/server/frida-server" "${OUT_DIR}/ms_server"
cp "${BUILD_DIR}/subprojects/frida-core/lib/gadget/frida-gadget.so" "${OUT_DIR}/gadget.so"
cp "${BUILD_DIR}/subprojects/frida-core/inject/frida-code-inject" "${OUT_DIR}/frida-code-inject"
cp "${BUILD_DIR}/subprojects/frida-core/inject/frida-so-inject" "${OUT_DIR}/frida-so-inject"
printf 'Android 构建完成：%s\n' "${OUT_DIR}"
