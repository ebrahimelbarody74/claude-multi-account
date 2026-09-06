#!/usr/bin/env bash
#
# Test suite for claude-account.
#
# Runs against a throwaway CLAUDE_ACCOUNTS_HOME and a fake `claude` binary, so it
# never touches your real accounts, your real ~/.claude, or the network.
#
#   ./tests/run-tests.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/claude-account"

WORK="$(mktemp -d -t claude-account-tests.XXXXXX)"
export CLAUDE_ACCOUNTS_HOME="$WORK/accounts"
export HOME_GUARD="$WORK/home-guard"
export NO_COLOR=1

FAKE_BIN="$WORK/fakebin"
mkdir -p "$FAKE_BIN" "$HOME_GUARD/.claude"
echo "do not delete me" > "$HOME_GUARD/.claude/sentinel"

# A fake `claude` that reports a different identity per CLAUDE_CONFIG_DIR and
# records exactly which arguments it received.
cat > "$FAKE_BIN/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_ARGS_FILE:-/dev/null}"
printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR-<unset>}" > "${FAKE_ENV_FILE:-/dev/null}"

if [ "${1-}" = "auth" ] && [ "${2-}" = "status" ]; then
  dir="${CLAUDE_CONFIG_DIR-}"
  if [ -z "$dir" ]; then
    cat <<'J'
{
  "loggedIn": true,
  "authMethod": "claude.ai",
  "email": "default@example.com",
  "orgName": "Default Org",
  "subscriptionType": "max"
}
J
    exit 0
  fi
  if [ -f "$dir/.logged-in" ]; then
    email="$(cat "$dir/.logged-in")"
    printf '{\n  "loggedIn": true,\n  "authMethod": "claude.ai",\n  "email": "%s",\n  "orgName": "Test Org",\n  "subscriptionType": "pro"\n}\n' "$email"
    exit 0
  fi
  printf '{\n  "loggedIn": false,\n  "authMethod": "none"\n}\n'
  exit 1
fi

if [ "${1-}" = "auth" ] && [ "${2-}" = "login" ]; then
  [ -n "${CLAUDE_CONFIG_DIR-}" ] || { echo "login without CLAUDE_CONFIG_DIR" >&2; exit 2; }
  printf '%s\n' "${FAKE_LOGIN_EMAIL:-someone@example.com}" > "$CLAUDE_CONFIG_DIR/.logged-in"
  echo "signed in"
  exit 0
fi

echo "claude ran with: $*"
exit 0
FAKE
chmod +x "$FAKE_BIN/claude"
export PATH="$FAKE_BIN:$PATH"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2-}" ] && printf '       %s\n' "$2"; }
group(){ printf '\n%s\n' "$1"; }

# assert_ok <label> <cmd...>
assert_ok() {
  local label="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -eq 0 ]; then ok "$label"; else bad "$label" "exit $rc: $out"; fi
}

# assert_fail <label> <cmd...>
assert_fail() {
  local label="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -ne 0 ]; then ok "$label"; else bad "$label" "expected failure, got exit 0: $out"; fi
}

# assert_contains <label> <needle> <cmd...>
assert_contains() {
  local label="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  case "$out" in
    *"$needle"*) ok "$label" ;;
    *) bad "$label" "expected to find '$needle' in: $out" ;;
  esac
}

# assert_not_contains <label> <needle> <cmd...>
assert_not_contains() {
  local label="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  case "$out" in
    *"$needle"*) bad "$label" "did not expect '$needle' in: $out" ;;
    *) ok "$label" ;;
  esac
}

printf 'claude-account test suite\n'
printf 'sandbox: %s\n' "$WORK"

# ---------------------------------------------------------------------------
group 'basics'
# ---------------------------------------------------------------------------
assert_contains 'version prints a version' 'claude-account 1' "$CLI" version
assert_contains 'help lists the commands' 'rename <old> <new>' "$CLI" help
assert_contains 'no args prints help' 'USAGE' "$CLI"
assert_fail     'unknown command fails' "$CLI" definitely-not-a-command
assert_fail     'unknown option fails' "$CLI" --nope

