#!/usr/bin/env bash
# aes-managed:v1 — installed by "agent-enforcement system". Safe to edit; edits
# are preserved (the installer never overwrites a file you have changed unless
# it still carries this marker AND you pass --force).
#
# preflight.sh — read-only guardrail check. Run BEFORE doing work in this repo.
# It never writes, never pushes, never deploys, never touches app source.
#
#   ./scripts/preflight.sh            # check, human output
#   ./scripts/preflight.sh --quiet    # only report problems
#
# Exit: 0 = clear to proceed · 1 = hard failure · 0 with warnings = proceed with care
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$(basename "$ROOT")"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

fails=0; warns=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; O=$'\033[0m'
else R=""; G=""; Y=""; D=""; O=""; fi

fail() { printf '  %sFAIL%s %s\n' "$R" "$O" "$1"; fails=$((fails + 1)); }
warn() { printf '  %sWARN%s %s\n' "$Y" "$O" "$1"; warns=$((warns + 1)); }
pass() { [ "$QUIET" -eq 1 ] || printf '  %sok%s   %s\n' "$G" "$O" "$1"; }
note() { [ "$QUIET" -eq 1 ] || printf '  %s%s%s\n' "$D" "$1" "$O"; }

[ "$QUIET" -eq 1 ] || printf '\npreflight: %s\n\n' "$NAME"

# 1. Canonical path — never operate from a worktree, temp, or download dir.
case "$ROOT" in
  */_worktrees/*|*/.release-worktrees/*|*/.codex/worktrees/*|/tmp/*|/private/tmp/*|*/Downloads/*|*/Desktop/*)
    fail "non-canonical source path: $ROOT (never build/ship from here)" ;;
  *) pass "canonical source path" ;;
esac

# 2. Secret hygiene — nothing secret may be tracked or staged.
SECRET_RE='\.env$|\.env\.[a-z]+$|\.pem$|\.p8$|\.p12$|\.keystore$|\.jks$|id_rsa|service-account.*\.json$|credentials\.json$|\.mobileprovision$'
ALLOW_RE='(^|[./_-])(example|sample|template|dist|placeholder)([./_-]|$)|\.md$'
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  tracked="$(git -C "$ROOT" ls-files 2>/dev/null | grep -Ei "$SECRET_RE" | grep -Eiv "$ALLOW_RE" || true)"
  if [ -n "$tracked" ]; then
    fail "secret-shaped files tracked by git:"
    printf '%s\n' "$tracked" | sed 's/^/         /'
  else
    pass "no secret-shaped files tracked"
  fi

  staged="$(git -C "$ROOT" diff --cached --name-only 2>/dev/null | grep -Ei "$SECRET_RE" | grep -Eiv "$ALLOW_RE" || true)"
  [ -n "$staged" ] && fail "secret-shaped files staged for commit: $staged"

  # 3. Git posture — informational, never blocking.
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  dirty="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -c '^' || true)"
  note "branch: $branch · uncommitted files: $dirty"
  [ "$branch" = "HEAD" ] && warn "detached HEAD — commit will not land on a branch"
else
  warn "not a git repository — agent work here is not autosaved"
fi

# 4. Context files the operating rules require.
[ -f "$ROOT/AGENTS.md" ] && pass "AGENTS.md present" || warn "no AGENTS.md — agents will act without project context"
[ -f "$ROOT/STATUS.md" ] && pass "STATUS.md present" || warn "no STATUS.md — required for every project"

# 5. Deploy targets — surface them, never act on them.
#    COMMIT != PUSH != DEPLOY. This only tells you what a deploy WOULD hit.
for cfg in wrangler.toml wrangler.jsonc netlify.toml; do
  [ -f "$ROOT/$cfg" ] || continue
  target="$(grep -Eo '^[[:space:]]*(name|site)[[:space:]]*=[[:space:]]*"[^"]+"' "$ROOT/$cfg" 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')"
  note "deploy target declared in $cfg: ${target:-<unparsed>} (deploy needs explicit per-session consent)"
done

if [ "$QUIET" -eq 0 ] || [ "$fails" -gt 0 ] || [ "$warns" -gt 0 ]; then
  printf '\n  %d failure(s), %d warning(s)\n\n' "$fails" "$warns"
fi
[ "$fails" -gt 0 ] && exit 1
exit 0
