#!/usr/bin/env bash
# e2e-install.sh - install / update / uninstall the kit inside a throwaway HOME.
# Never touches the real ~/.claude. The repo is COPIED (not linked) to $SANDBOX/.claude-kit so
# install.sh's "must live at ~/.claude-kit" check passes and the mutation step can edit the copy.
#
# Usage: bash scripts/tests/e2e-install.sh      (exit 0 = all pass)
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
PASS=0 FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s%s\n' "$1" "${2:+ - $2}"; }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

SANDBOXES=""
new_sandbox() {  # echoes a fresh sandbox HOME containing a copy of the kit
  local s; s=$(mktemp -d "${TMPDIR:-/tmp}/kit-e2e.XXXXXX"); s=$(cd "$s" && pwd -P)
  mkdir -p "$s/.claude-kit"
  ( cd "$REPO" && tar --exclude .git --exclude '__pycache__' -cf - . ) | ( cd "$s/.claude-kit" && tar -xf - )
  mkdir -p "$s/.claude"
  SANDBOXES="$SANDBOXES $s"
  printf '%s' "$s"
}
cleanup() { for s in $SANDBOXES; do rm -rf "$s"; done; }
trap cleanup EXIT

run_install() { local h="$1"; shift; HOME="$h" bash "$h/.claude-kit/install.sh" "$@" 2>&1; }
run_uninstall() { local h="$1"; shift; HOME="$h" bash "$h/.claude-kit/uninstall.sh" "$@" 2>&1; }

# ─────────────────────────────────────────────────────────────────────────────
echo "== A. fresh install over an existing user setup =="
H=$(new_sandbox); C="$H/.claude"; K="$H/.claude-kit"
cat > "$C/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo user-stop-hook" } ] } ]
  },
  "myCustomKey": { "keep": ["me", 1] },
  "statusLine": { "type": "command", "command": "echo my-status", "padding": 0 },
  "permissions": { "allow": ["Bash(ls:*)"] }
}
EOF
printf '# my own rules\nBe nice.\n' > "$C/CLAUDE.md"
mkdir -p "$C/commands"; printf 'my own plan command\n' > "$C/commands/plan.md"
cp "$C/settings.json" "$H/seed-settings.json"; cp "$C/CLAUDE.md" "$H/seed-claude.md"

OUT=$(run_install "$H" --yes --usage=off); RC=$?
check "no --statusline flag with an existing status bar -> exit 3" '[ "$RC" = 3 ]' "rc=$RC"
check "prints ASK_USER:statusline" 'printf "%s" "$OUT" | grep -q "^ASK_USER:statusline: "' "$OUT"
check "nothing changed before asking (settings identical)" 'cmp -s "$C/settings.json" "$H/seed-settings.json"'
check "nothing changed before asking (no manifest)" '[ ! -e "$C/.kit-install.json" ]'

OUT=$(run_install "$H" --yes --dry-run --statusline=keep --usage=off); RC=$?
check "dry run exits 0" '[ "$RC" = 0 ]' "rc=$RC $OUT"
check "dry run changes nothing" 'cmp -s "$C/settings.json" "$H/seed-settings.json" && [ ! -e "$C/.kit-install.json" ] && [ ! -L "$C/agents/criticer.md" ]'

OUT=$(run_install "$H" --statusline=keep --yes --usage=off); RC=$?
check "install with --statusline=keep exits 0" '[ "$RC" = 0 ]' "rc=$RC $OUT"
check "summary tells the user to restart" 'printf "%s" "$OUT" | grep -q "Restart Claude Code"'
check "agent linked into the kit" '[ -L "$C/agents/criticer.md" ] && [ "$(readlink "$C/agents/criticer.md")" = "$H/.claude-kit/agents/criticer.md" ]'
check "command in a subfolder linked" '[ -L "$C/commands/god-review/README.md" ] && [ -e "$C/commands/god-review/README.md" ]'
check "rule linked" '[ -L "$C/rules/verify-by-mechanism.md" ]'

RENDER_OK=1 RENDER_N=0
while IFS= read -r rel; do
  RENDER_N=$((RENDER_N+1)); t="$C/$rel"
  if [ -L "$t" ] || [ ! -f "$t" ] || grep -q '__KIT_ABS__' "$t" || ! grep -qF "$H/.claude-kit" "$t"; then RENDER_OK=0; echo "    bad render: $t"; fi
done < <(cd "$K" && grep -rl '__KIT_ABS__' commands agents rules 2>/dev/null)
check "files with __KIT_ABS__ rendered as real files with the absolute kit path ($RENDER_N)" '[ "$RENDER_OK" = 1 ] && [ "$RENDER_N" -ge 1 ]'

