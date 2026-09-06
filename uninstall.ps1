<#
.SYNOPSIS
  Uninstaller for claude-account on Windows.

.DESCRIPTION
  Removes the installed script, the .cmd shim and the user PATH entry.
  It NEVER removes your accounts (%USERPROFILE%\.claude-accounts) and NEVER
  touches your default Claude Code installation.

.EXAMPLE
  irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.ps1 | iex
#>

[CmdletBinding()]
param(
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

$BinName = 'claude-account'

function Write-Ok    { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "warning: $m" -ForegroundColor Yellow }

Write-Host 'Uninstalling claude-account' -ForegroundColor Cyan
Write-Host ''

if (-not $InstallDir) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $InstallDir = Join-Path $base 'Programs\claude-multi-account'
}

$removed = $false

# --- the installed files --------------------------------------------------

foreach ($leaf in @("$BinName.ps1", "$BinName.cmd")) {
    $path = Join-Path $InstallDir $leaf
    if (-not (Test-Path -LiteralPath $path)) { continue }
    # Only delete something that really is ours.
    $content = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ($content -notmatch 'claude-multi-account|CLAUDE_CONFIG_DIR') {
        Write-Warn2 "skipping $path - it does not look like claude-account"
        continue
    }
    Remove-Item -LiteralPath $path -Force
    Write-Ok "removed $path"
    $removed = $true
}

# Remove the install directory only if it is now empty.
if ((Test-Path -LiteralPath $InstallDir) -and
    -not (Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $InstallDir -Force
    Write-Ok "removed empty $InstallDir"
}

if (-not $removed) {
    Write-Host 'No installed files found.' -ForegroundColor DarkGray
}

# --- generated shortcuts (shims) -----------------------------------------

# Shims are tool artefacts, not user data, so they go. Accounts still stay.
$shimMarker = 'claude-multi-account shim'
if (Test-Path -LiteralPath $InstallDir) {
    Get-ChildItem -LiteralPath $InstallDir -File -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path -Leaf $_.FullName) -notlike 'claude-account.*' } |
        ForEach-Object {
            $head = Get-Content -LiteralPath $_.FullName -TotalCount 5 -ErrorAction SilentlyContinue
            if ($head -and (($head -join "`n") -match [regex]::Escape($shimMarker))) {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Ok "removed shortcut $($_.FullName)"
            }
        }
}

# --- the PATH entry -------------------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $kept = $userPath -split ';' | Where-Object {
        $_ -and ($_.TrimEnd('\') -ine $InstallDir.TrimEnd('\'))
    }
    $newPath = ($kept -join ';')
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Ok "removed $InstallDir from your user PATH"
    }
}

# --- what we deliberately keep -------------------------------------------

$profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$accountsHome = $env:CLAUDE_ACCOUNTS_HOME
if (-not $accountsHome) { $accountsHome = Join-Path $profileDir '.claude-accounts' }

Write-Host ''
Write-Host 'Kept, on purpose:' -ForegroundColor Cyan
if (Test-Path -LiteralPath $accountsHome) {
    $count = @(Get-ChildItem -LiteralPath $accountsHome -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "  $accountsHome  ($count account(s), still signed in)"
} else {
    Write-Host "  $accountsHome  (does not exist)"
}
Write-Host "  $(Join-Path $profileDir '.claude')  (your default Claude Code installation - never touched)"
Write-Host ''
Write-Host 'If you also want the stored account sessions gone, delete them yourself:'
Write-Host "  Remove-Item -Recurse -Force '$accountsHome'"
Write-Host ''
Write-Ok 'Done.'
