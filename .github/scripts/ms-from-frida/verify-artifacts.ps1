# Windows x86_64 产物验证。仅供 GitHub Actions（windows-latest）调用。
param(
  [string]$BuildType = "release"
)

$ErrorActionPreference = "Stop"
if ($env:GITHUB_ACTIONS -ne "true") {
  Write-Error "verify-artifacts.ps1 仅供 GitHub Actions 使用"
  exit 1
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$OutDir = Join-Path $RepoRoot "out\$BuildType\windows-x86_64"
$outputs = @("ms_server.exe", "gadget.dll", "frida-inject.exe")

# 以 Latin1 读原始字节做 ASCII 字符串匹配，避免外部 strings 工具依赖。
function Get-BinaryText([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  return [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
}

$texts = @()
foreach ($output in $outputs) {
  $path = Join-Path $OutDir $output
  if (-not (Test-Path $path)) { Write-Error "缺少产物：$path"; exit 1 }
  if ((Get-Item $path).Length -le 0) { Write-Error "产物为空：$path"; exit 1 }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
    Write-Error "不是 PE 文件：$path"
    exit 1
  }
  Get-FileHash -Algorithm SHA256 -Path $path | ForEach-Object { Write-Host "$($_.Hash)  $path" }
  $texts += Get-BinaryText $path
}
$all = $texts -join "`n"

# 发布版必须包含功能性改动，但不得包含调试日志和停止点。
if (-not $all.Contains("gogogo")) { Write-Error "缺少 gogogo 标识"; exit 1 }
if (-not $all.Contains("msagent")) { Write-Error "缺少 msagent 标识"; exit 1 }
if (-not $all.Contains("Jit thread pool worker thread")) { Write-Error "缺少线程名标识"; exit 1 }
if ($all.Contains("MYOBS")) { Write-Error "release 产物包含 MYOBS"; exit 1 }
if ($all.Contains("mygadget.stop.")) { Write-Error "release 产物包含二分停止点"; exit 1 }
if ($all.Contains("mygadget.nop")) { Write-Error "release 产物包含 mygadget.nop"; exit 1 }

if ($BuildType -eq "debug") {
  if (-not $all.Contains("MYOBS")) { Write-Error "debug 产物缺少 MYOBS"; exit 1 }
  if (-not $all.Contains("mygadget.stop.")) { Write-Error "debug 产物缺少二分停止点"; exit 1 }
  if (-not $all.Contains("mygadget.nop")) { Write-Error "debug 产物缺少 mygadget.nop"; exit 1 }
}
Write-Host "产物验证完成：build_type=$BuildType host=windows-x86_64"