S="$C/settings.json"
check "kit hook merged (SessionStart primer)" 'jq -e --arg c "$H/.claude-kit/scripts/hooks/post-compact-primer.sh" "any(.hooks.SessionStart[].hooks[]; .command == \$c)" "$S" >/dev/null'
check "kit hook merged (PreCompact auto)" 'jq -e "any(.hooks.PreCompact[]; .matcher == \"auto\")" "$S" >/dev/null'
check "user Stop hook preserved" 'jq -e "any(.hooks.Stop[].hooks[]; .command == \"echo user-stop-hook\")" "$S" >/dev/null'
check "user custom key preserved" 'jq -e ".myCustomKey == {\"keep\":[\"me\",1]}" "$S" >/dev/null'
check "user allow rule kept + mission-write rule added (absolute path)" 'jq -e --arg r "Bash(bash $H/.claude-kit/scripts/hooks/mission-write.sh:*)" "(.permissions.allow | index(\"Bash(ls:*)\")) != null and (.permissions.allow | index(\$r)) != null" "$S" >/dev/null'
check "every kit allow rule added (placeholders rendered)" 'jq -e --slurpfile k "$H/.claude-kit/settings/kit-settings.json" --arg kit "$H/.claude-kit" "(\$k[0].permissions.allow | map(gsub(\"__KIT__\"; \$kit))) - .permissions.allow == []" "$S" >/dev/null'
check "crossSessionInbound + subagentPromptCacheTtl set" 'jq -e ".crossSessionInbound == \"accept\" and .subagentPromptCacheTtl == \"1h\"" "$S" >/dev/null'
check "no forbidden keys added" 'jq -e "(has(\"effortLevel\") or has(\"remoteControlAtStartup\") or (.permissions | has(\"defaultMode\")) or has(\"skipDangerousModePermissionPrompt\")) | not" "$S" >/dev/null'
check "no placeholders left in settings" '! grep -q "__KIT__\|__HOME__" "$S"'
if [ -f "$K/scripts/hooks/no-detach-gate.py" ]; then
  check "no-detach-gate registered (file ships)" 'grep -q "no-detach-gate.py" "$S"'
else
  check "no-detach-gate dropped (file does not ship)" '! grep -q "no-detach-gate.py" "$S"'
fi
HOOK_MISSING=""
while IFS= read -r cmd; do
  p=$(printf '%s' "$cmd" | tr ' ' '\n' | grep '\.claude-kit/' | head -1)
  [ -f "$p" ] || HOOK_MISSING="$HOOK_MISSING $p"
  case "$cmd" in bash\ *|python3\ *) ;; *) [ -x "$p" ] || HOOK_MISSING="$HOOK_MISSING (not executable)$p" ;; esac
done < <(jq -r '.hooks[][].hooks[].command' "$S" | grep '\.claude-kit/')
check "every kit hook command points at an existing file (executable when run directly)" '[ -z "$HOOK_MISSING" ]' "$HOOK_MISSING"
check "settings backup written" 'ls "$C"/settings.json.bak-* >/dev/null 2>&1'
check "backup equals the seed" 'cmp -s "$(ls "$C"/settings.json.bak-* | head -1)" "$H/seed-settings.json"'
check "foreign commands/plan.md moved aside with its content" 'grep -q "my own plan command" "$C"/commands/plan.md.bak-* && [ -L "$C/commands/plan.md" ]'
check "CLAUDE.md keeps user text + has the import block" 'grep -q "Be nice." "$C/CLAUDE.md" && grep -qF "<!-- >>> omid_skills >>> -->" "$C/CLAUDE.md" && grep -qxF "@~/.claude-kit/CLAUDE.md" "$C/CLAUDE.md"'
check "kit statusline linked" '[ -L "$C/kit-statusline.sh" ]'
check "wrapper exists and is executable" '[ -x "$C/kit-statusline-wrap.sh" ]'
check "statusLine points at the wrapper (other fields kept)" 'jq -e --arg w "$C/kit-statusline-wrap.sh" ".statusLine.command == \$w and .statusLine.padding == 0" "$S" >/dev/null'
WOUT=$(printf '{"session_id":"e2e-sid","context_window":{"used_percentage":42}}' | HOME="$H" "$C/kit-statusline-wrap.sh" 2>/dev/null)
check "wrapper still runs the user's own status bar" '[ "$WOUT" = "my-status" ]' "got '$WOUT'"
check "manifest recorded (keep mode + original statusline)" 'jq -e ".statusline_mode == \"keep\" and .original_statusline.command == \"echo my-status\" and (.links | length) > 50" "$C/.kit-install.json" >/dev/null'

