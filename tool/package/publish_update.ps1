<#
.SYNOPSIS
  Publish a packaged release as a self-updatable GitHub release.

.DESCRIPTION
  Collects the artifacts in dist\ produced by build_windows.ps1,
  build_android.ps1 and (in WSL) build_linux_deb.sh, hashes them, writes
  dist\updates.json, and publishes a GitHub release on
  https://github.com/klovaaxel/local-transcription whose latest download URL
  is exactly what the app's updater (lib/update/) reads.

  Artifacts are optional: whatever exists for a platform goes into the
  manifest, so Windows/Android can ship before Linux is built and vice
  versa. Run this AFTER bumping pubspec.yaml - the version and build number
  there name both the tag and the manifest.

.EXAMPLE
  pwsh -File tool\package\publish_update.ps1
  pwsh -File tool\package\publish_update.ps1 -Notes "Fastare sammanfattning, battre live-text."
  pwsh -File tool\package\publish_update.ps1 -WhatIf    # writes updates.json, no upload
#>
[CmdletBinding()]
param(
  # Repo slug the app's update feed points at. Changing this means changing
  # updateRepoSlug in lib/update/update_feed.dart too.
  [string]$Repo = 'klovaaxel/local-transcription',

  # Release notes shown with the tag and written into the manifest.
  [string]$Notes = '',

  # Build updates.json and print the release plan without uploading.
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$dist = Join-Path $PSScriptRoot '..\..\dist'

# Version and build come from pubspec: "1.0.0+1" -> tag v1.0.0.
$versionLine = (Select-String -Path (Join-Path $PSScriptRoot '..\..\pubspec.yaml') `
  -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$appVersion = ($versionLine -split '\+')[0]
$buildNumber = if ($versionLine -match '\+') { [int](($versionLine -split '\+')[1]) } else { 0 }

# file -> manifest key. The app picks its own platform from these keys; the
# portable zip and the per-ABI split APKs ship on the release but are not in
# the manifest: a portable copy cannot self-install, and the updater installs
# exactly one universal APK.
$patterns = [ordered]@{
  'windows' = "Forelasning-$appVersion-windows-x64-setup.exe"
  'android' = "Forelasning-$appVersion-android-universal.apk"
  'linux'   = "forelasning_${appVersion}-*_amd64.deb"
  'zip'     = "Forelasning-$appVersion-windows-x64.zip"
  'splits'  = "Forelasning-$appVersion-android-*.apk"
}

# Get-ChildItem -Filter takes a wildcard, not a pattern, so the split APKs are
# picked up by the broad android-* filter and narrowed here. Do it this way
# rather than with a character class: [0-9a] is not honoured on every platform
# PowerShell runs on, and the universal APK is already claimed under 'android'
# so it must not be attached twice.
$excludes = @{
  'splits' = @('*-universal.apk')
}

$manifestArtifacts = [ordered]@{}
$releaseFiles = New-Object System.Collections.Generic.List[string]

foreach ($key in $patterns.Keys) {
  $pattern = $patterns[$key]
  $files = @(Get-ChildItem $dist -Filter $pattern -File -ErrorAction SilentlyContinue)
  if (-not $files) {
    if (Test-Path (Join-Path $dist $pattern)) {
      $files = @(Get-Item (Join-Path $dist $pattern))
    }
  }
  # Exclude AFTER the literal-path fallback above, not before it. Test-Path and
  # Get-Item treat the * in a pattern as a wildcard, so that fallback finds the
  # universal APK again and hands back exactly what the filter had just
  # narrowed away - which would attach it twice and hide the missing splits.
  if ($excludes.ContainsKey($key)) {
    foreach ($exclude in $excludes[$key]) {
      $files = @($files | Where-Object { $_.Name -notlike $exclude })
    }
  }
  if (-not $files) {
    if ($key -in @('windows', 'android', 'linux')) {
      Write-Warning "No $key artifact in dist\ matching $pattern - manifest will lack $key."
    }
    if ($key -eq 'splits') {
      # Every release so far has shipped the universal APK only, because this
      # lookup never matched. It works, but it is 201 MB where the per-ABI
      # file is 39-107 MB, and docs/INSTALL.md tells emulator and old-phone
      # testers to install a file that was never attached (#1). A release
      # without them is a release that wastes a tester's download.
      throw "No per-ABI split APKs in dist\ matching $pattern after excluding $($excludes['splits'] -join ', '). Build them with: flutter build apk --release --split-per-abi"
    }
    continue
  }
  foreach ($file in $files) {
    $releaseFiles.Add($file.FullName)
    if ($key -notin @('windows', 'android', 'linux')) {
      continue
    }
    $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
    $manifestArtifacts[$key] = @{
      file   = $file.Name
      sha256 = $hash
    }
    Write-Host ('  {0,-8} {1}  {2}' -f $key, $file.Name, $hash.Substring(0, 12) + '...')
  }
}

if ($manifestArtifacts.Count -eq 0) {
  throw "No artifacts found in $dist. Run the build scripts first."
}

$manifest = [ordered]@{
  schema  = 1
  version = $appVersion
  build   = $buildNumber
  notes   = $Notes
  artifacts = $manifestArtifacts
}

$manifestPath = Join-Path $dist 'updates.json'
$json = $manifest | ConvertTo-Json -Depth 5
if ($PSVersionTable.PSVersion.Major -ge 7) {
  Set-Content -Path $manifestPath -Value $json -Encoding utf8NoBOM
} else {
  Set-Content -Path $manifestPath -Value $json -Encoding UTF8
}
Write-Host "==> updates.json written to $manifestPath"
$json | Write-Host

$releaseFiles.Add($manifestPath)
$tag = "v$appVersion"

if ($WhatIf) {
  Write-Host ''
  Write-Host "==> WhatIf: would create release $tag on $Repo with $($releaseFiles.Count) files."
  return
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
  throw 'gh CLI not found. Install it (winget install GitHub.cli) and run gh auth login, or create the release by hand from the file list above.'
}

# Idempotent-ish: an existing release with this tag means the version was
# already published. Fail loudly rather than overwrite.
$existing = & gh release view $tag --repo $Repo 2>$null
if ($LASTEXITCODE -eq 0) {
  throw "Release $tag already exists on $Repo. Bump pubspec.yaml before publishing again."
}

$releaseArgs = @(
  'release', 'create', $tag,
  '--repo', $Repo,
  '--title', "Forelasning $appVersion"
)
if ($Notes) {
  $releaseArgs += @('--notes', $Notes)
} else {
  $releaseArgs += @('--notes', "Forelasning $appVersion (bygg $buildNumber).")
}
$releaseArgs += $releaseFiles

Write-Host "==> gh release create $tag on $Repo"
& gh @releaseArgs
if ($LASTEXITCODE -ne 0) {
  throw "gh release create failed ($LASTEXITCODE). Remove a half-created release with: gh release delete $tag --repo $Repo"
}

Write-Host ''
Write-Host "==> Published. The app will pick this up from"
Write-Host "    https://github.com/$Repo/releases/latest/download/updates.json"
