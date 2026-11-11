#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "prepare-source.sh 仅供 GitHub Actions 使用" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${ROOT_DIR}/ms_from_frida/config/versions.env"
PYTHON="${PYTHON:-python3}"

BUILD_TYPE="release"
HOST=""
ARCH=""
SOURCE_DIR=""
usage() {
  echo "用法：$0 [-b release|debug] --host <host> -s <source-dir>" >&2
  echo "host: android-arm64 android-x86_64 linux-x86_64 windows-x86_64" >&2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type) BUILD_TYPE="${2:?缺少 build type}"; shift 2 ;;
    --host) HOST="${2:?缺少 host}"; shift 2 ;;
    -a|--arch) ARCH="${2:?缺少 arch}"; shift 2 ;;   # 兼容旧参数，等价 android-<arch>
    -s|--source) SOURCE_DIR="${2:?缺少 source dir}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

# 未显式给 --host 时，允许用旧的 --arch 推导 android host。
if [[ -z "${HOST}" ]]; then
  [[ -n "${ARCH}" ]] || { usage; exit 2; }
  HOST="android-${ARCH}"
fi
case "${HOST}" in
  android-arm64|android-x86_64|linux-x86_64|windows-x86_64) ;;
  *) echo "不支持的 host：${HOST}" >&2; usage; exit 2 ;;
esac
PLATFORM="${HOST%%-*}"     # android | linux | windows
[[ "${BUILD_TYPE}" == release || "${BUILD_TYPE}" == debug ]] || { usage; exit 2; }
[[ -n "${SOURCE_DIR}" ]] || { usage; exit 2; }
SOURCE_DIR="$(realpath -m "${SOURCE_DIR}")"

clone_at() {
  local url="$1" dir="$2" rev="$3"
  local path="${SOURCE_DIR}/subprojects/${dir}"
  if [[ ! -d "${path}/.git" && ! -f "${path}/.git" ]]; then
    git clone --no-checkout "${url}" "${path}"
  fi
  if ! git -C "${path}" cat-file -e "${rev}^{commit}" 2>/dev/null; then
    git -C "${path}" fetch origin "${rev}"
  fi
  git -C "${path}" checkout --detach "${rev}"
}

mkdir -p "$(dirname "${SOURCE_DIR}")"
if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone --branch "${FRIDA_TAG}" --recurse-submodules \
    https://github.com/frida/frida.git "${SOURCE_DIR}"
fi
git -C "${SOURCE_DIR}" checkout --detach "${FRIDA_ROOT_COMMIT}"
git -C "${SOURCE_DIR}" submodule update --init --recursive
[[ "$(git -C "${SOURCE_DIR}" rev-parse HEAD)" == "${FRIDA_ROOT_COMMIT}" ]] || {
  echo "Frida 根仓库 commit 不符合锁定值" >&2; exit 1;
}

# 固定子模块和 deps.py 使用的源码版本，避免 tag 或浮动分支漂移。
clone_at https://github.com/frida/frida-core.git frida-core "${FRIDA_CORE_COMMIT}"
clone_at https://github.com/frida/frida-gum.git frida-gum "${FRIDA_GUM_COMMIT}"
clone_at https://github.com/frida/glib.git glib "${GLIB_COMMIT}"
clone_at https://github.com/frida/libffi.git libffi "${LIBFFI_COMMIT}"
clone_at https://github.com/frida/libiconv.git libiconv "${LIBICONV_COMMIT}"
clone_at https://github.com/frida/termux-elf-cleaner.git termux-elf-cleaner "${TERMUX_ELF_CLEANER_COMMIT}"

link_dep() {
  local parent="$1" name="$2"
  local path="${SOURCE_DIR}/subprojects/${parent}/subprojects/${name}"
  mkdir -p "$(dirname "${path}")"
  [[ -e "${path}" ]] || ln -s "../../${name}" "${path}"
}
link_dep frida-core glib
link_dep frida-core libffi
link_dep frida-core termux-elf-cleaner
link_dep frida-gum glib
link_dep frida-gum libffi

download_prebuilt() {
  local bundle="$1" machine="$2" location="$3"
  "${PYTHON}" "${SOURCE_DIR}/releng/deps.py" sync "${bundle}" "${machine}" "${location}"
}

# 按 host 同步预编译依赖；windows 的 SDK 带 vscrt config 后缀，工具链固定映射到 windows-x86。
case "${PLATFORM}" in
  android)
    download_prebuilt sdk "${HOST}" "${SOURCE_DIR}/deps/sdk-${HOST}"
    download_prebuilt toolchain linux-x86_64 "${SOURCE_DIR}/deps/toolchain-linux-x86_64"
    ;;
  linux)
    download_prebuilt sdk "${HOST}" "${SOURCE_DIR}/deps/sdk-${HOST}"
    download_prebuilt toolchain linux-x86_64 "${SOURCE_DIR}/deps/toolchain-linux-x86_64"
    ;;
  windows)
    download_prebuilt sdk "${HOST}-mt" "${SOURCE_DIR}/deps/sdk-${HOST}-mt"
    download_prebuilt toolchain "${HOST}" "${SOURCE_DIR}/deps/toolchain-${HOST}"
    ;;
esac

apply_patch() {
  local repo="$1" patch="$2"
  git -C "${SOURCE_DIR}/subprojects/${repo}" apply --check \
    --whitespace=nowarn "${ROOT_DIR}/ms_from_frida/patches/${patch}"
  git -C "${SOURCE_DIR}/subprojects/${repo}" apply \
    --whitespace=nowarn "${ROOT_DIR}/ms_from_frida/patches/${patch}"
}

# 所有平台共用：名字统一改造、控制端口、gum runtime；debug 补丁跟随 profile。
apply_common() {
  apply_patch frida-core release/process-name/frida-core.patch
  apply_patch frida-core release/control-port/frida-core.patch
  apply_patch frida-gum release/gum-runtime/frida-gum.patch
  apply_patch glib release/thread-name/glib.patch
  apply_patch frida-gum release/thread-name/frida-gum.patch
  apply_patch frida-core release/thread-name/frida-core.patch
  apply_patch frida-core release/exceptor-handler-only/frida-core.patch
}

# 仅 linux 内核语义可用的补丁：memfd 命名、注入分组停止、自研 helper 注入。
apply_linux_family() {
  apply_patch frida-core release/agent-memfd-name/frida-core.patch
  apply_patch frida-core release/injection-group-stop/frida-core.patch
  apply_patch frida-core release/helper-injection/frida-core.patch
}

# 仅 windows 需要的标识改名与注入修复。
apply_windows_family() {
  apply_patch frida-core release/windows-identity/frida-core.patch
}

apply_debug() {
  apply_patch frida-core debug/bisect/frida-core.patch
  apply_patch frida-gum debug/logging/frida-gum.patch
  apply_patch glib debug/bisect/glib.patch
}

apply_common
if [[ "${PLATFORM}" == android || "${PLATFORM}" == linux ]]; then
  apply_linux_family
fi
if [[ "${PLATFORM}" == windows ]]; then
  apply_windows_family
fi
if [[ "${BUILD_TYPE}" == debug ]]; then
  apply_debug
fi

# helper.dex 与 ARM64 helper payload 只服务于 android 目标。
if [[ "${PLATFORM}" == android ]]; then
  cp -a "${ROOT_DIR}/ms_from_frida/files/frida-core/." \
    "${SOURCE_DIR}/subprojects/frida-core/"
fi

printf '源码准备完成：build_type=%s host=%s source=%s\n' \
  "${BUILD_TYPE}" "${HOST}" "${SOURCE_DIR}"