# ─────────────────────────────────────────────────────────────────────────────
echo "== B. re-running is idempotent =="
jq -S . "$S" > "$H/after1.json"; N1=$(find "$C" -type l | wc -l)
OUT=$(run_install "$H" --statusline=keep --yes --usage=off); RC=$?
check "second install exits 0" '[ "$RC" = 0 ]' "$OUT"
check "settings identical after re-install (jq -S)" 'jq -S . "$S" | cmp -s - "$H/after1.json"'
check "same number of links" '[ "$(find "$C" -type l | wc -l)" = "$N1" ]'
OUT=$(run_install "$H"); RC=$?
check "update with NO flags reuses earlier answers (no question, exit 0)" '[ "$RC" = 0 ]' "rc=$RC $OUT"
check "settings still identical" 'jq -S . "$S" | cmp -s - "$H/after1.json"'

# ─────────────────────────────────────────────────────────────────────────────
echo "== C. update after the kit changed: no orphans =="
cp "$K/scripts/hooks/mission-liveness.sh" "$K/scripts/hooks/mission-liveness-v2.sh"
jq '(.hooks.Stop[].hooks[] | select(.command | endswith("mission-liveness.sh")) | .command) |= sub("mission-liveness\\.sh$"; "mission-liveness-v2.sh")' \
  "$K/settings/kit-settings.json" > "$H/frag.tmp" && mv "$H/frag.tmp" "$K/settings/kit-settings.json"
rm -f "$K/commands/line.md"
printf 'new command\n' > "$K/commands/zz-new.md"
OUT=$(run_install "$H" --yes); RC=$?
check "install after mutation exits 0" '[ "$RC" = 0 ]' "$OUT"
check "old hook command gone" '! jq -r ".hooks[][].hooks[].command" "$S" | grep -q "mission-liveness\.sh$"'
check "renamed hook command present exactly once" '[ "$(jq -r ".hooks[][].hooks[].command" "$S" | grep -c "mission-liveness-v2\.sh$")" = 1 ]'
check "link for a removed kit file is gone" '[ ! -e "$C/commands/line.md" ] && [ ! -L "$C/commands/line.md" ]'
check "new kit file linked" '[ -L "$C/commands/zz-new.md" ]'
check "no dangling links anywhere" '[ -z "$(find "$C" -type l ! -exec test -e {} \; -print)" ]'

# ─────────────────────────────────────────────────────────────────────────────
echo "== D. uninstall restores the user's setup =="
OUT=$(run_uninstall "$H" --yes --restore-backups); RC=$?
check "uninstall exits 0" '[ "$RC" = 0 ]' "$OUT"
check "settings equal the seed (jq -S)" 'diff <(jq -S . "$H/seed-settings.json") <(jq -S . "$S") >/dev/null' "$(diff <(jq -S . "$H/seed-settings.json") <(jq -S . "$S"))"
check "CLAUDE.md equals the seed" 'cmp -s "$C/CLAUDE.md" "$H/seed-claude.md"'
check "no links into the kit remain" '[ -z "$(find "$C" -type l)" ]'
check "wrapper, statusline link, manifest, usage marker gone" '[ ! -e "$C/kit-statusline-wrap.sh" ] && [ ! -L "$C/kit-statusline.sh" ] && [ ! -e "$C/.kit-install.json" ] && [ ! -e "$C/kit-usage-enabled" ]'
check "--restore-backups put the user's plan.md back" 'grep -q "my own plan command" "$C/commands/plan.md" && [ ! -L "$C/commands/plan.md" ]'

