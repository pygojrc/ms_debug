#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${ROOT_DIR}/toolchains/android-ndk-r29}"
ARCHIVE="${ROOT_DIR}/toolchains/android-ndk-r29-linux.zip"
URL="${ANDROID_NDK_URL:-https://dl.google.com/android/repository/android-ndk-r29-linux.zip}"

if [[ -f "${DEST}/source.properties" ]] && grep -q '^Pkg.Revision = 29\.' "${DEST}/source.properties"; then
  echo "Android NDK r29 已存在：${DEST}"
  exit 0
fi

mkdir -p "$(dirname "${DEST}")"
if [[ ! -f "${ARCHIVE}" ]]; then
  command -v curl >/dev/null || { echo '缺少 curl，无法下载 Android NDK' >&2; exit 1; }
  curl -L --fail --retry 3 -o "${ARCHIVE}" "${URL}"
fi
command -v unzip >/dev/null || { echo '缺少 unzip，无法解压 Android NDK' >&2; exit 1; }
unzip -q -n "${ARCHIVE}" -d "$(dirname "${DEST}")"
[[ -f "${DEST}/source.properties" ]] || { echo "NDK 解压后未找到 source.properties：${DEST}" >&2; exit 1; }
grep -q '^Pkg.Revision = 29\.' "${DEST}/source.properties" || { echo '下载的 NDK 不是 r29' >&2; exit 1; }
echo "Android NDK r29 已准备：${DEST}"