# ---------------------------------------------------------------------------
group 'add'
# ---------------------------------------------------------------------------
FAKE_LOGIN_EMAIL='work@example.com' assert_ok 'add work' "$CLI" add work
assert_ok       'account dir exists' test -d "$CLAUDE_ACCOUNTS_HOME/work"
assert_contains 'add is idempotent-safe (rejects duplicate)' 'already exists' "$CLI" add work
assert_ok       'add --no-login skips sign-in' "$CLI" add nologin --no-login
assert_ok       'no-login account has no session' test ! -f "$CLAUDE_ACCOUNTS_HOME/nologin/.logged-in"
assert_fail     'add with no name fails' "$CLI" add
assert_fail     'add rejects two names' "$CLI" add a b
assert_fail     'add rejects unknown option' "$CLI" add x --bogus

perms="$(stat -f '%Lp' "$CLAUDE_ACCOUNTS_HOME" 2>/dev/null || stat -c '%a' "$CLAUDE_ACCOUNTS_HOME" 2>/dev/null)"
if [ "$perms" = "700" ]; then ok 'accounts root is 0700'; else bad 'accounts root is 0700' "got $perms"; fi

# ---------------------------------------------------------------------------
group 'path traversal and hostile names'
# ---------------------------------------------------------------------------
for evil in '../evil' '../../etc/passwd' '/etc/passwd' 'a/b' '.hidden' '-rf' '..' '.' 'a b' 'a;rm -rf /' 'a$(id)' 'a`id`' 'a|b' 'a&b' 'a>b' 'a*' 'a?' 'a\b' '~root' 'a"b' "a'b" '' '新しい'; do
  assert_fail "rejects add '$evil'" "$CLI" add "$evil"
  assert_fail "rejects remove '$evil'" "$CLI" remove --yes "$evil"
  assert_fail "rejects rename '$evil'" "$CLI" rename "$evil" safe
  assert_fail "rejects path '$evil'" "$CLI" path "$evil"
done

