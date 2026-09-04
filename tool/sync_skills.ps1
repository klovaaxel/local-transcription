# Mirror .agents/skills (written by the skills installer) into .claude/skills,
# which is the only place Claude Code discovers project skills.
# Run after installing or updating any skill.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root ".agents\skills"
$dst = Join-Path $root ".claude\skills"

if (-not (Test-Path $src)) { throw "Missing $src" }
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

$n = (Get-ChildItem $dst -Directory).Count
Write-Host "Synced $n skills to .claude\skills"
