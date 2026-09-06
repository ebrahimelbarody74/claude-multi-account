<#
.SYNOPSIS
  claude-account - run and switch between multiple Claude Code accounts.

.DESCRIPTION
  Each account is an isolated CLAUDE_CONFIG_DIR under %USERPROFILE%\.claude-accounts.
  The user profile / HOME is never modified.

.LINK
  https://github.com/ebrahimelbarody74/claude-multi-account
#>

# There is deliberately NO param() block.
#
# Any declared parameter -- even one marked ValueFromRemainingArguments -- turns
# this into an advanced script, which adds PowerShell's common parameters. A
# Claude Code flag such as `-p` would then fail to bind with
# "the parameter name 'p' is ambiguous. Possible matches include:
# -ProgressAction -PipelineVariable" instead of being passed through.
#
# The automatic $args variable takes every argument verbatim, quoting intact.
$CliArgs = @($args)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '1.0.0'
$script:Prog    = 'claude-account'
$script:MaxNameLength = 64

# Account names that cannot be created, because they are commands or reserved.
$script:Reserved = @(
    'default','add','list','ls','use','run','remove','rm','delete',
    'rename','mv','status','path','env','shell','link','unlink','links',
    'help','version'
)

# Shim names that must never be created. 'claude' is the important one: a shim by
# that name would be found by this tool's own claude lookup and call itself.
$script:ReservedLinks = @('claude','claude-account','node','npm','npx','git','pwsh','powershell','cmd')

$script:ShimMarker = 'claude-multi-account shim'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

function Get-AccountsHome {
    if ($env:CLAUDE_ACCOUNTS_HOME) { return $env:CLAUDE_ACCOUNTS_HOME }
    $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return (Join-Path $profileDir '.claude-accounts')
}

function Get-ClaudeBin {
    if ($env:CLAUDE_BIN) { return $env:CLAUDE_BIN }
    return 'claude'
}

$script:AccountsHome = Get-AccountsHome
$script:ClaudeBin    = Get-ClaudeBin

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Write-Info { param([string]$Message) Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Host "warning: $Message" -ForegroundColor Yellow }

function Stop-WithError {
    param([string]$Message)
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Validation - this is the path-traversal guard
# ---------------------------------------------------------------------------

function Assert-ValidName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Stop-WithError "account name cannot be empty"
    }
    if ($Name.Length -gt $script:MaxNameLength) {
        Stop-WithError "account name is too long (max $($script:MaxNameLength) characters)"
    }
    if ($Name -eq '.' -or $Name -eq '..') {
        Stop-WithError "'$Name' is not a valid account name"
    }
    if ($Name.StartsWith('.')) {
        Stop-WithError "account name cannot start with '.'"
    }
    if ($Name.StartsWith('-')) {
        Stop-WithError "account name cannot start with '-'"
    }
    # Only letters, digits, dot, underscore, hyphen. Blocks \ / : .. and drive letters.
    if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
        Stop-WithError "invalid account name '$Name' (allowed: letters, digits, '.', '_', '-')"
    }
    # Windows reserved device names.
    if ($Name -match '^(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
        Stop-WithError "'$Name' is a reserved Windows device name"
    }
}

function Assert-NotReserved {
    param([string]$Name)
    if ($script:Reserved -contains $Name.ToLowerInvariant()) {
        Stop-WithError "'$Name' is a reserved name and cannot be used for an account"
    }
}

