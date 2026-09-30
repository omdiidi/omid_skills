#!/usr/bin/env bash
# e2e-precompact-chain.sh - the long-session loop, end to end, in a throwaway HOME + git repo:
#   (1) context at 80%  -> the prompt-submit gate forces /pre-compact
#   (2) a /pre-compact handoff (full-SID CLAUDE.local.<SID>.md + Step-6D END-OF-HANDOFF marker
#       with a nonce, verified with the same writer_verify_marker_sid helper /pre-compact uses),
#       then arm-auto-compact.sh -> "armed" or one of its documented NOT-armed reasons
#   (3) SessionStart {"source":"compact"} -> the primer names the handoff and /post-compact-resume
#   (4) post-compact-resume-step2.sh resolves the SAME file
#   (5) mission bridge: mission-write.sh create + log, read back
# Fixture shapes follow scripts/hooks/test-ctx-gate.sh (G4 / 3l) and test-auto-compact.sh (R8-D7).
# Never touches the real ~/.claude.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
HOOKS="$REPO/scripts/hooks"
PASS=0 FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s%s\n' "$1" "${2:+ - $2}"; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kit-chain.XXXXXX"); SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"
ln -s "$REPO" "$HOME/.claude-kit"
mkdir -p "$HOME/.claude/progress" "$HOME/.claude/logs"; chmod 700 "$HOME/.claude/progress"
PROJ="$SANDBOX/project"; mkdir -p "$PROJ"
git -C "$PROJ" init -q 2>/dev/null || git init -q "$PROJ"

# Kit hooks registered in the sandbox settings (arm-auto-compact checks the Stop hook is wired).
jq --arg kit "$HOME/.claude-kit" --arg home "$HOME" '
  def r: if type == "object" then map_values(r) elif type == "array" then map(r)
         elif type == "string" then gsub("__KIT__"; $kit) | gsub("__HOME__"; $home) else . end;
  r' "$REPO/settings/kit-settings.json" > "$HOME/.claude/settings.json"

SID="$(uuidgen 2>/dev/null | tr 'A-F' 'a-f')"
[ -n "$SID" ] || SID="c0ffee00-1234-4abc-8def-$(date +%s)00"
NONCE="$(uuidgen 2>/dev/null | tr 'A-F' 'a-f')"; NONCE=${NONCE:-chain-nonce-$$}
export CLAUDE_SESSION_ID="$SID" CLAUDE_CODE_SESSION_ID="$SID"

# ── (1) ctx 80% forces /pre-compact ────────────────────────────────────────
echo "== (1) context gate at 80% =="
printf '80\n' > "$HOME/.claude/progress/ctx-$SID.txt"
OUT=$("$HOOKS/ctx-gate-on-prompt-submit.sh" <<< "{\"session_id\":\"$SID\",\"prompt\":\"keep going\",\"hook_event_name\":\"UserPromptSubmit\"}" 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | (contains("Skill(pre-compact)") and contains("FIRST action"))' >/dev/null 2>&1; then
  pass "ctx=80 -> the gate makes /pre-compact the first action"
else
  fail "ctx=80 should force /pre-compact" "got: ${OUT:0:300}"
fi

# ── (2) handoff + arm ─────────────────────────────────────────────────────
echo "== (2) handoff written + auto-compact armed =="
HANDOFF="$PROJ/CLAUDE.local.$SID.md"
{
  printf '# Handoff\n\n## Objective\nChain test objective.\n\n## Next step\nContinue the chain test.\n\n'
  printf '<!-- END-OF-HANDOFF schema=v1 sid=%s nonce=%s -->\n' "$SID" "$NONCE"
} > "$HANDOFF"
if ( . "$HOOKS/lib/writer-verify.sh" && writer_verify_marker_sid "$HANDOFF" "$SID" ) 2>/dev/null; then
  pass "handoff marker verified by writer_verify_marker_sid (the /pre-compact Step 6D check)"
else
  fail "writer_verify_marker_sid rejected the fixture handoff"
fi
ARM=$(cd "$PROJ" && bash "$HOOKS/arm-auto-compact.sh" "" 2>/dev/null | head -1)
case "$ARM" in
  "armed "*)
    if [ -f "$HOME/.claude/progress/auto-compact-$SID.json" ]; then pass "arm-auto-compact: armed (sentinel written in the sandbox)"
    else fail "arm-auto-compact said armed but no sentinel" "$ARM"; fi ;;
  "NOT armed — auto-compact requires macOS Terminal.app"|"NOT armed — running inside tmux/screen"*|"NOT armed — host is "*|\
  "NOT armed — could not resolve controlling tty"*|"NOT armed — could not resolve session id"*)
    pass "arm-auto-compact: documented not-armed reason here -> '$ARM' (type /compact yourself in this host)" ;;
  *) fail "arm-auto-compact gave an unexpected answer" "'$ARM'" ;;