longname=""
while [ ${#longname} -lt 200 ]; do longname="${longname}aaaaaaaaaa"; done
assert_fail 'rejects an over-long name' "$CLI" add "$longname"
assert_ok   'nothing escaped the accounts root' test ! -e "$WORK/evil"
assert_ok   'no directory was created outside accounts' test "$(find "$CLAUDE_ACCOUNTS_HOME" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "2"

# ---------------------------------------------------------------------------
group 'reserved names'
# ---------------------------------------------------------------------------
for reserved in default list add use remove rename status help version path env shell; do
  assert_fail "rejects add '$reserved'" "$CLI" add "$reserved"
done
assert_fail 'cannot remove default' "$CLI" remove --yes default
assert_fail 'cannot rename default' "$CLI" rename default other

# ---------------------------------------------------------------------------
group 'list and status'
# ---------------------------------------------------------------------------
assert_contains 'list shows default'        'default'           "$CLI" list
assert_contains 'list shows work'           'work'              "$CLI" list
assert_contains 'list shows the email'      'work@example.com'  "$CLI" list
assert_contains 'list shows the plan'       'pro'               "$CLI" list
assert_contains 'list marks logged out'     'logged out'        "$CLI" list
assert_contains 'status work: email'        'work@example.com'  "$CLI" status work
assert_contains 'status work: plan'         'pro'               "$CLI" status work
assert_contains 'status work: directory'    "$CLAUDE_ACCOUNTS_HOME/work" "$CLI" status work
assert_contains 'status default is default' 'default@example.com' "$CLI" status default
assert_contains 'status with no arg = default' 'default@example.com' "$CLI" status
assert_fail     'status of a logged-out account exits nonzero' "$CLI" status nologin
assert_fail     'status of a missing account fails' "$CLI" status ghost

# ---------------------------------------------------------------------------
group 'running claude with the right env'
# ---------------------------------------------------------------------------
export FAKE_ARGS_FILE="$WORK/args.txt" FAKE_ENV_FILE="$WORK/env.txt"

"$CLI" work >/dev/null 2>&1
assert_contains 'bare name sets CLAUDE_CONFIG_DIR' "CLAUDE_CONFIG_DIR=$CLAUDE_ACCOUNTS_HOME/work" cat "$WORK/env.txt"

"$CLI" use work >/dev/null 2>&1
assert_contains 'use sets CLAUDE_CONFIG_DIR' "CLAUDE_CONFIG_DIR=$CLAUDE_ACCOUNTS_HOME/work" cat "$WORK/env.txt"

"$CLI" work -p 'hello world' --model opus >/dev/null 2>&1
printf -- '-p\nhello world\n--model\nopus\n' > "$WORK/expected-args.txt"
if diff -q "$WORK/args.txt" "$WORK/expected-args.txt" >/dev/null; then
  ok 'arguments (including a quoted one) pass through unchanged'
else
  bad 'arguments pass through unchanged' "$(cat "$WORK/args.txt")"
fi

"$CLI" default >/dev/null 2>&1
assert_contains 'default leaves CLAUDE_CONFIG_DIR unset' 'CLAUDE_CONFIG_DIR=<unset>' cat "$WORK/env.txt"

CLAUDE_CONFIG_DIR="$WORK/leaked" "$CLI" default >/dev/null 2>&1
assert_contains 'default strips an inherited CLAUDE_CONFIG_DIR' 'CLAUDE_CONFIG_DIR=<unset>' cat "$WORK/env.txt"

"$CLI" use default -p hi >/dev/null 2>&1
assert_contains 'use default is also unset' 'CLAUDE_CONFIG_DIR=<unset>' cat "$WORK/env.txt"

assert_fail 'running a missing account fails' "$CLI" ghost
assert_fail 'use with no name fails' "$CLI" use

# exit code propagation
cat > "$FAKE_BIN/claude" <<'FAKE2'
#!/usr/bin/env bash
if [ "$1" = "auth" ]; then printf '{\n  "loggedIn": true,\n  "email": "x@y.z"\n}\n'; exit 0; fi
exit 42
FAKE2
chmod +x "$FAKE_BIN/claude"
exit_code=0
"$CLI" work >/dev/null 2>&1 || exit_code=$?
if [ "$exit_code" -eq 42 ]; then
  ok "claude's exit code is propagated"
else
  bad "claude's exit code is propagated" "got $exit_code"
fi

# restore the full fake
cat > "$FAKE_BIN/claude" <<'FAKE3'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_ARGS_FILE:-/dev/null}"
printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR-<unset>}" > "${FAKE_ENV_FILE:-/dev/null}"
if [ "${1-}" = "auth" ] && [ "${2-}" = "status" ]; then
  dir="${CLAUDE_CONFIG_DIR-}"
  if [ -z "$dir" ]; then
    printf '{\n  "loggedIn": true,\n  "email": "default@example.com",\n  "subscriptionType": "max"\n}\n'; exit 0
  fi
  if [ -f "$dir/.logged-in" ]; then
    printf '{\n  "loggedIn": true,\n  "email": "%s",\n  "subscriptionType": "pro"\n}\n' "$(cat "$dir/.logged-in")"; exit 0
  fi
  printf '{\n  "loggedIn": false\n}\n'; exit 1
fi
if [ "${1-}" = "auth" ] && [ "${2-}" = "login" ]; then
  printf '%s\n' "${FAKE_LOGIN_EMAIL:-someone@example.com}" > "$CLAUDE_CONFIG_DIR/.logged-in"; exit 0
fi
exit 0
FAKE3
chmod +x "$FAKE_BIN/claude"

# ---------------------------------------------------------------------------
group 'path, env, shell'
# ---------------------------------------------------------------------------
assert_contains 'path prints the account dir' "$CLAUDE_ACCOUNTS_HOME/work" "$CLI" path work
assert_contains 'env prints an export line'   'export CLAUDE_CONFIG_DIR=' "$CLI" env work
assert_contains 'env default unsets'          'unset CLAUDE_CONFIG_DIR'   "$CLI" env default
assert_fail     'env of a missing account fails' "$CLI" env ghost
assert_not_contains 'env output contains no eval' 'eval' "$CLI" env work

