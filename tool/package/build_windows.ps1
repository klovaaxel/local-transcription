<#
.SYNOPSIS
  Build the Windows release bundle and wrap it in an installer for beta testers.

.DESCRIPTION
  Produces two artifacts in dist\:
    Forelasning-<version>-windows-x64-setup.exe   Inno Setup, per-user, no admin
    Forelasning-<version>-windows-x64.zip         portable, unzip and run

  The installer is unsigned. SmartScreen will warn on first run until the
  download has enough reputation; docs/INSTALL.md tells testers how to
  get past it. Signing needs an EV/OV code-signing certificate.

.EXAMPLE
  pwsh -File tool\package\build_windows.ps1
#>
[CmdletBinding()]
param(
  # Skip flutter build and package whatever is already in build\windows.
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$bundle = Join-Path $repo 'build\windows\x64\runner\Release'
$dist = Join-Path $repo 'dist'
$iss = Join-Path $PSScriptRoot 'forelasning.iss'

# The JVM on this machine cannot open an AF_UNIX socket under %LOCALAPPDATA%\Temp
# (endpoint protection), which breaks Gradle. Irrelevant for the Windows desktop
# build, but keep the whole toolchain on one temp dir so behaviour matches.
if (-not $env:TMP -or $env:TMP -like "$env:LOCALAPPDATA\Temp*") {
  New-Item -ItemType Directory -Force -Path 'C:\Temp\build' | Out-Null
  $env:TMP = 'C:\Temp\build'; $env:TEMP = 'C:\Temp\build'
}

# Version from pubspec: "1.0.0+1" -> 1.0.0 for the installer, +1 kept in the name.
$versionLine = (Select-String -Path (Join-Path $repo 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$appVersion = ($versionLine -split '\+')[0]
$buildNumber = if ($versionLine -match '\+') { ($versionLine -split '\+')[1] } else { '0' }
Write-Host "==> Version $appVersion (build $buildNumber)"

if (-not $SkipBuild) {
  Write-Host '==> flutter build windows --release'
  & flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
}

if (-not (Test-Path (Join-Path $bundle 'lecture_local.exe'))) {
  throw "No bundle at $bundle - run without -SkipBuild"
}

# Ship the MSVC runtime beside the exe. ggml.dll imports MSVCP140/VCRUNTIME140,
# and Flutter does not bundle them - on a machine without the Visual C++
# Redistributable the app dies at launch with a missing-DLL box. App-local
# deployment is the licensed way to do this and needs no admin, unlike running
# the redist installer.
$crt = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT" -Directory -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1
if ($crt) {
  $crtDlls = @(
    "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll",
    "msvcp140_atomic_wait.dll", "msvcp140_codecvt_ids.dll",
    "vcruntime140.dll", "vcruntime140_1.dll"
  )
  foreach ($dll in $crtDlls) {
    $src = Join-Path $crt.FullName $dll
    if (Test-Path $src) { Copy-Item $src (Join-Path $bundle $dll) -Force }
  }
  Write-Host "==> bundled the MSVC runtime from $($crt.Name)"
} else {
  Write-Warning "Visual C++ redistributable DLLs not found; testers will need the VC++ Redistributable installed."
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null

# Portable zip, for a tester who cannot or will not run an installer.
$zip = Join-Path $dist "Forelasning-$appVersion-windows-x64.zip"
Write-Host "==> Packing $zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -CompressionLevel Optimal

# Inno Setup installer.
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  throw "ISCC.exe not found. Install Inno Setup 6: winget install --id JRSoftware.InnoSetup --scope user"
}

Write-Host "==> $iscc"
& $iscc `
  "/DMyAppVersion=$appVersion" `
  "/DMyBundleDir=$bundle" `
  "/DMyOutputDir=$dist" `
  $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host '==> Artifacts'
Get-ChildItem $dist -File | Where-Object { $_.Name -like 'Forelasning-*' } |
  Select-Object Name, @{n='Size';e={'{0:N1} MB' -f ($_.Length/1MB)}}, LastWriteTime |
  Format-Table -AutoSize
