# /devtools — changelog

## Sonnet via an agent definition; effort enforced

Step 4 spawns `subagent_type: "devtools-worker"` (`agents/devtools-worker.md`: Sonnet, **high**
effort from the definition). No per-call `model`, no prompt-body effort hint. Posture: Sonnet
always, no Opus escalation, stuck = an "inconclusive" report handed back to the user.

**Why:** the `Agent` tool's per-call `model` accepts only aliases and has no effort parameter, so
a prompt-body effort line is a hint the model can ignore. An agent definition's `effort:` is
enforced. New definitions load at session start: restart open windows before relying on them.

## Stop stealing the user's screen

A `PreToolUse` hook (`scripts/hooks/devtools-no-focus-steal.py`) forces
`select_page {bringToFront:false}` and `new_page {background:true}`. Step 1 (launch) and
Step 1.5 (wake tabs) record the user's front app and hand focus back to it afterward.

**Why:** the MCP's click/type never raise the window (it emulates focus per page); the cause of
focus theft was agents passing `bringToFront:true` or opening foreground tabs.

## Wake discarded/frozen tabs before connecting (Step 1.5)

**Problem:** tool calls hung forever even though Chrome was up on 9222 and `initialize`
succeeded. chrome-devtools-mcp probes every page target in one `Promise.all` with no timeout, so a
single discarded/frozen background tab hangs the whole enumeration.

**Fix:** Step 1.5 activates every page target (`/json/activate/<id>`) before the `/mcp`
reconnect, with an optional responsiveness check and a fallback to close a crashed tab. Tabs are
preserved.

## Connect to the user's real profile + tabs (port 9222)

**Problem:** the MCP hung on first call and never reached the user's real tabs. Causes:
`--autoConnect` targets the default profile, which Chrome 136+ refuses to debug; a copied profile
can land on the "Who's using Chrome?" picker; stale MCP procs / a corrupt npx cache wedge the
server.

**Fix:** one-time setup migrates the real profile into a non-default `~/.chrome-debug-profile`;
the MCP config uses `--browserUrl http://127.0.0.1:9222`; `/devtools` self-heals by launching
the debug Chrome with `--profile-directory=Default --restore-last-session`, killing stale MCP
procs, and scrubbing the npx cache. The user does the `/mcp` reconnect.
