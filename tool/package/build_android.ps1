<#
.SYNOPSIS
  Build signed release APKs for beta testers to sideload.

.DESCRIPTION
  Produces one APK per ABI in dist\. arm64-v8a is the one to hand out: every
  Android phone sold in the last several years is arm64. The others exist for
  old 32-bit devices (armeabi-v7a) and emulators (x86_64).

  Signing comes from android\key.properties. Without that file the release
  build falls back to the debug key - fine to run, not fine to ship, because a
  debug-signed install cannot later be upgraded by a properly signed one.

  Not an app bundle (.aab): testers install these directly, and an .aab has to
  go through Play to become installable.

.EXAMPLE
  pwsh -File tool\package\build_android.ps1
#>
[CmdletBinding()]
param(
  # Package whatever is already in build\app\outputs instead of rebuilding.
  [switch]$SkipBuild,

  # Allow a debug-signed APK when the release keystore is unavailable. For local
  # smoke tests only - never for anything handed to a tester.
  [switch]$AllowDebugSigning
)

$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$apkDir = Join-Path $repo 'build\app\outputs\flutter-apk'
$dist = Join-Path $repo 'dist'

# Gradle's daemon talks to its client over an AF_UNIX socket placed in the JVM
# temp dir. On this machine a connect() inside %LOCALAPPDATA%\Temp fails with
# "Invalid argument" (endpoint protection), which surfaces as the useless
# "Unable to establish loopback connection". Any temp dir outside it works.
New-Item -ItemType Directory -Force -Path 'C:\Temp\gradle' | Out-Null
$env:TMP = 'C:\Temp\gradle'
$env:TEMP = 'C:\Temp\gradle'

# The llm_llamacpp build hook unpacks the llama.cpp release with unzip(1).
if (-not (Get-Command unzip -ErrorAction SilentlyContinue)) {
  $gitUsrBin = 'C:\Program Files\Git\usr\bin'
  if (Test-Path (Join-Path $gitUsrBin 'unzip.exe')) {
    $env:PATH = "$gitUsrBin;$env:PATH"
  } else {
    Write-Warning "unzip not on PATH; the llm_llamacpp hook needs it (Git for Windows provides it)."
  }
}

$jdk21 = "$env:LOCALAPPDATA\Programs\jdk\jdk-21.0.9+10"
if (Test-Path $jdk21) { $env:JAVA_HOME = $jdk21 }

$keyProps = Join-Path $repo 'android\key.properties'
if (Test-Path $keyProps) {
  Write-Host '==> Signing with the release key from android\key.properties'
} elseif ($AllowDebugSigning) {
  Write-Warning 'android\key.properties missing - producing a DEBUG-SIGNED APK because -AllowDebugSigning was passed. Do not hand it to testers.'
} else {
  # Stopping here on purpose. A debug-signed APK installs and looks fine, but it
  # can never be upgraded in place by a properly signed build, so a tester who
  # gets one has to uninstall and lose their lectures later.
  throw "android\key.properties is missing - the release build would fall back to the debug key. Restore the keystore, or pass -AllowDebugSigning if you really want an unshippable local build."
}

$versionLine = (Select-String -Path (Join-Path $repo 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$appVersion = ($versionLine -split '\+')[0]
Write-Host "==> Version $appVersion"

if (-not $SkipBuild) {
  Write-Host '==> flutter build apk --release --split-per-abi'
  & flutter build apk --release --split-per-abi
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed ($LASTEXITCODE)" }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null

$apks = Get-ChildItem $apkDir -Filter 'app-*-release.apk' -ErrorAction SilentlyContinue
if (-not $apks) { throw "No APKs in $apkDir" }

foreach ($apk in $apks) {
  $abi = $apk.BaseName -replace '^app-', '' -replace '-release$', ''
  $target = Join-Path $dist "Forelasning-$appVersion-android-$abi.apk"
  Copy-Item $apk.FullName $target -Force
}

# Verify what we are about to hand out is actually signed with the release key,
# not the debug key the gradle fallback would have used.
$buildTools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -First 1
$apksigner = if ($buildTools) { Join-Path $buildTools.FullName 'apksigner.bat' } else { $null }

if ($apksigner -and (Test-Path $apksigner)) {
  $main = Join-Path $dist "Forelasning-$appVersion-android-arm64-v8a.apk"
  if (Test-Path $main) {
    Write-Host ''
    Write-Host '==> apksigner verify (arm64-v8a)'
    # apksigner writes JVM warnings to stderr, which PowerShell would otherwise
    # turn into a terminating error under $ErrorActionPreference = 'Stop'.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $out = & $apksigner verify --print-certs $main 2>$null
      $certLines = $out | Select-String 'certificate DN|certificate SHA-256'
      if ($certLines) {
        $certLines | ForEach-Object { Write-Host "   $_" }
      } else {
        Write-Warning 'apksigner printed no certificate info.'
      }
      if ($out -match 'CN=Axel Karlsson') {
        Write-Host '   -> release key OK'
      } elseif ($AllowDebugSigning) {
        Write-Warning 'This APK is NOT signed with the release key. Do not hand it out.'
      } else {
        throw 'This APK is not signed with the release key - refusing to leave it in dist/ where it could be handed out.'
      }
    } finally {
      $ErrorActionPreference = $prev
    }
  }
} else {
  Write-Warning 'apksigner not found; skipped signature verification.'
}

Write-Host ''
Write-Host '==> Artifacts'
Get-ChildItem $dist -Filter '*.apk' |
  Select-Object Name, @{n='Size';e={'{0:N1} MB' -f ($_.Length/1MB)}} |
  Format-Table -AutoSize
