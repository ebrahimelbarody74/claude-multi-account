<#
.SYNOPSIS
  Test suite for claude-account.ps1.

.DESCRIPTION
  Runs against a throwaway CLAUDE_ACCOUNTS_HOME and a fake `claude` executable,
  so it never touches your real accounts or the network.

    pwsh -File tests/run-tests.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Cli      = Join-Path $RepoRoot 'powershell\claude-account.ps1'
if (-not (Test-Path -LiteralPath $Cli)) {
    $Cli = Join-Path $RepoRoot 'powershell/claude-account.ps1'
}

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("cma-tests-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$FakeBin = Join-Path $Work 'fakebin'
New-Item -ItemType Directory -Path $FakeBin -Force | Out-Null

$env:CLAUDE_ACCOUNTS_HOME = Join-Path $Work 'accounts'

# --- a fake `claude` ------------------------------------------------------
# On Windows this is a .cmd wrapper around a .ps1; elsewhere a shell script.
$isWindows_ = $false
if (Test-Path Variable:\IsWindows) { $isWindows_ = $IsWindows } else { $isWindows_ = $true }

$fakeBody = @'
#!/usr/bin/env bash
if [ "${1-}" = "auth" ] && [ "${2-}" = "status" ]; then
  dir="${CLAUDE_CONFIG_DIR-}"
  if [ -z "$dir" ]; then
    printf '{\n  "loggedIn": true,\n  "authMethod": "claude.ai",\n  "email": "default@example.com",\n  "orgName": "Default Org",\n  "subscriptionType": "max"\n}\n'
    exit 0
  fi
  if [ -f "$dir/.logged-in" ]; then
    printf '{\n  "loggedIn": true,\n  "authMethod": "claude.ai",\n  "email": "%s",\n  "orgName": "Test Org",\n  "subscriptionType": "pro"\n}\n' "$(cat "$dir/.logged-in")"
    exit 0
  fi
  printf '{\n  "loggedIn": false,\n  "authMethod": "none"\n}\n'
  exit 1
fi
if [ "${1-}" = "auth" ] && [ "${2-}" = "login" ]; then
  [ -n "${CLAUDE_CONFIG_DIR-}" ] || exit 2
  printf '%s\n' "${FAKE_LOGIN_EMAIL:-someone@example.com}" > "$CLAUDE_CONFIG_DIR/.logged-in"
  exit 0
fi
printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR-<unset>}" > "${FAKE_ENV_FILE:-/dev/null}"
printf '%s\n' "$@" > "${FAKE_ARGS_FILE:-/dev/null}"
exit 0
'@

$fakeCmdBody = @'
@echo off
setlocal EnableDelayedExpansion
if "%~1"=="auth" if "%~2"=="status" (
  if "%CLAUDE_CONFIG_DIR%"=="" (
    echo {
    echo   "loggedIn": true,
    echo   "email": "default@example.com",
    echo   "subscriptionType": "max"
    echo }
    exit /b 0
  )
  if exist "%CLAUDE_CONFIG_DIR%\.logged-in" (
    set /p EMAIL=<"%CLAUDE_CONFIG_DIR%\.logged-in"
    echo {
    echo   "loggedIn": true,
    echo   "email": "!EMAIL!",
    echo   "subscriptionType": "pro"
    echo }
    exit /b 0
  )
  echo {
  echo   "loggedIn": false
  echo }
  exit /b 1
)
if "%~1"=="auth" if "%~2"=="login" (
  if "%CLAUDE_CONFIG_DIR%"=="" exit /b 2
  if "%FAKE_LOGIN_EMAIL%"=="" set "FAKE_LOGIN_EMAIL=someone@example.com"
  echo %FAKE_LOGIN_EMAIL%>"%CLAUDE_CONFIG_DIR%\.logged-in"
  exit /b 0
)
if not "%FAKE_ENV_FILE%"=="" echo CLAUDE_CONFIG_DIR=%CLAUDE_CONFIG_DIR%>"%FAKE_ENV_FILE%"
if not "%FAKE_ARGS_FILE%"=="" echo %*>"%FAKE_ARGS_FILE%"
exit /b 0
'@

