#!/usr/bin/env bash
# run-all.sh - every check the kit has, in one go, inside a throwaway HOME.
#
#   bash scripts/tests/run-all.sh                 # everything
#   KIT_DENYLIST_FILE=/path/deny.txt bash ...     # also scan for your own extra private strings
#
# Sets HOME to a fresh sandbox with the repo linked at $HOME/.claude-kit (the real ~/.claude is
# never touched), then runs: syntax checks (bash -n, Python compile, node --check, jq), the
# personal-data scan, the agent-reference check, both end-to-end tests, and every shipped
# scripts/hooks/test-*.sh plus verify-test-integrity.sh. Prints a summary table; exit 1 on any FAIL.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kit-runall.XXXXXX"); SANDBOX=$(cd "$SANDBOX" && pwd -P)
LOGDIR="$SANDBOX/logs"; mkdir -p "$LOGDIR" "$SANDBOX/.claude/progress" "$SANDBOX/.claude/logs"
chmod 700 "$SANDBOX/.claude/progress"
ln -s "$REPO" "$SANDBOX/.claude-kit"
KEEP_LOGS=${KEEP_LOGS:-0}
trap '[ "$KEEP_LOGS" = 1 ] || rm -rf "$SANDBOX"' EXIT

# The sandbox must not inherit the caller's live session identity.
unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CLAUDECODE CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true

RESULTS=""
NFAIL=0
record() {  # $1 name, $2 PASS|FAIL, $3 seconds, $4 note
  RESULTS="$RESULTS$(printf '%-44s %-5s %4ss  %s' "$1" "$2" "$3" "${4:-}")\n"
  [ "$2" = FAIL ] && NFAIL=$((NFAIL+1))
  printf '%-5s %s%s\n' "$2" "$1" "${4:+  ($4)}"
}

run_step() {  # $1 name, rest = command (run with HOME=sandbox, cwd=repo)
  local name="$1"; shift
  local log="$LOGDIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_').log" t0 rc
  t0=$(date +%s)
  ( cd "$REPO" && HOME="$SANDBOX" "$@" ) > "$log" 2>&1; rc=$?
  if [ "$rc" = 0 ]; then record "$name" PASS "$(( $(date +%s) - t0 ))"
  else
    record "$name" FAIL "$(( $(date +%s) - t0 ))" "rc=$rc"
    echo "      --- last lines of $name ---"; grep -E 'FAIL|Error|error|rc=' "$log" | tail -n 15 | sed 's/^/      /'
    [ -s "$log" ] && ! grep -qE 'FAIL|Error|error|rc=' "$log" && tail -n 10 "$log" | sed 's/^/      /'
  fi
}

# ── syntax checks ───────────────────────────────────────────────────────
syntax_bash() {
  local bad=0 f
  while IFS= read -r f; do bash -n "$f" 2>&1 || { echo "SYNTAX $f"; bad=1; }; done \
    < <(find . -type d \( -name .git -o -name node_modules \) -prune -o -type f -name '*.sh' -print)
  return $bad
}
syntax_python() {  # compile in memory: py_compile would drop __pycache__ into the repo
  local bad=0 f
  while IFS= read -r f; do
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$f" 2>&1 || { echo "SYNTAX $f"; bad=1; }
  done < <(find . -type d \( -name .git -o -name __pycache__ -o -name node_modules \) -prune -o -type f -name '*.py' -print)
  return $bad
}
syntax_node() {
  local bad=0 f
  while IFS= read -r f; do node --check "$f" 2>&1 || { echo "SYNTAX $f"; bad=1; }; done \
    < <(find scripts commands -type d -name node_modules -prune -o -type f \( -name '*.mjs' -o -name '*.js' \) -print)
  return $bad
}
syntax_json() {
  local bad=0 f
  while IFS= read -r f; do jq . "$f" >/dev/null 2>&1 || { echo "INVALID JSON $f"; bad=1; }; done \
    < <(find . -type d \( -name .git -o -name node_modules \) -prune -o -type f -name '*.json' -print)
  return $bad
}
executable_bits() {  # every hook the settings fragment runs directly must be executable
  local bad=0 p
  while IFS= read -r p; do
    [ -x "$p" ] || { echo "NOT EXECUTABLE $p"; bad=1; }
  done < <(jq -r '.hooks[][].hooks[].command' settings/kit-settings.json | grep -vE '^(bash|python3) ' | sed "s#__KIT__#$REPO#")
  return $bad
}

echo "omid_skills test run (sandbox HOME: $SANDBOX)"
echo ""
run_step "syntax: bash -n *.sh"            syntax_bash
run_step "syntax: python compile *.py"     syntax_python
run_step "syntax: node --check *.mjs/*.js" syntax_node
run_step "syntax: jq . *.json"             syntax_json
run_step "hooks run directly are executable" executable_bits
run_step "check-no-personal"               bash scripts/tests/check-no-personal.sh
run_step "check-agent-refs"                bash scripts/tests/check-agent-refs.sh
run_step "e2e-install"                     bash scripts/tests/e2e-install.sh
run_step "e2e-precompact-chain"            bash scripts/tests/e2e-precompact-chain.sh
if [ -f "$REPO/scripts/tests/check-claude-fallback.sh" ]; then
  run_step "check-claude-fallback"         bash scripts/tests/check-claude-fallback.sh
fi
for t in "$REPO"/scripts/hooks/test-*.sh "$REPO/scripts/hooks/verify-test-integrity.sh"; do
  [ -f "$t" ] || continue
  run_step "hooks/$(basename "$t")" bash "$t"
done

echo ""
echo "================================ SUMMARY ================================"
printf '%b' "$RESULTS"
echo "========================================================================="
if [ "$NFAIL" = 0 ]; then echo "ALL PASSED"; else echo "$NFAIL FAILED  (re-run with KEEP_LOGS=1 to keep full logs in $LOGDIR)"; fi
[ "$NFAIL" = 0 ]
