# Codex fallback: a Claude reviewer fills the Codex slot

Several skills run review passes through the Codex CLI (`scripts/codex-exec.sh` or a direct
`codex exec`). Codex is optional. When it is missing, every review call site follows this one
procedure so the review still happens.

## 1. When the fallback applies

Any one of these, for a Codex **review** call:

- `command -v codex` fails before you make the call.
- The slot's `$OUT.status` is `unavailable`.
- `$OUT.status` is `nonzero-*` and `$OUT` contains `Not inside a trusted directory`
  (Codex refuses to run outside a git repo).
- `$OUT.status` is `nonzero-*` and `$OUT` says the model was not found, is unsupported, or is
  not available to the account (for example a pinned `CODEX_MODEL` your Codex login cannot use).

A `timeout`, or a Codex content refusal, is not covered here. Follow the call site's own rule for those.

## 2. When it does NOT apply

- **The user turned Codex off on purpose** (for example `/ui-audit --codex-off`). Skip the slot
  as the skill already says.
- **Cross-model validation slots.** Where Codex exists to check Claude's own work, a Claude
  stand-in would only be Claude agreeing with itself. The slot stays skipped, and the findings it
  would have checked are tagged `(unverified — no second model)`. These slots are:
  - `/god-review`: "Codex validates Claude"
  - `/codex-review`: Step 6 verify
- **Build calls** (`scripts/codex-build-chunk.sh`). These stay `unavailable`, and /implement and
  /mission hand the chunk to the Claude `implementer` agent.

## 3. Spawn the stand-in

For each slot that needs it, spawn:

```
Agent(subagent_type: "codex-fallback-reviewer",
      prompt: "Prompt file: <the slot's prompt file path>. Working dir: <the slot's workdir>. Follow it.")
```

Use the exact prompt file the Codex call would have read. If a call site passed its prompt
inline rather than as a file, write it to a temp file first. Independent slots (for example
the parallel review lanes) are spawned **together in one message** so they run concurrently.

## 4. Record the result like a Codex pass

Write the agent's returned text to the slot's `$OUT` with the **Write tool** (never through a
shell `echo`/`printf`: the text is untrusted and may contain shell metacharacters). Then:

```bash
printf 'ok\n'     > "$OUT.status"
printf 'claude\n' > "$OUT.engine"
```

From here the call site reads `$OUT` and `$OUT.status` exactly as it would for Codex, so
pass counts (for example `Codex-passes: N/4`) include fallback passes.

The `$OUT.engine` sidecar is the label of record. Never prepend text to machine-readable output:
the agent adds its `[engine: claude-fallback]` header line only when the prompt asked for free
text, and emits JSON (or any other parsed format) bare, so gates like `jq -e 'type=="array"'`
still pass.

## 5. Label it

Wherever the report names the lane or engine, add `(claude-fallback)`. Example:
`Codex executability (claude-fallback)`.

## 6. Tell the user once per run

> Codex isn't installed, so a Claude reviewer filled the Codex slots. Reviews still run, but
> you lose the second-model cross-check. Install Codex for the full effect: see the kit README.