if ($isWindows_) {
    Set-Content -LiteralPath (Join-Path $FakeBin 'claude.cmd') -Value $fakeCmdBody -Encoding ASCII
} else {
    $fakePath = Join-Path $FakeBin 'claude'
    Set-Content -LiteralPath $fakePath -Value $fakeBody -Encoding UTF8
    & chmod +x $fakePath
}

$sep = [IO.Path]::PathSeparator
$env:PATH = "$FakeBin$sep$($env:PATH)"

# --- harness --------------------------------------------------------------

$script:Pass = 0
$script:Fail = 0

function Ok   { param($n) $script:Pass++; Write-Host "  ok   $n" }
function Bad  { param($n, $d) $script:Fail++; Write-Host "  FAIL $n" -ForegroundColor Red; if ($d) { Write-Host "       $d" -ForegroundColor DarkGray } }
function Group{ param($n) Write-Host ''; Write-Host $n -ForegroundColor Cyan }

# Runs the CLI in a child pwsh so its `exit` cannot kill this process.
function RunCli {
    param([string[]]$CliArguments)
    $exe = (Get-Process -Id $PID).Path
    $all = @('-NoLogo','-NoProfile','-File', $Cli) + $CliArguments
    $out = & $exe @all 2>&1 | Out-String
    return @{ Output = $out; Code = $LASTEXITCODE }
}

function AssertOk       { param($n, [string[]]$a) $r = RunCli $a; if ($r.Code -eq 0) { Ok $n } else { Bad $n "exit $($r.Code): $($r.Output)" } }
function AssertFail     { param($n, [string[]]$a) $r = RunCli $a; if ($r.Code -ne 0) { Ok $n } else { Bad $n "expected failure: $($r.Output)" } }
function AssertContains { param($n, $needle, [string[]]$a) $r = RunCli $a; if ($r.Output -like "*$needle*") { Ok $n } else { Bad $n "expected '$needle' in: $($r.Output)" } }

Write-Host 'claude-account PowerShell test suite'
Write-Host "sandbox: $Work"

# ---------------------------------------------------------------------------
Group 'basics'
AssertContains 'version prints a version' 'claude-account 1' @('version')
AssertContains 'help lists the commands'  'rename <old> <new>' @('help')
AssertContains 'no args prints help'      'USAGE' @()
AssertFail     'unknown command fails'    @('definitely-not-a-command')
AssertFail     'unknown option fails'     @('--nope')

# ---------------------------------------------------------------------------
Group 'add'
$env:FAKE_LOGIN_EMAIL = 'work@example.com'
AssertOk       'add work' @('add','work')
if (Test-Path -LiteralPath (Join-Path $env:CLAUDE_ACCOUNTS_HOME 'work')) { Ok 'account dir exists' } else { Bad 'account dir exists' }
AssertContains 'add rejects a duplicate' 'already exists' @('add','work')
AssertOk       'add --no-login skips sign-in' @('add','nologin','--no-login')
AssertFail     'add with no name fails' @('add')
AssertFail     'add rejects two names'  @('add','a','b')
AssertFail     'add rejects an unknown option' @('add','x','--bogus')

# ---------------------------------------------------------------------------
Group 'path traversal and hostile names'
$evilNames = @('../evil','../../etc/passwd','/etc/passwd','a/b','.hidden','-rf','..','.','a b','a;b','a`b','a|b','a&b','a>b','a*','a?','a\b','~root','C:\Windows','CON','NUL','LPT1')
foreach ($evil in $evilNames) {
    AssertFail "rejects add '$evil'"    @('add', $evil)
    AssertFail "rejects remove '$evil'" @('remove','--yes', $evil)
    AssertFail "rejects rename '$evil'" @('rename', $evil, 'safe')
    AssertFail "rejects path '$evil'"   @('path', $evil)
}
AssertFail 'rejects an over-long name' @('add', ('a' * 200))

