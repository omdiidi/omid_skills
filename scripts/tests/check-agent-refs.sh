#!/usr/bin/env bash
# check-agent-refs.sh - every agent a shipped command dispatches must exist in agents/.
#
# Sources of agent names (all files under commands/):
#   subagent_type: "name"   subagent_type: name   "subagent_type": "name"   subagent_type=name
#   `name` agent            `name` subagent
# Built-in agents (general-purpose, Explore, Plan, claude-code-guide, statusline-setup) are
# provided by Claude Code itself and are skipped. A fixed list of agents the core pipelines need
# must also exist. Exit 1 listing every miss.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd "$REPO" || exit 2

BUILTINS=" general-purpose explore plan claude-code-guide statusline-setup fork "
REQUIRED="plan-reviewer criticer parallelizer implementer implementation-reviewer review-lane-sonnet review-worker codebase-explorer researcher codex-fallback-reviewer"

FOUND=$( {
  grep -rhoE '"?subagent_type"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9-]+' commands 2>/dev/null \
    | sed -E 's/.*[:=][[:space:]]*"?//'
  grep -rhoE '`[a-z0-9-]+` (sub)?agent' commands 2>/dev/null | sed -E 's/^`([a-z0-9-]+)`.*/\1/'
} | sort -u )

MISSES=""
CHECKED=0
for name in $FOUND; do
  lower=$(printf '%s' "$name" | tr 'A-Z' 'a-z')
  case "$BUILTINS" in *" $lower "*) continue ;; esac
  CHECKED=$((CHECKED+1))
  if [ ! -f "agents/$name.md" ]; then
    where=$(grep -rlE "(subagent_type\"?[[:space:]]*[:=][[:space:]]*\"?$name\b|\`$name\` (sub)?agent)" commands 2>/dev/null | head -3 | tr '\n' ' ')
    MISSES="$MISSES\n  referenced but missing: agents/$name.md  (in: $where)"
  fi
done
for name in $REQUIRED; do
  [ -f "agents/$name.md" ] || MISSES="$MISSES\n  required but missing: agents/$name.md"
done

if [ -n "$MISSES" ]; then
  printf 'check-agent-refs: FAIL%b\n' "$MISSES"
  exit 1
fi
echo "check-agent-refs: OK ($CHECKED referenced agents + $(echo $REQUIRED | wc -w | tr -d ' ') required agents all present)"
