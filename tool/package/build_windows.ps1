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
#
# Ask vswhere where Visual Studio actually is instead of guessing a path. The
# version folder is not stable: this was written against "2022\Enterprise" and
# silently found nothing once the CI image moved to Visual Studio 2026, which
# installs into "18\Enterprise" under Program Files - and a build that only
# warns ships a package that cannot start (#3).
$required = @("msvcp140.dll", "vcruntime140.dll")
$optional = @(
  "msvcp140_1.dll", "msvcp140_2.dll", "msvcp140_atomic_wait.dll",
  "msvcp140_codecvt_ids.dll", "vcruntime140_1.dll"
)

$crtRoots = @()
$vswhere = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
  "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($vswhere) {
  # -products * covers BuildTools, Community and Enterprise; the C++ workload
  # can be installed into any of them. vswhere reports the exact install path
  # including the edition folder, so both 18\BuildTools and 18\Enterprise are
  # found without guessing at a layout.
  foreach ($install in @(& $vswhere -all -products '*' -property installationPath)) {
    if ($install -and (Test-Path $install)) {
      $crtRoots += Get-ChildItem (Join-Path $install 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue
    }
  }
}

# Fallback for a machine with no vswhere: search both Program Files roots. The
# edition folder is not always directly under the version - VS 2026 BuildTools
# lands in 18\BuildTools while Enterprise is 18\Enterprise - so match the CRT
# folder at any depth below the version directory.
if (-not $crtRoots) {
  $crtRoots = @(
    (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio')
  ) | Where-Object { $_ -and (Test-Path $_) } |
    ForEach-Object {
      # The CRT folder is the match, so the architecture is its parent - arm64
      # and x86 installs sit alongside x64 and must not be picked up.
      Get-ChildItem $_ -Directory -Recurse -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Where-Object { $_.Parent.Name -eq 'x64' }
    }
}

$crt = $crtRoots | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) {
  throw "No MSVC runtime found to bundle. ggml.dll needs $($required -join ' and '), so the package would crash on launch. Install the Visual C++ Redistributable, or the 'Desktop development with C++' workload, and build again (#3)."
}

foreach ($dll in $required + $optional) {
  $src = Join-Path $crt.FullName $dll
  if (Test-Path $src) { Copy-Item $src (Join-Path $bundle $dll) -Force }
}

$stillMissing = $required | Where-Object { -not (Test-Path (Join-Path $bundle $_)) }
if ($stillMissing) {
  throw "The MSVC runtime in $($crt.FullName) is missing $($stillMissing -join ', '). Refusing to package a bundle that cannot start (#3)."
}
Write-Host "==> bundled the MSVC runtime from $($crt.FullName)"

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
