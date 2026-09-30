#!/bin/bash
# codex-exec.sh — the ONE shared wrapper for diff-as-text / prompt-file Codex passes.
#
# WHY A SEPARATE WRAPPER (deliberate — do not consolidate): the
# commands/god-review/lib/codex-invoke.sh and commands/ui-audit/lib/codex-invoke.sh wrappers each
# set their own effort on the argv and write "[unavailable]" INLINE into the output file — contracts
# those subsystems rely on. THIS wrapper has a different contract: effort comes from the CALLER when
# it sets one, else from `~/.codex/config.toml`; the wrapper never hardcodes a value. (State the
# MECHANISM, never the value: a comment that names a value set in ANOTHER file drifts.) It also
# writes a SEPARATE machine-readable `.status` sidecar (the output file stays pure model output),
# and uses a portable process-group timeout.
#
# When Codex is not installed (or refuses the directory / model), callers follow
# ~/.claude-kit/docs/codex-fallback.md: a Claude subagent fills the review slot instead.
#
# Usage: codex-exec.sh <promptfile> <outfile> [workdir]
#   stdin is ALWAYS the prompt file (`- < promptfile`) — bare-stdin codex exec hangs (proven).
#   Env: CODEX_EFFORT   optional; low|medium are RAISED to xhigh; high|xhigh|max pass through;
#                       unset = NO override (config `model_reasoning_effort` is authoritative).
#        CODEX_MODEL    optional; passes -m <model> (e.g. gpt-6-luna for cheap, simple research).
#                       unset = NO override (the CLI default model stays authoritative - never pin here).
#        CODEX_TIMEOUT_SECS  default 1800 (max-effort passes have taken 5-25 min).
#        CODEX_OUTPUT_SCHEMA optional path to a JSON Schema file; passes --output-schema so the
#                            final message is structured JSON (callers that parse output should
#                            use this rather than regexing prose).
#        CODEX_LAST_MESSAGE  optional path; passes -o so ONLY the final agent message is written
#                            there (<outfile> still gets the full stdout+stderr transcript).
#
# Writes (atomic .tmp -> mv):
#   <outfile>          full codex stdout+stderr
#   <outfile>.status   invocation outcome ONLY: ok | timeout | unavailable | nonzero-<rc>
#                      (.status says "the process ran"; it does NOT judge review quality.
#                       The USABILITY verdict — `.usable` — is owned EXCLUSIVELY by
#                       codex-review.md Step 3c, which combines .status=ok with its
#                       verdict-regex. Single owner per artifact; do not write .usable here.)
# Exit code mirrors the codex process (124 timeout, 127 missing binary), but callers should
# read .status — this wrapper never masks the outcome.

set -u
PROMPT="${1:?usage: codex-exec.sh <promptfile> <outfile> [workdir]}"
OUT="${2:?usage: codex-exec.sh <promptfile> <outfile> [workdir]}"
WORKDIR="${3:-$(pwd)}"

. "$HOME/.claude-kit/scripts/lib/portable-timeout.sh"

_status() {  # _status <token> — atomic sidecar write
  printf '%s\n' "$1" > "$OUT.status.tmp" && mv -f "$OUT.status.tmp" "$OUT.status"
}

[ -f "$PROMPT" ] || { echo "codex-exec: prompt file not found: $PROMPT" >&2; _status unavailable; exit 127; }
command -v codex >/dev/null 2>&1 || { echo "codex-exec: codex CLI not on PATH" >&2; _status unavailable; exit 127; }

# MODEL: the model comes from your ~/.codex/config.toml unless CODEX_MODEL is set. This wrapper
# does not second-guess the config and prints no drift warnings.

# ONE effort contract: the CALLER sets its lane's effort; unset = the config value is used as-is.
# Review lanes pass CODEX_EFFORT explicitly (codex-review.md, mission.md, plan.md, prepare-pr.md).
EFFORT_ARGS=()
if [ -n "${CODEX_EFFORT:-}" ]; then
  case "$CODEX_EFFORT" in
    low|medium) EFFORT_ARGS=(-c "model_reasoning_effort=xhigh") ;;   # raised — never run a review lens below xhigh
    high|xhigh|max) EFFORT_ARGS=(-c "model_reasoning_effort=$CODEX_EFFORT") ;;
    *) echo "codex-exec: ignoring unknown CODEX_EFFORT='$CODEX_EFFORT' (config stays authoritative)" >&2 ;;
  esac
fi

WRAPPER_NAME=codex-exec

# Optional structured-output pass-through. Both are OFF unless the caller sets them, so every
# existing caller is byte-for-byte unaffected. A declared-but-missing schema file is a caller bug
# and fails BEFORE spending a model call.
EXTRA_ARGS=()
if [ -n "${CODEX_OUTPUT_SCHEMA:-}" ]; then
  [ -f "$CODEX_OUTPUT_SCHEMA" ] || { echo "$WRAPPER_NAME: output schema not found: $CODEX_OUTPUT_SCHEMA" >&2; _status unavailable; exit 127; }
  EXTRA_ARGS+=(--output-schema "$CODEX_OUTPUT_SCHEMA")
fi
if [ -n "${CODEX_LAST_MESSAGE:-}" ]; then
  EXTRA_ARGS+=(-o "$CODEX_LAST_MESSAGE")
fi

MODEL_ARGS=()
if [ -n "${CODEX_MODEL:-}" ]; then
  case "$CODEX_MODEL" in
    *[!A-Za-z0-9._-]*) echo "codex-exec: ignoring invalid CODEX_MODEL='$CODEX_MODEL'" >&2 ;;
    *) MODEL_ARGS=(-m "$CODEX_MODEL") ;;
  esac
fi
TIMEOUT="${CODEX_TIMEOUT_SECS:-1800}"
# ${arr[@]+...} guard: macOS ships bash 3.2, where an EMPTY array under `set -u` is an
# "unbound variable" error (caught live by the 6a timeout fixture).
pt_run "$TIMEOUT" codex exec ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} ${EFFORT_ARGS[@]+"${EFFORT_ARGS[@]}"} ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} -s read-only --ephemeral -C "$WORKDIR" - < "$PROMPT" > "$OUT.tmp" 2>&1
rc=$?
mv -f "$OUT.tmp" "$OUT"

case "$rc" in
  0)   _status ok ;;
  124) _status timeout ;;
  127) _status unavailable ;;
  *)   _status "nonzero-$rc" ;;
esac
exit "$rc"
