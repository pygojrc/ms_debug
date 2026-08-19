#!/usr/bin/env bash
set -euo pipefail

# Rebuild GLib/GObject/GIO from source and overlay the resulting partial SDK
# onto the official full SDK.  This deliberately keeps all non-GLib packages
# from the downloaded SDK while ensuring the GLib bisect patch and the
# descriptive thread-name patch are compiled into GLib.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(realpath -m "${1:?用法: build_glib_sdk.sh <frida-source> <android-host>}")"
HOST="${2:?用法: build_glib_sdk.sh <frida-source> <android-host>}"
source "${ROOT_DIR}/config/versions.env"

# Prefer task-local host tools when available.  This keeps the build
# reproducible on runners where the system package database is read-only.
LOCAL_HOST_BIN="${ROOT_DIR}/toolchains/host-bin"
if [[ -x "${LOCAL_HOST_BIN}/gperf" ]]; then
  PATH="${LOCAL_HOST_BIN}:${PATH}"
  export PATH
fi

DEPS_DIR="${FRIDA_DEPS:-${SRC}/deps}"
SDK_DIR="${DEPS_DIR}/sdk-${HOST}"
BUILD_DEPS_DIR="${DEPS_DIR}/glib-build-cache-${HOST}"
GLIB_SRC="${BUILD_DEPS_DIR}/src/glib"
GLIB_PATCHES=(
  "${ROOT_DIR}/patchs/002-glib-gio-thread-name-and-gtask-bisect.patch"
  "${ROOT_DIR}/patchs/009-glib-descriptive-thread-name.patch"
)
ARCHIVE="${BUILD_DEPS_DIR}/sdk-${HOST}.tar.xz"

[[ -d "${SDK_DIR}" ]] || { echo "完整 SDK 不存在：${SDK_DIR}" >&2; exit 1; }
for patch in "${GLIB_PATCHES[@]}"; do
  [[ -f "${patch}" ]] || { echo "GLib patch 不存在：${patch}" >&2; exit 1; }
done
command -v python3 >/dev/null || { echo "缺少 python3" >&2; exit 1; }
command -v gperf >/dev/null || {
  echo "缺少 host 工具 gperf；请使用 Frida x-tools CI 镜像或安装 gperf" >&2
  exit 1
}

PATCH_DIGEST="$(sha256sum "${GLIB_PATCHES[@]}" | sha256sum | cut -d' ' -f1)"
STAMP="${SDK_DIR}/.ms-debug-glib-${GLIB_COMMIT}-${PATCH_DIGEST}"
if [[ -f "${STAMP}" && "${FRIDA_BUILD_GLIB_REBUILD:-0}" != "1" ]]; then
  echo "已存在匹配的自构建 GLib，跳过：${SDK_DIR}"
  exit 0
fi

mkdir -p "${BUILD_DEPS_DIR}/src"
if [[ ! -d "${GLIB_SRC}/.git" && ! -f "${GLIB_SRC}/.git" ]]; then
  git clone --no-checkout https://github.com/frida/glib.git "${GLIB_SRC}"
fi
if ! git -C "${GLIB_SRC}" cat-file -e "${GLIB_COMMIT}^{commit}" 2>/dev/null; then
  git -C "${GLIB_SRC}" fetch origin "${GLIB_COMMIT}"
fi

CURRENT_COMMIT="$(git -C "${GLIB_SRC}" rev-parse HEAD 2>/dev/null || true)"
if [[ "${CURRENT_COMMIT}" != "${GLIB_COMMIT}" ]]; then
  git -C "${GLIB_SRC}" diff --quiet || {
    echo "GLib 源码存在未预期修改，无法切换到固定 commit：${GLIB_SRC}" >&2
    exit 1
  }
  git -C "${GLIB_SRC}" checkout --detach "${GLIB_COMMIT}"
fi

# Frida's deps.py reuses the checkout by resolving FETCH_HEAD.  A detached
# checkout created from a local/cache clone may not retain that pseudo-ref;
# refresh it locally without contacting the network.
if ! git -C "${GLIB_SRC}" rev-parse FETCH_HEAD >/dev/null 2>&1; then
  git -C "${GLIB_SRC}" fetch . HEAD >/dev/null
fi

for patch in "${GLIB_PATCHES[@]}"; do
  if git -C "${GLIB_SRC}" apply --check "${patch}" 2>/dev/null; then
    git -C "${GLIB_SRC}" apply "${patch}"
  elif git -C "${GLIB_SRC}" apply --reverse --check "${patch}" 2>/dev/null; then
    echo "GLib patch 已应用，继续使用：${patch}"
  else
    echo "GLib patch 无法应用或识别状态：${patch}" >&2
    exit 1
  fi
done

# deps.py uses the bootstrap toolchain bundle, but builds the SDK packages
# from their pinned source repositories.  Wipe only its generated partial
# SDK state so a changed patch cannot be hidden by an old manifest.
rm -rf "${BUILD_DEPS_DIR}/_sdk.out" "${BUILD_DEPS_DIR}/_sdk.tmp"
FRIDA_DEPS="${BUILD_DEPS_DIR}" python3 "${SRC}/releng/deps.py" build \
  --bundle=sdk \
  --build=linux-x86_64 \
  --host="${HOST}" \
  --only=glib \
  -v

[[ -f "${ARCHIVE}" ]] || { echo "GLib SDK archive 未生成：${ARCHIVE}" >&2; exit 1; }
tar -xJf "${ARCHIVE}" -C "${SDK_DIR}"
printf '%s\n' "${GLIB_COMMIT} ${PATCH_DIGEST}" > "${STAMP}"
echo "已用源码构建并覆盖 GLib/GObject/GIO：${SDK_DIR}"
