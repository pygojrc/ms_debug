#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "verify-artifacts.sh 仅供 GitHub Actions 使用" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_TYPE="release"
HOST=""
ARCH=""
usage() {
  echo "用法：$0 [-b release|debug] --host <host>" >&2
  echo "host: android-arm64 android-x86_64 linux-x86_64" >&2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type) BUILD_TYPE="${2:?缺少 build type}"; shift 2 ;;
    --host) HOST="${2:?缺少 host}"; shift 2 ;;
    -a|--arch) ARCH="${2:?缺少 arch}"; shift 2 ;;   # 兼容旧参数
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
  *) echo "verify-artifacts.sh 不处理 host：${HOST}（windows 走 verify-artifacts.ps1）" >&2; exit 2 ;;
esac
[[ "${BUILD_TYPE}" == release || "${BUILD_TYPE}" == debug ]] || { usage; exit 2; }

OUT_DIR="${ROOT_DIR}/out/${BUILD_TYPE}/${HOST}"
outputs=(ms_server gadget.so frida-code-inject frida-so-inject)
strings_file="$(mktemp)"
trap 'rm -f "${strings_file}"' EXIT
for output in "${outputs[@]}"; do
  path="${OUT_DIR}/${output}"
  [[ -s "${path}" ]] || { echo "缺少产物：${path}" >&2; exit 1; }
  file "${path}"
  readelf -h "${path}" >/dev/null
  sha256sum "${path}"
  strings -a "${path}" >> "${strings_file}"
done

# 发布版必须包含功能性改动，但不得包含调试日志和停止点。
grep -Fq 'gogogo' "${strings_file}"
grep -Fq 'msagent' "${strings_file}"
grep -Fq 'Jit thread pool worker thread' "${strings_file}"
! grep -Fq 'MYOBS' "${strings_file}"
! grep -Fq 'mygadget.stop.' "${strings_file}"
! grep -Fq 'mygadget.nop' "${strings_file}"
! grep -Eq 'Connection (Listener|Handler)' "${strings_file}"

if [[ "${BUILD_TYPE}" == debug ]]; then
  grep -Fq 'MYOBS' "${strings_file}"
  grep -Fq 'mygadget.stop.' "${strings_file}"
  grep -Fq 'mygadget.nop' "${strings_file}"
fi
echo "产物验证完成：build_type=${BUILD_TYPE} host=${HOST}"