function Get-AccountDir {
    param([string]$Name)
    Assert-ValidName $Name
    $dir = Join-Path $script:AccountsHome $Name
    # Belt and braces: the resolved parent must be the accounts root.
    $parent = Split-Path -Parent $dir
    if ($parent.TrimEnd('\','/') -ne $script:AccountsHome.TrimEnd('\','/')) {
        Stop-WithError "refusing to operate on a path outside $($script:AccountsHome)"
    }
    return $dir
}

function Test-AccountExists {
    param([string]$Name)
    return (Test-Path -LiteralPath (Join-Path $script:AccountsHome $Name) -PathType Container)
}

function Assert-AccountExists {
    param([string]$Name)
    if (-not (Test-AccountExists $Name)) {
        Stop-WithError "no such account: '$Name' (run '$($script:Prog) list', or '$($script:Prog) add $Name')"
    }
}

function Assert-ClaudeInstalled {
    if (-not (Get-Command $script:ClaudeBin -ErrorAction SilentlyContinue)) {
        Stop-WithError "'$($script:ClaudeBin)' was not found on PATH. Install Claude Code first: https://claude.com/claude-code"
    }
}

function Initialize-AccountsHome {
    if (-not (Test-Path -LiteralPath $script:AccountsHome -PathType Container)) {
        New-Item -ItemType Directory -Path $script:AccountsHome -Force | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Reading `claude auth status --json`
# ---------------------------------------------------------------------------

function Get-AuthStatus {
    param([string]$Dir)   # empty / $null means the default account

    $previous = $env:CLAUDE_CONFIG_DIR
    $hadPrevious = Test-Path Env:\CLAUDE_CONFIG_DIR
    try {
        if ([string]::IsNullOrEmpty($Dir)) {
            if ($hadPrevious) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
        } else {
            $env:CLAUDE_CONFIG_DIR = $Dir
        }
        $raw = & $script:ClaudeBin auth status --json 2>$null
        if (-not $raw) { return $null }
        return ($raw | Out-String | ConvertFrom-Json)
    } catch {
        return $null
    } finally {
        if ($hadPrevious) { $env:CLAUDE_CONFIG_DIR = $previous }
        elseif (Test-Path Env:\CLAUDE_CONFIG_DIR) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
    }
}

function Get-Field {
    param($Object, [string]$Name, [string]$Fallback = '-')
    if ($null -eq $Object) { return $Fallback }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or [string]::IsNullOrEmpty([string]$prop.Value)) { return $Fallback }
    return [string]$prop.Value
}

# ---------------------------------------------------------------------------
# Running Claude Code under an account
# ---------------------------------------------------------------------------

function Invoke-ClaudeWithDir {
    param([string]$Dir, [string[]]$Passthrough)

    Assert-ClaudeInstalled

    $code        = 0
    $previous    = $env:CLAUDE_CONFIG_DIR
    $hadPrevious = Test-Path Env:\CLAUDE_CONFIG_DIR
    try {
        if ([string]::IsNullOrEmpty($Dir)) {
            # 'default': make sure an inherited value cannot leak in.
            if ($hadPrevious) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
        } else {
            $env:CLAUDE_CONFIG_DIR = $Dir
        }

        if ($null -eq $Passthrough -or $Passthrough.Count -eq 0) {
            & $script:ClaudeBin
        } else {
            # Splatting keeps every argument intact, including quoted strings.
            & $script:ClaudeBin @Passthrough
        }
        $code = $LASTEXITCODE
    } finally {
        if ($hadPrevious) { $env:CLAUDE_CONFIG_DIR = $previous }
        elseif (Test-Path Env:\CLAUDE_CONFIG_DIR) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
    }

    if ($null -eq $code) { $code = 0 }
    exit $code
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Add {
    param([string[]]$Rest)

    $name = $null
    $doLogin = $true
    foreach ($arg in $Rest) {
        if ($arg -eq '--no-login') { $doLogin = $false; continue }
        if ($arg.StartsWith('-'))  { Stop-WithError "unknown option for 'add': $arg" }
        if ($name) { Stop-WithError "'add' takes exactly one account name" }
        $name = $arg
    }

    if (-not $name) { Stop-WithError "usage: $($script:Prog) add <name>" }
    Assert-ValidName $name
    Assert-NotReserved $name
    Assert-ClaudeInstalled
    Initialize-AccountsHome

    $dir = Get-AccountDir $name
    if (Test-Path -LiteralPath $dir) {
        Stop-WithError "account '$name' already exists ($dir)"
    }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "created account '$name' at $dir" -ForegroundColor Green

    if (-not $doLogin) {
        Write-Info "Skipped sign-in. Run '$($script:Prog) $name' when you are ready to log in."
        return
    }

    Write-Info ""
    Write-Info "Signing in to '$name'. Use the email address for this account."
    Write-Info ""

    $code        = 0
    $previous    = $env:CLAUDE_CONFIG_DIR
    $hadPrevious = Test-Path Env:\CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = $dir
        & $script:ClaudeBin auth login
        $code = $LASTEXITCODE
    } finally {
        if ($hadPrevious) { $env:CLAUDE_CONFIG_DIR = $previous }
        elseif (Test-Path Env:\CLAUDE_CONFIG_DIR) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
    }

    if ($code -ne 0) {
        Write-Warn "sign-in did not complete (exit $code). The account directory was kept."
        Write-Warn "Retry with: $($script:Prog) $name    (or remove it with: $($script:Prog) remove $name)"
        exit $code
    }

    Write-Info ""
    Invoke-Status $name
}

function Write-AccountRow {
    param([string]$Name, [string]$Dir, $Status)

    $email = Get-Field $Status 'email'
    $plan  = Get-Field $Status 'subscriptionType'

    $loggedIn = $false
    if ($null -ne $Status -and $Status.PSObject.Properties['loggedIn']) {
        $loggedIn = [bool]$Status.loggedIn
    }

    $marker = ''
    $current = $env:CLAUDE_CONFIG_DIR
    if ($current -and $Dir -and ($current.TrimEnd('\','/') -eq $Dir.TrimEnd('\','/'))) { $marker = ' *' }
    elseif (-not $current -and -not $Dir) { $marker = ' *' }

    $line = '{0,-18} {1,-34} {2,-10} ' -f $Name, $email, $plan
    Write-Host $line -NoNewline
    if ($loggedIn) {
        Write-Host 'logged in' -ForegroundColor Green -NoNewline
    } else {
        Write-Host 'logged out' -ForegroundColor DarkGray -NoNewline
    }
    Write-Host $marker -ForegroundColor Cyan
}

function Invoke-List {
    Assert-ClaudeInstalled

    Write-Host ('{0,-18} {1,-34} {2,-10} {3}' -f 'ACCOUNT','EMAIL','PLAN','STATUS')

    Write-AccountRow 'default' '' (Get-AuthStatus '')

    if (-not (Test-Path -LiteralPath $script:AccountsHome -PathType Container)) {
        Write-Host "(no named accounts yet - create one with: $($script:Prog) add work)" -ForegroundColor DarkGray
        return
    }

    $dirs = @(Get-ChildItem -LiteralPath $script:AccountsHome -Directory -ErrorAction SilentlyContinue |
              Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)

    if ($dirs.Count -eq 0) {
        Write-Host "(no named accounts yet - create one with: $($script:Prog) add work)" -ForegroundColor DarkGray
        return
    }

    foreach ($d in $dirs) {
        Write-AccountRow $d.Name $d.FullName (Get-AuthStatus $d.FullName)
    }

    $links = @(Get-Links)
    if ($links.Count -gt 0) {
        Write-Host ''
        Write-Host 'Shortcuts'
        foreach ($l in $links) { Write-Host ('  {0,-16} -> {1}' -f $l.Name, $l.Account) }
    }
}

function Invoke-Status {
    param([string]$Name)

    Assert-ClaudeInstalled

    $dir = ''
    $label = 'default'
    if ($Name -and $Name -ne 'default') {
        Assert-AccountExists $Name
        $dir = Get-AccountDir $Name
        $label = $Name
    }

    $status = Get-AuthStatus $dir

    Write-Host ('Account   {0}' -f $label)
    if ($dir) {
        Write-Host ('Directory {0}' -f $dir)
    } else {
        Write-Host 'Directory (Claude Code default - CLAUDE_CONFIG_DIR is not set)'
    }

    $loggedIn = $false
    if ($null -ne $status -and $status.PSObject.Properties['loggedIn']) {
        $loggedIn = [bool]$status.loggedIn
    }

    if ($loggedIn) {
        Write-Host 'Status    ' -NoNewline; Write-Host 'logged in' -ForegroundColor Green
        Write-Host ('Email     {0}' -f (Get-Field $status 'email'))
        Write-Host ('Plan      {0}' -f (Get-Field $status 'subscriptionType'))
        Write-Host ('Org       {0}' -f (Get-Field $status 'orgName'))
        Write-Host ('Method    {0}' -f (Get-Field $status 'authMethod'))
        return
    }

    Write-Host 'Status    ' -NoNewline; Write-Host 'logged out' -ForegroundColor Yellow
    if ($dir) {
        Write-Info ""
        Write-Info "Sign in with: $($script:Prog) $label"
    }
    exit 1
}

function Assert-Removable {
    param([string]$Dir)

    $parent = (Split-Path -Parent $Dir).TrimEnd('\','/')
    $root   = $script:AccountsHome.TrimEnd('\','/')
    $leaf   = Split-Path -Leaf $Dir

    if ($parent -ne $root)  { Stop-WithError "refusing to delete '$Dir': not inside $($script:AccountsHome)" }
    if (-not $leaf)         { Stop-WithError "refusing to delete an empty path" }
    if ($leaf -eq '.' -or $leaf -eq '..') { Stop-WithError "refusing to delete '$Dir'" }

    $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($Dir.TrimEnd('\','/') -eq $profileDir.TrimEnd('\','/')) { Stop-WithError "refusing to delete the user profile" }
    if ($Dir.TrimEnd('\','/') -eq (Join-Path $profileDir '.claude').TrimEnd('\','/')) { Stop-WithError "refusing to delete ~/.claude" }
    if ($Dir.TrimEnd('\','/') -eq $root) { Stop-WithError "refusing to delete the accounts root" }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Stop-WithError "'$Dir' is not a directory" }
}

function Invoke-Remove {
    param([string[]]$Rest)

    $name = $null
    $assumeYes = $false
    foreach ($arg in $Rest) {
        if ($arg -eq '-y' -or $arg -eq '--yes' -or $arg -eq '-Force') { $assumeYes = $true; continue }
        if ($arg.StartsWith('-')) { Stop-WithError "unknown option for 'remove': $arg" }
        if ($name) { Stop-WithError "'remove' takes exactly one account name" }
        $name = $arg
    }

    if (-not $name) { Stop-WithError "usage: $($script:Prog) remove <name>" }
    Assert-ValidName $name
    if ($name -eq 'default') {
        Stop-WithError "'default' is the built-in Claude Code account and cannot be removed"
    }

    Assert-AccountExists $name
    $dir = Get-AccountDir $name
    Assert-Removable $dir

    if (-not $assumeYes) {
        $reply = Read-Host "Remove account $name and its stored session at $dir? [y/N]"
        if ($reply -notmatch '^(?i)y(es)?$') {
            Write-Info 'aborted'
            exit 1
        }
    }

    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "removed account '$name'" -ForegroundColor Green
    Write-Info 'Your default Claude Code installation was not touched.'
}

function Invoke-Rename {
    param([string]$OldName, [string]$NewName)

    if (-not $OldName -or -not $NewName) {
        Stop-WithError "usage: $($script:Prog) rename <old> <new>"
    }

    Assert-ValidName $OldName
    Assert-ValidName $NewName
    Assert-NotReserved $NewName

    if ($OldName -eq 'default') {
        Stop-WithError "'default' is the built-in Claude Code account and cannot be renamed"
    }
    if ($OldName -eq $NewName) {
        Stop-WithError "the new name is the same as the old one"
    }

    Assert-AccountExists $OldName
    if (Test-AccountExists $NewName) { Stop-WithError "account '$NewName' already exists" }

    $from = Get-AccountDir $OldName
    $to   = Get-AccountDir $NewName

    Move-Item -LiteralPath $from -Destination $to
    Write-Host "renamed '$OldName' -> '$NewName'" -ForegroundColor Green
}

function Invoke-Path {
    param([string]$Name)
    if (-not $Name) { Stop-WithError "usage: $($script:Prog) path <name>" }
    if ($Name -eq 'default') {
        if ($env:CLAUDE_CONFIG_DIR) { Write-Output $env:CLAUDE_CONFIG_DIR }
        else {
            $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
            Write-Output (Join-Path $profileDir '.claude')
        }
        return
    }
    Assert-AccountExists $Name
    Write-Output (Get-AccountDir $Name)
}

# Prints the assignment line. It is printed, never invoked by this tool.
function Invoke-Env {
    param([string]$Name)
    if (-not $Name) { Stop-WithError "usage: $($script:Prog) env <name>" }
    if ($Name -eq 'default') {
        Write-Output 'Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue'
        return
    }
    Assert-AccountExists $Name
    $dir = Get-AccountDir $Name
    Write-Output ('$env:CLAUDE_CONFIG_DIR = ''{0}''' -f $dir)
}

# Opens a child PowerShell already pointed at the account.
function Invoke-Shell {
    param([string]$Name)
    if (-not $Name) { Stop-WithError "usage: $($script:Prog) shell <name>" }

    $host_exe = (Get-Process -Id $PID).Path
    if (-not $host_exe) { $host_exe = 'powershell.exe' }

    if ($Name -eq 'default') {
        Write-Info "Opening a shell using the default Claude Code account. Type 'exit' to leave."
        if (Test-Path Env:\CLAUDE_CONFIG_DIR) { Remove-Item Env:\CLAUDE_CONFIG_DIR }
        $env:CLAUDE_ACCOUNT = 'default'
    } else {
        Assert-AccountExists $Name
        Write-Info "Opening a shell using account '$Name'. Type 'exit' to leave."
        $env:CLAUDE_CONFIG_DIR = Get-AccountDir $Name
        $env:CLAUDE_ACCOUNT = $Name
    }

    & $host_exe -NoLogo -NoExit
    exit $LASTEXITCODE
}

# --- shortcuts (link / unlink / links) ------------------------------------

function Get-SelfDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

# True only for a generated shim. The marker must be near the top, which keeps
# this tool's own source -- where the marker appears inside the generator --
# from being mistaken for a shim.
function Test-Shim {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Split-Path -Leaf $Path) -like 'claude-account.*') { return $false }
    $head = Get-Content -LiteralPath $Path -TotalCount 5 -ErrorAction SilentlyContinue
    if (-not $head) { return $false }
    return (($head -join "`n") -match [regex]::Escape($script:ShimMarker))
}

function Get-ShimAccount {
    param([string]$Path)
    $head = Get-Content -LiteralPath $Path -TotalCount 5 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        if ($line -match '^\s*(?:rem|#)\s*account:\s*(.+?)\s*$') { return $Matches[1] }
    }
    return '?'
}

function Get-Links {
    $dir = Get-SelfDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
             Where-Object { Test-Shim $_.FullName } |
             ForEach-Object { [pscustomobject]@{ Name = $_.BaseName; Account = (Get-ShimAccount $_.FullName) } })
}

function Invoke-Link {
    param([string[]]$Rest)

    $account = $null; $linkName = $null; $force = $false
    foreach ($arg in $Rest) {
        if ($arg -eq '-f' -or $arg -eq '--force') { $force = $true; continue }
        if ($arg.StartsWith('-')) { Stop-WithError "unknown option for 'link': $arg" }
        if (-not $account)      { $account = $arg; continue }
        if (-not $linkName)     { $linkName = $arg; continue }
        Stop-WithError "'link' takes an account and a shortcut name"
    }

    if (-not $account -or -not $linkName) {
        Stop-WithError "usage: $($script:Prog) link <account> <shortcut>   (example: $($script:Prog) link work claude1)"
    }

    Assert-ValidName $account
    Assert-ValidName $linkName
    if ($account -ne 'default') { Assert-AccountExists $account }

    if ($script:ReservedLinks -contains $linkName.ToLowerInvariant()) {
        Stop-WithError "'$linkName' is not allowed as a shortcut - it would shadow the real '$linkName' command"
    }

    $dir    = Get-SelfDir
    $target = Join-Path $dir "$linkName.cmd"

    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Shim $target)) {
            Stop-WithError "'$target' already exists and was not created by $($script:Prog) - refusing to overwrite it"
        }
        if (-not $force) {
            Stop-WithError "shortcut '$linkName' already points at '$(Get-ShimAccount $target)' (re-run with --force to repoint it)"
        }
    }

    $existing = Get-Command $linkName -ErrorAction SilentlyContinue
    if ($existing -and $existing.Source -and ($existing.Source -ne $target) -and -not (Test-Shim $existing.Source)) {
        Stop-WithError "'$linkName' is already a command on your PATH ($($existing.Source)) - pick another name"
    }

    $shim = @"
@echo off
rem $($script:ShimMarker)
rem account: $account
rem Created by: $($script:Prog) link $account $linkName
setlocal
set "PSEXE=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PSEXE=pwsh.exe"
"%PSEXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-account.ps1" use $account %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $target -Value $shim -Encoding ASCII
    Write-Host "created shortcut '$linkName' -> account '$account'" -ForegroundColor Green
    Write-Info "Run it with: $linkName   (arguments pass through, e.g. $linkName -p ""hi"")"
}

function Invoke-Unlink {
    param([string]$LinkName)
    if (-not $LinkName) { Stop-WithError "usage: $($script:Prog) unlink <shortcut>" }
    Assert-ValidName $LinkName

    $target = Join-Path (Get-SelfDir) "$LinkName.cmd"
    if (-not (Test-Path -LiteralPath $target)) { Stop-WithError "no such shortcut: '$LinkName'" }
    if (-not (Test-Shim $target)) {
        Stop-WithError "'$target' was not created by $($script:Prog) - refusing to delete it"
    }
    Remove-Item -LiteralPath $target -Force
    Write-Host "removed shortcut '$LinkName'" -ForegroundColor Green
}

function Invoke-Links {
    # @() at the call site: Windows PowerShell 5.1 unwraps a one-element array
    # returned from a function, and StrictMode then rejects .Count on the scalar.
    $links = @(Get-Links)
    if ($links.Count -eq 0) {
        Write-Info "No shortcuts yet. Create one with: $($script:Prog) link work claude1"
        return
    }
    Write-Host ('{0,-18} {1}' -f 'SHORTCUT','ACCOUNT')
    foreach ($l in $links) { Write-Host ('{0,-18} {1}' -f $l.Name, $l.Account) }
}

function Invoke-Help {
    @"
claude-account $($script:Version) - run several Claude Code accounts side by side.

USAGE
  $($script:Prog) <command> [args]
  $($script:Prog) <account> [claude args...]

COMMANDS
  add <name> [--no-login]   Create an account and sign in to it
  list                      Show every account with its email, plan and status
  use <name> [args...]      Run Claude Code as <name>
  <name> [args...]          Shorthand for 'use <name>'
  default [args...]         Run plain Claude Code (CLAUDE_CONFIG_DIR unset)
  status [name]             Show sign-in details for one account
  remove <name> [--yes]     Delete a stored account session
  rename <old> <new>        Rename an account
  link <account> <name>     Create a short command, e.g. 'link work claude1'
  unlink <name>             Remove a shortcut
  links                     List the shortcuts
  path <name>               Print the account's config directory
  env <name>                Print the assignment line for that account
  shell <name>              Open a child shell pointed at that account
  help, version

EXAMPLES
  $($script:Prog) add work
  $($script:Prog) add personal
  $($script:Prog) list
  $($script:Prog) work                        # interactive session on the work account
  $($script:Prog) work -p "summarise README"  # arguments pass straight through
  $($script:Prog) use personal --model opus
  $($script:Prog) default                     # your normal, untouched Claude Code
  $($script:Prog) status work

  $($script:Prog) link work claude1            # now 'claude1' runs the work account
  $($script:Prog) link personal claude2        # and 'claude2' runs the personal one
  claude1 -p "hi"                              # arguments still pass through

  If PowerShell tries to interpret a Claude flag as its own, stop parsing:
  $($script:Prog) work --% -p "summarise README"

HOW IT WORKS
  Every account is its own CLAUDE_CONFIG_DIR under
    $($script:AccountsHome)\<name>
  and Claude Code runs with `$env:CLAUDE_CONFIG_DIR set to that directory for the
  child process only. The user profile is never changed.

  The reserved account 'default' runs Claude Code with CLAUDE_CONFIG_DIR unset,
  which is your existing installation.

ENVIRONMENT
  CLAUDE_ACCOUNTS_HOME   Where accounts live (default: %USERPROFILE%\.claude-accounts)
  CLAUDE_BIN             Claude Code executable (default: claude)
"@ | Write-Output
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if ($null -eq $CliArgs -or $CliArgs.Count -eq 0) {
    Invoke-Help
    exit 0
}

$command = $CliArgs[0]
$rest    = @()
if ($CliArgs.Count -gt 1) { $rest = @($CliArgs[1..($CliArgs.Count - 1)]) }

# Windows PowerShell 5.1 has no `if` expression, so precompute the positionals.
$arg1 = ''
$arg2 = ''
if ($rest.Count -gt 0) { $arg1 = $rest[0] }
if ($rest.Count -gt 1) { $arg2 = $rest[1] }

switch -Regex ($command) {
    '^add$'                     { Invoke-Add $rest; break }
    '^(list|ls)$'               { Invoke-List; break }
    '^status$'                  { Invoke-Status $arg1; break }
    '^(remove|rm|delete)$'      { Invoke-Remove $rest; break }
    '^(rename|mv)$'             { Invoke-Rename $arg1 $arg2; break }
    '^link$'                    { Invoke-Link $rest; break }
    '^unlink$'                  { Invoke-Unlink $arg1; break }
    '^links$'                   { Invoke-Links; break }
    '^path$'                    { Invoke-Path $arg1; break }
    '^env$'                     { Invoke-Env $arg1; break }
    '^shell$'                   { Invoke-Shell $arg1; break }
    '^default$'                 { Invoke-ClaudeWithDir '' $rest; break }
    '^(use|run)$' {
        if ($rest.Count -eq 0) { Stop-WithError "usage: $($script:Prog) use <name> [claude args...]" }
        $name = $rest[0]
        $passthrough = @()
        if ($rest.Count -gt 1) { $passthrough = @($rest[1..($rest.Count - 1)]) }
        if ($name -eq 'default') {
            Invoke-ClaudeWithDir '' $passthrough
        } else {
            Assert-AccountExists $name
            Invoke-ClaudeWithDir (Get-AccountDir $name) $passthrough
        }
        break
    }
    '^(help|--help|-h|/\?)$'    { Invoke-Help; break }
    '^(version|--version|-V)$'  { Write-Output "$($script:Prog) $($script:Version)"; break }
    default {
        if ($command.StartsWith('-')) {
            Stop-WithError "unknown option: $command (try '$($script:Prog) help')"
        }
        # Bare account name: claude-account work [args...]
        Assert-ValidName $command
        if (Test-AccountExists $command) {
            Invoke-ClaudeWithDir (Get-AccountDir $command) $rest
        } else {
            Stop-WithError "unknown command or account: '$command' (try '$($script:Prog) list' or '$($script:Prog) help')"
        }
    }
}