esac

# ── (3) primer after compact ──────────────────────────────────────────────
echo "== (3) SessionStart primer after compaction =="
PRIMER=$("$HOOKS/post-compact-primer.sh" <<< "{\"session_id\":\"$SID\",\"source\":\"compact\",\"cwd\":\"$PROJ\",\"hook_event_name\":\"SessionStart\"}" 2>/dev/null)
CTX=$(printf '%s' "$PRIMER" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX" | grep -qF "CLAUDE.local.$SID.md" && printf '%s' "$CTX" | grep -qF "/post-compact-resume $SID"; then
  pass "primer names the handoff file and tells Claude to run /post-compact-resume $SID"
else
  fail "primer output missing the handoff path or /post-compact-resume" "${CTX:0:300}"
fi
if [ ! -f "$HOME/.claude/progress/auto-compact-$SID.json" ]; then
  pass "no armed sentinel left after a confirmed compaction"
else
  fail "armed sentinel survived source=compact"
fi

# ── (4) step2 resolves the same file ──────────────────────────────────────
echo "== (4) /post-compact-resume step 2 =="
S2=$(cd "$PROJ" && bash "$HOOKS/post-compact-resume-step2.sh" "$SID" 2>/dev/null)
STATE_JSON=$(printf '%s' "$S2" | sed -n 's/^STATE=//p' | head -1)
STATE=$(printf '%s' "$STATE_JSON" | jq -r '.state' 2>/dev/null)
S2PATH=$(printf '%s' "$STATE_JSON" | jq -r '.path' 2>/dev/null)
REAL_HANDOFF=$(cd "$(dirname "$HANDOFF")" && pwd -P)/$(basename "$HANDOFF")
REAL_S2=$( [ -n "$S2PATH" ] && [ -f "$S2PATH" ] && echo "$(cd "$(dirname "$S2PATH")" && pwd -P)/$(basename "$S2PATH")" )
if [ "$STATE" = ok ] && [ "$REAL_S2" = "$REAL_HANDOFF" ]; then
  pass "step2 STATE=ok and resolves the same handoff file"
else
  fail "step2 did not resolve the handoff" "state=$STATE path=$S2PATH raw=${S2:0:300}"
fi

# ── (5) mission bridge roundtrip ──────────────────────────────────────────
echo "== (5) mission bridge write/read =="
MW="$HOME/.claude-kit/scripts/hooks/mission-write.sh"
C1=$(bash "$MW" create "$SID" "$PROJ" "chain test plan" 2>/dev/null)
[ "$C1" = "mission-write: create ok" ] && pass "mission-write create ok" || fail "mission-write create" "$C1"
ENTRY="chain-roundtrip-$$-$(date +%s)"
L1=$(bash "$MW" log "$SID" "$PROJ" "$ENTRY" 2>/dev/null)
[ "$L1" = "mission-write: log ok" ] && pass "mission-write log ok" || fail "mission-write log" "$L1"
if grep -qF "$ENTRY" "$PROJ/MISSION.$SID.log" 2>/dev/null; then pass "logged entry reads back from MISSION.<sid>.log"
else fail "logged entry not found in MISSION.$SID.log"; fi
if ( . "$HOOKS/lib/mission-bridge.sh" && mission_verify "$PROJ/MISSION.$SID.md" "$SID" ) >/dev/null 2>&1; then
  pass "mission file verifies (mission_verify)"
else
  fail "mission_verify rejected the created mission file"
fi
rm -f "$HOME/.claude/progress/mission-liveness-$SID.json" 2>/dev/null

echo ""
echo "e2e-precompact-chain: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