# ─────────────────────────────────────────────────────────────────────────────
echo "== E. fresh HOME with nothing in it =="
H2=$(new_sandbox); rmdir "$H2/.claude"
OUT=$(run_install "$H2" --yes); RC=$?
check "installs with no existing ~/.claude (no question asked)" '[ "$RC" = 0 ]' "rc=$RC $OUT"
check "statusLine is the kit's own" 'jq -e --arg p "$H2/.claude/kit-statusline.sh" ".statusLine.command == \$p" "$H2/.claude/settings.json" >/dev/null'
check "CLAUDE.md created with the block" 'grep -qF "@~/.claude-kit/CLAUDE.md" "$H2/.claude/CLAUDE.md"'
OUT=$(run_uninstall "$H2" --yes); RC=$?
check "uninstall leaves an empty settings object and no CLAUDE.md" '[ "$RC" = 0 ] && jq -e ". == {}" "$H2/.claude/settings.json" >/dev/null && [ ! -e "$H2/.claude/CLAUDE.md" ]' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
echo "== F. symlinked CLAUDE.md =="
H3=$(new_sandbox); mkdir -p "$H3/elsewhere"; printf '# shared rules\n' > "$H3/elsewhere/CLAUDE.md"
ln -s "$H3/elsewhere/CLAUDE.md" "$H3/.claude/CLAUDE.md"
OUT=$(run_install "$H3" --yes --statusline=replace); RC=$?
check "symlinked CLAUDE.md -> exit 3" '[ "$RC" = 3 ]' "rc=$RC"
check "prints ASK_USER:claude_md_symlink" 'printf "%s" "$OUT" | grep -q "^ASK_USER:claude_md_symlink: "' "$OUT"
check "link and its target untouched, nothing installed" '[ -L "$H3/.claude/CLAUDE.md" ] && [ "$(cat "$H3/elsewhere/CLAUDE.md")" = "# shared rules" ] && [ ! -e "$H3/.claude/.kit-install.json" ]'
OUT=$(run_install "$H3" --yes --claude-md=replace-link); RC=$?
check "--claude-md=replace-link installs" '[ "$RC" = 0 ] && [ -f "$H3/.claude/CLAUDE.md" ] && [ ! -L "$H3/.claude/CLAUDE.md" ] && grep -qF "@~/.claude-kit/CLAUDE.md" "$H3/.claude/CLAUDE.md"' "$OUT"
check "the link target was never written" '[ "$(cat "$H3/elsewhere/CLAUDE.md")" = "# shared rules" ]'
OUT=$(run_uninstall "$H3" --yes); RC=$?
check "uninstall puts the CLAUDE.md shortcut back" '[ -L "$H3/.claude/CLAUDE.md" ] && [ "$(readlink "$H3/.claude/CLAUDE.md")" = "$H3/elsewhere/CLAUDE.md" ]' "$OUT"
H3b=$(new_sandbox); mkdir -p "$H3b/elsewhere"; printf 'x\n' > "$H3b/elsewhere/CLAUDE.md"; ln -s "$H3b/elsewhere/CLAUDE.md" "$H3b/.claude/CLAUDE.md"
OUT=$(run_install "$H3b" --yes --claude-md=skip); RC=$?
check "--claude-md=skip installs and tells the user the line to add" '[ "$RC" = 0 ] && [ -L "$H3b/.claude/CLAUDE.md" ] && printf "%s" "$OUT" | grep -qF "@~/.claude-kit/CLAUDE.md"' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
echo "== G. symlinked commands folder =="
H4=$(new_sandbox); mkdir -p "$H4/other-repo/commands"; printf 'theirs\n' > "$H4/other-repo/commands/plan.md"
ln -s "$H4/other-repo/commands" "$H4/.claude/commands"
OUT=$(run_install "$H4" --yes); RC=$?
check "symlinked commands dir -> exit 3" '[ "$RC" = 3 ]' "rc=$RC"
check "prints ASK_USER:dirs_symlink" 'printf "%s" "$OUT" | grep -q "^ASK_USER:dirs_symlink: "' "$OUT"
check "other repo untouched" '[ "$(ls "$H4/other-repo/commands")" = "plan.md" ]'
OUT=$(run_install "$H4" --yes --dirs=abort); RC=$?
check "--dirs=abort stops with exit 1 and changes nothing" '[ "$RC" = 1 ] && [ "$(ls "$H4/other-repo/commands")" = "plan.md" ] && [ ! -e "$H4/.claude/.kit-install.json" ]' "rc=$RC"
OUT=$(run_install "$H4" --yes --dirs=write-through); RC=$?
check "--dirs=write-through installs into the linked folder" '[ "$RC" = 0 ] && [ -L "$H4/other-repo/commands/mission.md" -o -f "$H4/other-repo/commands/mission.md" ] && [ -L "$H4/.claude/commands" ]' "$OUT"

# ─────────────────────────────────────────────────────────────────────────────
echo "== H. wrong location is refused =="
H5=$(new_sandbox); mv "$H5/.claude-kit" "$H5/somewhere-else"
OUT=$(HOME="$H5" bash "$H5/somewhere-else/install.sh" --yes 2>&1); RC=$?
check "install from outside ~/.claude-kit exits 1 with a clear message" '[ "$RC" = 1 ] && printf "%s" "$OUT" | grep -q "~/.claude-kit"' "rc=$RC $OUT"

echo ""
echo "e2e-install: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