# Names containing quotes cannot be asserted on the child's exit code: Windows
# argument marshalling (CommandLineToArgvW) strips an embedded quote before the
# script is ever started, so `a"b` arrives as the perfectly legal name `ab`.
# The property that actually matters is that no illegally-named account
# directory can come into existence, so assert that directly.
foreach ($q in @('a"b', "a'b", 'a`"b')) { RunCli @('add', $q) | Out-Null }
$illegal = @(Get-ChildItem -LiteralPath $env:CLAUDE_ACCOUNTS_HOME -Directory |
             Where-Object { $_.Name -notmatch '^[A-Za-z0-9._-]+$' })
if ($illegal.Count -eq 0) {
    Ok 'no illegally-named account directory can be created'
} else {
    Bad 'no illegally-named account directory can be created' ($illegal.Name -join ', ')
}
# Drop anything the marshalling legitimised, so the expected set is restored.
Get-ChildItem -LiteralPath $env:CLAUDE_ACCOUNTS_HOME -Directory |
    Where-Object { $_.Name -notin @('work','nologin') } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

$dirCount = @(Get-ChildItem -LiteralPath $env:CLAUDE_ACCOUNTS_HOME -Directory).Count
if ($dirCount -eq 2) { Ok 'only the two real accounts exist' } else { Bad 'only the two real accounts exist' "found $dirCount" }
if (-not (Test-Path -LiteralPath (Join-Path $Work 'evil'))) { Ok 'nothing escaped the accounts root' } else { Bad 'nothing escaped the accounts root' }

# ---------------------------------------------------------------------------
Group 'reserved names'
foreach ($r in @('default','list','add','use','remove','rename','status','help','version','path','env','shell')) {
    AssertFail "rejects add '$r'" @('add', $r)
}
AssertFail 'cannot remove default' @('remove','--yes','default')
AssertFail 'cannot rename default' @('rename','default','other')

# ---------------------------------------------------------------------------
Group 'list and status'
AssertContains 'list shows default'          'default'            @('list')
AssertContains 'list shows work'             'work'               @('list')
AssertContains 'list shows the email'        'work@example.com'   @('list')
AssertContains 'list shows the plan'         'pro'                @('list')
AssertContains 'list marks logged out'       'logged out'         @('list')
AssertContains 'status work: email'          'work@example.com'   @('status','work')
AssertContains 'status work: directory'      'work'               @('status','work')
AssertContains 'status default is default'   'default@example.com' @('status','default')
AssertContains 'status with no arg = default' 'default@example.com' @('status')
AssertFail     'status of a logged-out account exits nonzero' @('status','nologin')
AssertFail     'status of a missing account fails' @('status','ghost')

# ---------------------------------------------------------------------------
Group 'running claude with the right env'
$env:FAKE_ENV_FILE  = Join-Path $Work 'env.txt'
$env:FAKE_ARGS_FILE = Join-Path $Work 'args.txt'

RunCli @('work') | Out-Null
$envTxt = Get-Content -LiteralPath $env:FAKE_ENV_FILE -Raw
$expect = Join-Path $env:CLAUDE_ACCOUNTS_HOME 'work'
if ($envTxt -like "*$expect*") { Ok 'bare name sets CLAUDE_CONFIG_DIR' } else { Bad 'bare name sets CLAUDE_CONFIG_DIR' $envTxt }

RunCli @('use','work') | Out-Null
$envTxt = Get-Content -LiteralPath $env:FAKE_ENV_FILE -Raw
if ($envTxt -like "*$expect*") { Ok 'use sets CLAUDE_CONFIG_DIR' } else { Bad 'use sets CLAUDE_CONFIG_DIR' $envTxt }