# ---------------------------------------------------------------------------
group 'rename'
# ---------------------------------------------------------------------------
assert_ok       'rename work -> company' "$CLI" rename work company
assert_ok       'new dir exists' test -d "$CLAUDE_ACCOUNTS_HOME/company"
assert_ok       'old dir is gone' test ! -d "$CLAUDE_ACCOUNTS_HOME/work"
assert_contains 'session survived the rename' 'work@example.com' "$CLI" status company
assert_fail     'rename onto an existing name fails' "$CLI" rename company nologin
assert_fail     'rename to itself fails' "$CLI" rename company company
assert_fail     'rename to a reserved name fails' "$CLI" rename company default
assert_fail     'rename with one arg fails' "$CLI" rename company
assert_fail     'rename a missing account fails' "$CLI" rename ghost other

# ---------------------------------------------------------------------------
group 'remove'
# ---------------------------------------------------------------------------
assert_fail 'remove without a tty and without --yes refuses' bash -c "$CLI remove nologin < /dev/null"
assert_ok   'the account survived that refusal' test -d "$CLAUDE_ACCOUNTS_HOME/nologin"
assert_ok   'remove --yes works' "$CLI" remove --yes nologin
assert_ok   'the directory is gone' test ! -d "$CLAUDE_ACCOUNTS_HOME/nologin"
assert_fail 'removing it again fails' "$CLI" remove --yes nologin
assert_fail 'remove with no name fails' "$CLI" remove --yes

# ---------------------------------------------------------------------------
group 'destructive-operation guards'
# ---------------------------------------------------------------------------
assert_ok 'the real ~/.claude sentinel is untouched' test -f "$HOME_GUARD/.claude/sentinel"
if [ -d "$HOME/.claude" ]; then
  ok 'the real ~/.claude still exists'
else
  ok 'no real ~/.claude on this machine (nothing to protect)'
fi
assert_ok 'the accounts root itself still exists' test -d "$CLAUDE_ACCOUNTS_HOME"

# ---------------------------------------------------------------------------
group 'source hygiene'
# ---------------------------------------------------------------------------
if grep -nE '(^|[^_[:alnum:]])eval[[:space:]]' "$CLI" | grep -v '^\s*#' | grep -q .; then
  bad 'the CLI never calls eval' "$(grep -nE '(^|[^_[:alnum:]])eval[[:space:]]' "$CLI")"
else
  ok 'the CLI never calls eval'
fi
# Every rm in the CLI must be the single guarded account removal.
rm_lines="$(grep -nE '(^|[^[:alnum:]_])rm[[:space:]]+-' "$CLI" | grep -v '^\s*[0-9]*:\s*#')"
if [ "$(printf '%s\n' "$rm_lines" | grep -c 'rm -rf -- "\$dir"')" = "1" ] && \
   [ "$(printf '%s\n' "$rm_lines" | grep -c .)" = "1" ]; then
  ok 'the CLI has exactly one rm, and it is the guarded account removal'
else
  bad 'the CLI has exactly one rm, and it is the guarded account removal' "$rm_lines"
fi
if grep -qE 'rm[[:space:]]+-rf[[:space:]]+"?\$HOME"?[[:space:]]*$|rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*$' "$CLI"; then
  bad 'the CLI never rm -rf a home path or /'
else
  ok 'the CLI never rm -rf a home path or /'
fi
# Build the pattern at runtime so this file does not match itself.
secret_pat="(sk""-ant-|ANTHROPIC_API_KEY[[:space:]]*=[[:space:]]*[\"'][^\"']+|OAUTH_TOKEN[[:space:]]*=[[:space:]]*[\"'][^\"']+)"
hits="$(grep -RIlE "$secret_pat" "$REPO_ROOT" --exclude-dir=.git --exclude="$(basename "${BASH_SOURCE[0]}")" 2>/dev/null)"
if [ -n "$hits" ]; then
  bad 'no credentials committed in the repo' "$hits"
else
  ok 'no credentials committed in the repo'
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' '---------------------------------------------'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ] || exit 1
printf 'all tests passed\n'
