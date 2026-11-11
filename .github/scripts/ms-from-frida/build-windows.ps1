# Windows x86_64 构建入口。仅供 GitHub Actions（windows-latest）调用。
param(
  [string]$BuildType = "release",
  [Parameter(Mandatory = $true)][string]$SourceDir
)

$ErrorActionPreference = "Stop"
if ($env:GITHUB_ACTIONS -ne "true") {
  Write-Error "build-windows.ps1 仅供 GitHub Actions 使用"
  exit 1
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$SourceDir = (Resolve-Path $SourceDir).Path

# glib 的 gdbus-codegen 仍 import distutils（Python 3.12 已移除），由 setuptools 提供兼容层。
& python -m pip install --quiet --disable-pip-version-check setuptools
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 读取固定版本配置（versions.env 为 shell 格式的 KEY=VALUE）。
$versions = @{}
Get-Content (Join-Path $RepoRoot "ms_from_frida\config\versions.env") | ForEach-Object {
  if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)=(.*)$') {
    $versions[$Matches[1]] = $Matches[2].Trim()
  }
}
$GlibCommit = $versions["GLIB_COMMIT"]

# 从锁定源码构建 patched GLib；windows 上没有预编译的已打补丁 glib。
$glibBuild = Join-Path $env:RUNNER_TEMP "ms-glib-windows-x86_64"
$glibSrc = Join-Path $glibBuild "src\glib"
if (Test-Path $glibBuild) { Remove-Item -Recurse -Force $glibBuild }
New-Item -ItemType Directory -Force (Split-Path $glibSrc) | Out-Null
git clone --no-checkout https://github.com/frida/glib.git $glibSrc
git -C $glibSrc checkout --detach $GlibCommit
git -C $glibSrc fetch . HEAD 2>$null | Out-Null
git -C $glibSrc apply --whitespace=nowarn (Join-Path $RepoRoot "ms_from_frida\patches\release\thread-name\glib.patch")
if ($BuildType -eq "debug") {
  git -C $glibSrc apply --whitespace=nowarn (Join-Path $RepoRoot "ms_from_frida\patches\debug\bisect\glib.patch")
}
$env:FRIDA_DEPS = $glibBuild
& python "$SourceDir\releng\deps.py" build --bundle=sdk --build=windows-x86_64 --host=windows-x86_64 --only=glib -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 用自构建产物覆盖 SDK 里的 glib/gobject/gio 静态库。
$glibArchive = Join-Path $glibBuild "sdk-windows-x86_64-mt.tar.xz"
if (-not (Test-Path $glibArchive)) { Write-Error "自构建 GLib SDK 未生成：$glibArchive"; exit 1 }
tar -xJf $glibArchive -C (Join-Path $SourceDir "deps\sdk-windows-x86_64-mt")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# deps.py 用 FRIDA_DEPS 决定依赖缓存目录；自建 glib 完成后必须清除，
# 否则主 configure 会从临时目录找 SDK（缺 ngtcp2 等依赖）而失败。
Remove-Item Env:FRIDA_DEPS -ErrorAction SilentlyContinue

# native 构建的 server/gadget/inject auto 规则默认关闭，必须显式 enable。
# compat 需要 32 位 SDK 与工具链，先关闭以打通 64 位产物。
$buildDir = Join-Path $SourceDir "build\windows-x86_64"
$installPrefix = Join-Path $SourceDir "install\windows-x86_64"
$env:MESON_BUILD_ROOT = $buildDir
New-Item -ItemType Directory -Force $buildDir | Out-Null

Push-Location $SourceDir
try {
  & cmd /c "configure.bat --host=windows-x86_64 --prefix=$installPrefix --enable-server --enable-gadget --enable-inject --disable-frida-tools --disable-frida-python -- -Dlibdir=lib -Dfrida-core:compat=disabled -Dfrida-core:compiler_backend=disabled -Dfrida-core:barebone_backend=disabled"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  # Windows 上 meson 的 custom_target 名与 make 目标名不完全一致，直接构建全部启用目标；
  # 未启用的 portal/tools/python 不会进入构建，产物在下方按明确路径复制。
  & cmd /c "make.bat"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

$outDir = Join-Path $RepoRoot "out\$BuildType\windows-x86_64"
New-Item -ItemType Directory -Force $outDir | Out-Null
# Windows 不应用 linux-family 的 helper-injection 补丁，因此只产出官方注入工具 frida-inject；
# 自研 frida-code-inject / frida-so-inject 依赖 Linux helper 后端，暂不在 Windows 提供。
Copy-Item (Join-Path $buildDir "subprojects\frida-core\server\frida-server.exe") (Join-Path $outDir "ms_server.exe")
Copy-Item (Join-Path $buildDir "subprojects\frida-core\lib\gadget\frida-gadget.dll") (Join-Path $outDir "gadget.dll")
Copy-Item (Join-Path $buildDir "subprojects\frida-core\inject\frida-inject.exe") (Join-Path $outDir "frida-inject.exe")
Write-Host "windows-x86_64 构建完成：$outDir"