RunCli @('work','-p','hello world','--model','opus') | Out-Null
$argsTxt = (Get-Content -LiteralPath $env:FAKE_ARGS_FILE -Raw)
if (($argsTxt -like '*-p*') -and ($argsTxt -like '*hello world*') -and ($argsTxt -like '*--model*') -and ($argsTxt -like '*opus*')) {
    Ok 'arguments (including a quoted one) pass through'
} else { Bad 'arguments pass through' $argsTxt }

RunCli @('default') | Out-Null
$envTxt = Get-Content -LiteralPath $env:FAKE_ENV_FILE -Raw
if ($envTxt -match 'CLAUDE_CONFIG_DIR=(<unset>)?\s*$') { Ok 'default leaves CLAUDE_CONFIG_DIR unset' } else { Bad 'default leaves CLAUDE_CONFIG_DIR unset' $envTxt }

$env:CLAUDE_CONFIG_DIR = Join-Path $Work 'leaked'
RunCli @('default') | Out-Null
Remove-Item Env:\CLAUDE_CONFIG_DIR
$envTxt = Get-Content -LiteralPath $env:FAKE_ENV_FILE -Raw
if ($envTxt -notlike '*leaked*') { Ok 'default strips an inherited CLAUDE_CONFIG_DIR' } else { Bad 'default strips an inherited CLAUDE_CONFIG_DIR' $envTxt }

AssertFail 'running a missing account fails' @('ghost')
AssertFail 'use with no name fails' @('use')

# ---------------------------------------------------------------------------
Group 'path, env, shell'
AssertContains 'path prints the account dir' 'work' @('path','work')
AssertContains 'env prints an assignment'    'CLAUDE_CONFIG_DIR' @('env','work')
AssertContains 'env default removes the var' 'Remove-Item' @('env','default')
AssertFail     'env of a missing account fails' @('env','ghost')

# ---------------------------------------------------------------------------
Group 'link / unlink (shortcuts)'
# Shims live next to the executable, so exercise a copy in its own directory.
$ShimDir = Join-Path $Work 'shimbin'
New-Item -ItemType Directory -Path $ShimDir -Force | Out-Null
Copy-Item -LiteralPath $Cli -Destination (Join-Path $ShimDir 'claude-account.ps1')
$ShimCli = Join-Path $ShimDir 'claude-account.ps1'

function RunShimCli {
    param([string[]]$CliArguments)
    $exe = (Get-Process -Id $PID).Path
    $all = @('-NoLogo','-NoProfile','-File', $ShimCli) + $CliArguments
    $out = & $exe @all 2>&1 | Out-String
    return @{ Output = $out; Code = $LASTEXITCODE }
}
function AssertShimOk   { param($n, [string[]]$a) $r = RunShimCli $a; if ($r.Code -eq 0) { Ok $n } else { Bad $n "exit $($r.Code): $($r.Output)" } }
function AssertShimFail { param($n, [string[]]$a) $r = RunShimCli $a; if ($r.Code -ne 0) { Ok $n } else { Bad $n "expected failure: $($r.Output)" } }
function AssertShimHas  { param($n, $needle, [string[]]$a) $r = RunShimCli $a; if ($r.Output -like "*$needle*") { Ok $n } else { Bad $n "expected '$needle' in: $($r.Output)" } }

AssertShimOk   'link work -> claude1' @('link','work','claude1')
if (Test-Path -LiteralPath (Join-Path $ShimDir 'claude1.cmd')) { Ok 'the shim file exists' } else { Bad 'the shim file exists' }
AssertShimHas  'links lists it' 'claude1' @('links')
AssertShimHas  'links shows the account' 'work' @('links')
$linksOut = (RunShimCli @('links')).Output
if ($linksOut -notlike '*claude-account*') { Ok 'links does not list the tool itself' } else { Bad 'links does not list the tool itself' $linksOut }

