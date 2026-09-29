#!/usr/bin/env bash
# aes-managed:v1 — installed by "agent-enforcement system". Safe to edit; edits
# are preserved (the installer never overwrites a file you have changed unless
# it still carries this marker AND you pass --force).
#
# verify.sh — prove this repo is in a sane, shippable-shaped state.
# Read-only by default: no writes, no network, no installs, no deploys.
#
#   ./scripts/verify.sh               # structural verify (fast, offline)
#   AES_VERIFY_FULL=1 ./scripts/verify.sh
#                                     # also runs this project's own test/verify
#                                     # target, which MAY hit network/deps
#
# Exit: 0 = pass · 1 = fail
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$(basename "$ROOT")"
fails=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; D=$'\033[2m'; O=$'\033[0m'
else R=""; G=""; D=""; O=""; fi
fail() { printf '  %sFAIL%s %s\n' "$R" "$O" "$1"; fails=$((fails + 1)); }
pass() { printf '  %sok%s   %s\n' "$G" "$O" "$1"; }
note() { printf '  %s%s%s\n' "$D" "$1" "$O"; }

printf '\nverify: %s\n\n' "$NAME"

# 1. Guardrails must be intact and runnable.
if [ -x "$ROOT/scripts/preflight.sh" ]; then
  if "$ROOT/scripts/preflight.sh" --quiet; then
    pass "preflight clean"
  else
    fail "preflight reported a hard failure"
  fi
else
  fail "scripts/preflight.sh missing or not executable"
fi

# 2. Shell scripts must parse. Syntax only — nothing is executed.
sh_checked=0; sh_bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Check with the interpreter the script actually declares. zsh and bash
  # disagree on real syntax (case/esac, globbing), so guessing produces
  # false failures on perfectly good scripts.
  checker=bash
  case "$(head -1 "$f" 2>/dev/null)" in
    *zsh*) checker=zsh ;;
    *' sh'|*'/sh') checker=sh ;;
  esac
  command -v "$checker" >/dev/null 2>&1 || continue
  sh_checked=$((sh_checked + 1))
  "$checker" -n "$f" 2>/dev/null || { fail "shell syntax error ($checker): ${f#"$ROOT"/}"; sh_bad=$((sh_bad + 1)); }
done < <(find "$ROOT" -maxdepth 2 \( -name node_modules -o -name .git -o -name vendor -o -name Pods \) -prune -o -type f \( -name '*.sh' -o -name '*.zsh' \) -print 2>/dev/null)
[ "$sh_checked" -gt 0 ] && [ "$sh_bad" -eq 0 ] && pass "$sh_checked shell script(s) parse"

# 3. Python must parse. Syntax check only — nothing is executed, no bytecode
#    is written, so the repo and __pycache__ stay untouched.
if command -v python3 >/dev/null 2>&1; then
  py_checked=0; py_bad=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    py_checked=$((py_checked + 1))
    python3 -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' "$f" 2>/dev/null \
      || { fail "python syntax error: ${f#"$ROOT"/}"; py_bad=$((py_bad + 1)); }
  done < <(find "$ROOT" -maxdepth 2 \( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name __pycache__ \) -prune -o -type f -name '*.py' -print 2>/dev/null)
  [ "$py_checked" -gt 0 ] && [ "$py_bad" -eq 0 ] && pass "$py_checked python file(s) parse"
fi

# 4. Config files must be valid — a broken manifest breaks every downstream tool.
#    package.json/app.json are strict JSON. tsconfig.json is JSONC: TypeScript
#    accepts comments and trailing commas there, so it is checked leniently.
if command -v python3 >/dev/null 2>&1; then
  for j in package.json app.json composer.json; do
    [ -f "$ROOT/$j" ] || continue
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$ROOT/$j" 2>/dev/null \
      && pass "$j is valid JSON" || fail "$j is not valid JSON"
  done
  if [ -f "$ROOT/tsconfig.json" ]; then
    python3 - "$ROOT/tsconfig.json" <<'PY' 2>/dev/null && pass "tsconfig.json is valid JSONC" || fail "tsconfig.json is not parseable"
import json, re, sys

def strip_jsonc(s):
    """Remove comments, leaving string literals intact.

    Scans left to right rather than pattern-matching: a path like "@/*" holds
    a /* that is data, not a comment, and regex cannot tell the difference.
    """
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':                      # string literal — copy verbatim
            j = i + 1
            while j < n:
                if s[j] == '\\':
                    j += 2
                    continue
                if s[j] == '"':
                    break
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
        elif s.startswith('//', i):
            j = s.find('\n', i)
            i = n if j < 0 else j
        elif s.startswith('/*', i):
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)

src = strip_jsonc(open(sys.argv[1]).read())
# Trailing commas are legal in tsconfig. Commas inside strings are now the only
# ones left to protect, so mask strings before dropping them.
lits = []
src = re.sub(r'"(?:\\.|[^"\\])*"', lambda m: (lits.append(m.group(0)), f'\x00{len(lits)-1}\x00')[1], src)
src = re.sub(r',(\s*[}\]])', r'\1', src)
src = re.sub(r'\x00(\d+)\x00', lambda m: lits[int(m.group(1))], src)
json.loads(src)
PY
  fi
fi

# 5. Optional: the project's own verification. Off by default because it can
#    install, hit the network, or take minutes.
if [ "${AES_VERIFY_FULL:-0}" = "1" ]; then
  if [ -f "$ROOT/package.json" ] && command -v npm >/dev/null 2>&1; then
    if npm run 2>/dev/null | grep -qE '^[[:space:]]+verify$'; then
      note "running: npm run verify"
      npm run --silent verify || fail "npm run verify failed"
    elif npm run 2>/dev/null | grep -qE '^[[:space:]]+test$'; then
      note "running: npm test"
      npm test --silent || fail "npm test failed"
    fi
  elif [ -f "$ROOT/Makefile" ] && grep -qE '^verify:' "$ROOT/Makefile" 2>/dev/null; then
    note "running: make verify"
    make -C "$ROOT" verify || fail "make verify failed"
  else
    note "no project-native verify target found — structural checks only"
  fi
fi

if [ "$fails" -eq 0 ]; then
  printf '\n  %sPASS%s %s\n\n' "$G" "$O" "$NAME"
  exit 0
fi
printf '\n  %sFAIL%s %s — %d problem(s)\n\n' "$R" "$O" "$NAME" "$fails"
exit 1
