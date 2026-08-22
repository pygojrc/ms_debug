#!/usr/bin/env bash
set -euo pipefail

# 该脚本只允许由 GitHub Actions 调用；本地不提供构建入口。
[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
  echo "prepare-source.sh 仅供 GitHub Actions 使用" >&2
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
  local parent="$1" name="$2" path="${SOURCE_DIR}/subprojects/${parent}/subprojects/${name}"
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
  python3 "${SOURCE_DIR}/releng/deps.py" sync "${bundle}" "${machine}" "${location}"
}
download_prebuilt sdk "${HOST}" "${SOURCE_DIR}/deps/sdk-${HOST}"
download_prebuilt toolchain linux-x86_64 "${SOURCE_DIR}/deps/toolchain-linux-x86_64"

apply_patch() {
  local repo="$1" patch="$2"
  git -C "${SOURCE_DIR}/subprojects/${repo}" apply --check \
    --whitespace=nowarn "${ROOT_DIR}/ms_from_frida/patches/${patch}"
  git -C "${SOURCE_DIR}/subprojects/${repo}" apply \
    --whitespace=nowarn "${ROOT_DIR}/ms_from_frida/patches/${patch}"
}

# 顺序体现 patch 的依赖关系；debug patch 永远排在对应 release patch 之后。
apply_patch frida-core release/agent-memfd-name/frida-core.patch
apply_patch frida-core release/injection-group-stop/frida-core.patch
apply_patch frida-core release/helper-injection/frida-core.patch
apply_patch frida-core release/thread-name/frida-core.patch
apply_patch frida-gum release/process-name/frida-gum.patch
apply_patch frida-gum release/gum-runtime/frida-gum.patch
apply_patch frida-gum release/thread-name/frida-gum.patch
apply_patch glib release/thread-name/glib.patch
if [[ "${BUILD_TYPE}" == debug ]]; then
  apply_patch frida-core debug/bisect/frida-core.patch
  apply_patch frida-gum debug/logging/frida-gum.patch
  apply_patch glib debug/bisect/glib.patch
fi

# helper.dex 是已审计的架构无关资源，随源码一起进入 Frida 的资源打包。
cp -a "${ROOT_DIR}/ms_from_frida/files/frida-core/." \
  "${SOURCE_DIR}/subprojects/frida-core/"

printf '源码准备完成：build_type=%s host=%s source=%s\n' \
  "${BUILD_TYPE}" "${HOST}" "${SOURCE_DIR}"
