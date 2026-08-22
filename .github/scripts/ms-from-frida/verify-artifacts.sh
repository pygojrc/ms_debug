#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "verify-artifacts.sh 仅供 GitHub Actions 使用" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_TYPE="release"
ARCH=""
usage() { echo "用法：$0 [-b release|debug] -a arm64|x86_64" >&2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type) BUILD_TYPE="${2:?缺少 build type}"; shift 2 ;;
    -a|--arch) ARCH="${2:?缺少 arch}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ "${BUILD_TYPE}" == release || "${BUILD_TYPE}" == debug ]] || { usage; exit 2; }
[[ "${ARCH}" == arm64 || "${ARCH}" == x86_64 ]] || { usage; exit 2; }
OUT_DIR="${ROOT_DIR}/out/${BUILD_TYPE}/android-${ARCH}"
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
grep -Fq 'Jit thread pool worker thread' "${strings_file}"
grep -Fq 'msagent.so' "${strings_file}"
grep -Fq 'gogogo' "${strings_file}"
! grep -Fq 'MYOBS' "${strings_file}"
! grep -Fq 'mygadget.stop.' "${strings_file}"
! grep -Fq 'mygadget.nop' "${strings_file}"
! grep -Eq 'Connection (Listener|Handler)' "${strings_file}"

if [[ "${BUILD_TYPE}" == debug ]]; then
  grep -Fq 'MYOBS' "${strings_file}"
  grep -Fq 'mygadget.stop.' "${strings_file}"
  grep -Fq 'mygadget.nop' "${strings_file}"
fi
echo "产物验证完成：build_type=${BUILD_TYPE} arch=${ARCH}"
