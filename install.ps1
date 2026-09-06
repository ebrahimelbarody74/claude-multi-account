<#
.SYNOPSIS
  Installer for claude-account on Windows.

.DESCRIPTION
  Installs claude-account.ps1 plus a .cmd shim into
  %LOCALAPPDATA%\Programs\claude-multi-account and adds that folder to the
  user PATH. Nothing is written outside the user profile, and no administrator
  rights are needed.

.EXAMPLE
  irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.ps1 | iex

.EXAMPLE
  .\install.ps1 -InstallDir "D:\tools\claude-account" -NoModifyPath
#>

[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$Repo = 'ebrahimelbarody74/claude-multi-account',
    [string]$Ref  = 'main',
    [switch]$NoModifyPath
)

$ErrorActionPreference = 'Stop'

$BinName = 'claude-account'

function Write-Step { param([string]$m) Write-Host $m }
function Write-Ok   { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "warning: $m" -ForegroundColor Yellow }
function Fail       { param([string]$m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

Write-Host 'Installing claude-account' -ForegroundColor Cyan
Write-Host ''

# --- sanity ---------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Fail 'Windows PowerShell 5.1 or newer is required.'
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warn2 "Claude Code ('claude') is not on your PATH yet."
    Write-Warn2 'claude-account will install fine, but install Claude Code before using it:'
    Write-Warn2 '  https://claude.com/claude-code'
    Write-Host ''
}

# --- destination ----------------------------------------------------------

if (-not $InstallDir) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $InstallDir = Join-Path $base 'Programs\claude-multi-account'
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Write-Step "Install directory: $InstallDir"

# --- locate the source ----------------------------------------------------

$scriptSource = $null
$localCopy = $null
if ($PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot "powershell\$BinName.ps1"
    if (Test-Path -LiteralPath $candidate) { $localCopy = $candidate }
}

if ($localCopy) {
    Write-Step "Using local copy: $localCopy"
    $scriptSource = Get-Content -LiteralPath $localCopy -Raw
} else {
    $rawUrl = "https://raw.githubusercontent.com/$Repo/$Ref/powershell/$BinName.ps1"
    Write-Step "Downloading from $rawUrl"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
    try {
        $scriptSource = Invoke-RestMethod -Uri $rawUrl -UseBasicParsing
    } catch {
        Fail "download failed: $($_.Exception.Message)"
    }
}

if (-not $scriptSource -or $scriptSource -notmatch 'CLAUDE_CONFIG_DIR') {
    Fail 'the downloaded file does not look like claude-account.'
}

# --- write the script and the shim ---------------------------------------

$targetPs1 = Join-Path $InstallDir "$BinName.ps1"
Set-Content -LiteralPath $targetPs1 -Value $scriptSource -Encoding UTF8
Write-Ok "Installed $targetPs1"

# A .cmd shim so `claude-account` also works from cmd.exe and from anywhere
# that does not run .ps1 files directly.
$shim = @"
@echo off
rem claude-multi-account shim - sets CLAUDE_CONFIG_DIR via claude-account.ps1
setlocal
set "PSEXE=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PSEXE=pwsh.exe"
"%PSEXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0$BinName.ps1" %*
exit /b %ERRORLEVEL%
"@
$targetCmd = Join-Path $InstallDir "$BinName.cmd"
Set-Content -LiteralPath $targetCmd -Value $shim -Encoding ASCII
Write-Ok "Installed $targetCmd"

# --- PATH -----------------------------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }

$alreadyOnPath = ($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) }).Count -gt 0

if ($alreadyOnPath) {
    Write-Step "$InstallDir is already on your PATH"
} elseif ($NoModifyPath) {
    Write-Warn2 "$InstallDir is not on your PATH. Add it yourself, or re-run without -NoModifyPath."
} else {
    $newPath = if ($userPath.TrimEnd(';')) { "$($userPath.TrimEnd(';'));$InstallDir" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    # Make it work in this session too.
    $env:Path = "$env:Path;$InstallDir"
    Write-Ok "Added $InstallDir to your user PATH"
    Write-Step 'Open a new terminal for this to apply everywhere.'
}

# --- verify ---------------------------------------------------------------

# Verify the installed script itself with the current host, which works on any
# platform. The .cmd shim is only exercised where cmd.exe exists.
$reported = $null
try {
    $hostExe = (Get-Process -Id $PID).Path
    if (-not $hostExe) { $hostExe = 'powershell.exe' }
    $reported = & $hostExe -NoLogo -NoProfile -File $targetPs1 version 2>&1 | Select-Object -First 1
} catch {
    $reported = $null
}

$isWin = $true
if (Test-Path Variable:\IsWindows) { $isWin = $IsWindows }
if ($isWin) {
    try { & $targetCmd version *> $null } catch {
        Write-Warn2 'The .cmd shim did not run. You can still use claude-account.ps1 directly.'
    }
}

if (-not $reported) {
    Write-Warn2 'Could not verify the install. Open a new terminal and run: claude-account version'
} else {
    Write-Host ''
    Write-Ok "Done. $reported"
}

Write-Host ''
Write-Host 'Next steps' -ForegroundColor Cyan
Write-Host '  claude-account add work        # create an account and sign in'
Write-Host '  claude-account add personal'
Write-Host '  claude-account list'
Write-Host '  claude-account work            # run Claude Code as "work"'
Write-Host '  claude-account default         # your normal Claude Code, untouched'
Write-Host ''
Write-Host 'Accounts are stored in %USERPROFILE%\.claude-accounts and are never removed by the uninstaller.'