AssertShimOk   'link default -> claude0' @('link','default','claude0')
AssertShimFail 'link refuses to shadow claude' @('link','work','claude')
AssertShimFail 'link refuses to shadow claude-account' @('link','work','claude-account')
AssertShimFail 'link refuses a hostile shortcut name' @('link','work','../evil')
AssertShimFail 'link refuses a missing account' @('link','ghost','claude9')
AssertShimFail 'link with one arg fails' @('link','work')
AssertShimFail 'link over an existing shortcut fails' @('link','nologin','claude1')
AssertShimOk   'link --force repoints it' @('link','nologin','claude1','--force')
AssertShimHas  'the repoint took effect' 'nologin' @('links')

$foreign = Join-Path $ShimDir 'notours.cmd'
Set-Content -LiteralPath $foreign -Value "@echo off`r`necho not ours" -Encoding ASCII
AssertShimFail 'link refuses to overwrite a foreign file' @('link','work','notours')
if ((Get-Content -LiteralPath $foreign -Raw) -like '*not ours*') { Ok 'the foreign file is intact' } else { Bad 'the foreign file is intact' }
AssertShimFail 'unlink refuses a foreign file' @('unlink','notours')
if (Test-Path -LiteralPath $foreign) { Ok 'the foreign file survived' } else { Bad 'the foreign file survived' }
AssertShimFail 'unlink of a missing shortcut fails' @('unlink','nosuch')
AssertShimOk   'unlink removes the shim' @('unlink','claude1')
if (-not (Test-Path -LiteralPath (Join-Path $ShimDir 'claude1.cmd'))) { Ok 'the shim is gone' } else { Bad 'the shim is gone' }
AssertShimOk   'cleanup: unlink claude0' @('unlink','claude0')

# ---------------------------------------------------------------------------
Group 'rename'
AssertOk       'rename work -> company' @('rename','work','company')
if (Test-Path -LiteralPath (Join-Path $env:CLAUDE_ACCOUNTS_HOME 'company')) { Ok 'new dir exists' } else { Bad 'new dir exists' }
if (-not (Test-Path -LiteralPath (Join-Path $env:CLAUDE_ACCOUNTS_HOME 'work'))) { Ok 'old dir is gone' } else { Bad 'old dir is gone' }
AssertContains 'session survived the rename' 'work@example.com' @('status','company')
AssertFail     'rename onto an existing name fails' @('rename','company','nologin')
AssertFail     'rename to itself fails' @('rename','company','company')
AssertFail     'rename to a reserved name fails' @('rename','company','default')
AssertFail     'rename with one arg fails' @('rename','company')
AssertFail     'rename a missing account fails' @('rename','ghost','other')

# ---------------------------------------------------------------------------
Group 'remove'
AssertOk   'remove --yes works' @('remove','--yes','nologin')
if (-not (Test-Path -LiteralPath (Join-Path $env:CLAUDE_ACCOUNTS_HOME 'nologin'))) { Ok 'the directory is gone' } else { Bad 'the directory is gone' }
AssertFail 'removing it again fails' @('remove','--yes','nologin')
AssertFail 'remove with no name fails' @('remove','--yes')

# ---------------------------------------------------------------------------
Group 'source hygiene'
$src = Get-Content -LiteralPath $Cli -Raw
if ($src -notmatch 'Invoke-Expression|\biex\b') { Ok 'the CLI never uses Invoke-Expression' } else { Bad 'the CLI never uses Invoke-Expression' }
if ($src -match 'Remove-Item -LiteralPath \$dir -Recurse -Force') { Ok 'deletion goes through the guarded path' } else { Bad 'deletion goes through the guarded path' }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '---------------------------------------------'
Write-Host "passed: $($script:Pass)   failed: $($script:Fail)"
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:Fail -gt 0) { exit 1 }
Write-Host 'all tests passed' -ForegroundColor Green
# Explicit: without this the script inherits $LASTEXITCODE from the last child
# process, and the last assertion deliberately expects a non-zero exit.
exit 0
