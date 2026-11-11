#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "build-target.sh 仅供 GitHub Actions 使用" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${ROOT_DIR}/ms_from_frida/config/versions.env"
BUILD_TYPE="release"
HOST=""
ARCH=""
SOURCE_DIR=""
usage() {
  echo "用法：$0 [-b release|debug] --host <host> -s <source-dir>" >&2
  echo "host: android-arm64 android-x86_64 linux-x86_64" >&2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type) BUILD_TYPE="${2:?缺少 build type}"; shift 2 ;;
    --host) HOST="${2:?缺少 host}"; shift 2 ;;
    -a|--arch) ARCH="${2:?缺少 arch}"; shift 2 ;;   # 兼容旧参数
    -s|--source) SOURCE_DIR="${2:?缺少 source dir}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
if [[ -z "${HOST}" ]]; then
  [[ -n "${ARCH}" ]] || { usage; exit 2; }
  HOST="android-${ARCH}"
fi
case "${HOST}" in
  android-arm64|android-x86_64|linux-x86_64) ;;
  *) echo "build-target.sh 不处理 host：${HOST}（windows 走 build-windows.ps1）" >&2; exit 2 ;;
esac
PLATFORM="${HOST%%-*}"
[[ "${BUILD_TYPE}" == release || "${BUILD_TYPE}" == debug ]] || { usage; exit 2; }
[[ -n "${SOURCE_DIR}" ]] || { usage; exit 2; }
SOURCE_DIR="$(realpath -m "${SOURCE_DIR}")"

# android 依赖 NDK r29；linux native 不需要。
if [[ "${PLATFORM}" == android ]]; then
  NDK_ROOT="${ANDROID_NDK_ROOT:-}"
  [[ -f "${NDK_ROOT}/source.properties" ]] || {
    echo "ANDROID_NDK_ROOT 未指向 Android NDK r29" >&2; exit 1;
  }
  grep -q '^Pkg.Revision = 29\.' "${NDK_ROOT}/source.properties" || {
    echo "当前 NDK 不是 r29" >&2; exit 1;
  }
fi

# GLib/GObject/GIO 始终从锁定源码构建；不保留预编译 .a 的回退路径。
GLIB_BUILD="$(mktemp -d "${RUNNER_TEMP:-/tmp}/ms-glib-${HOST}.XXXXXX")"
GLIB_SRC="${GLIB_BUILD}/src/glib"
git clone --no-checkout https://github.com/frida/glib.git "${GLIB_SRC}"
git -C "${GLIB_SRC}" checkout --detach "${GLIB_COMMIT}"
# deps.py 会读取 FETCH_HEAD；固定 commit checkout 后补齐该元数据。
if ! git -C "${GLIB_SRC}" rev-parse FETCH_HEAD >/dev/null 2>&1; then
  git -C "${GLIB_SRC}" fetch . HEAD >/dev/null
fi
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
  # native 构建的 server/gadget/inject auto 规则默认关闭，必须显式 enable。
  # linux 关闭 compat（32 位 helper 需要额外的 32 位 SDK 与工具链）。
  EXTRA_OPTIONS=()
  if [[ "${PLATFORM}" == linux ]]; then
    EXTRA_OPTIONS+=("-Dfrida-core:compat=disabled")
  fi
  MESON_BUILD_ROOT="${BUILD_DIR}" ./configure \
    --host="${HOST}" \
    --prefix="${INSTALL_PREFIX}" \
    --enable-server --enable-gadget --enable-inject \
    --disable-frida-tools --disable-frida-python \
    -- -Dlibdir=lib "${EXTRA_OPTIONS[@]}"
fi

# 一次 configure、一次 make，确保四类产物使用同一份 patched tree。
make -C "${BUILD_DIR}" frida-server frida-gadget frida-code-inject frida-so-inject

OUT_DIR="${ROOT_DIR}/out/${BUILD_TYPE}/${HOST}"
mkdir -p "${OUT_DIR}"
cp "${BUILD_DIR}/subprojects/frida-core/server/frida-server" "${OUT_DIR}/ms_server"
cp "${BUILD_DIR}/subprojects/frida-core/lib/gadget/frida-gadget.so" "${OUT_DIR}/gadget.so"
cp "${BUILD_DIR}/subprojects/frida-core/inject/frida-code-inject" "${OUT_DIR}/frida-code-inject"
cp "${BUILD_DIR}/subprojects/frida-core/inject/frida-so-inject" "${OUT_DIR}/frida-so-inject"
printf '%s 构建完成：%s\n' "${HOST}" "${OUT_DIR}"
