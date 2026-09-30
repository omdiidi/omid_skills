# Commands

Every command you type in Claude Code after installing omid_skills. Each entry says what it does,
gives an example you can paste, and lists anything extra it needs.

Most commands need nothing beyond the setup. Three things come up below:

- **Codex (optional):** OpenAI's coding tool, used as a second reviewer. Without it, a Claude
  reviewer fills the slot and cross-model checks are skipped and labeled "unverified". See
  [codex-fallback.md](codex-fallback.md).
- **Chrome:** Google Chrome running with a debug port (`/devtools` starts it for you).
- **Node:** installed by setup; several commands run small Node scripts.

Artifacts land in your project's `./tmp/` folder: briefs in `./tmp/briefs/`, plans in
`./tmp/ready-plans/`, finished plans in `./tmp/done-plans/`.

---

## Plan & build

### /discussion
Talks an idea through with you. It reads your code as needed, lays out options and trade-offs,
and saves the decisions as a short brief in `./tmp/briefs/`. It never writes code. `/plan` picks up
the brief automatically, so the thinking carries into a fresh start.
- Example: `/discussion should comments be threaded or flat?`
- Needs: nothing extra.

### /plan
Writes a real implementation plan. Research agents read your codebase and the web in parallel,
then a `plan-reviewer` checks the plan for gaps and a `criticer` asks whether it's actually good.
Codex adds its own review passes. It iterates with you until the plan is sound, then saves it to
`./tmp/ready-plans/`.
- Example: `/plan add a dark mode toggle to the settings page`
- Needs: Codex optional.

### /simple-plan
The lightweight version for small, clear requests. It looks around, proposes a short plan, and
builds it once you say yes.
- Example: `/simple-plan make the signup button disabled while it's submitting`
- Needs: nothing extra.

### /implement
Builds an approved plan. A `parallelizer` works out which parts can safely be built at the same
time, `implementer` agents build them, and an `implementation-reviewer` plus a `criticer` check
the result against the plan. A post-batch check stops everything if a helper touched files it
wasn't assigned. The finished plan moves to `./tmp/done-plans/`.
- Example: `/implement` (uses the latest plan) or `/implement tmp/ready-plans/2026-01-15-dark-mode.md`
- Needs: Node. Codex optional (it can build small, fully specified pieces).

### /mission
The conductor for genuinely large builds. You agree on a multi-part roadmap once. Then, for each
part, it runs research, `/plan` with the full reviewer loop, `/implement`, and a code-review panel
(4 Codex passes plus 3 Claude reviewers), and keeps going until each part is honestly done. It
rides `/pre-compact` across as many compactions as it takes. Opt-in and heavy; overkill for small
work, unbeatable for big ones.
- Example: `/mission build a customer portal: login, invoices, and a support inbox`. Later:
  `/mission status`, `/mission resume`, `/mission clear`.
- Needs: Node. Codex strongly recommended (without it, Claude fills the panel slots and the round
  is labeled `(claude-fallback)`). Uses a lot of Claude usage.

### /investigate
Finds the root cause of a bug by forming guesses and testing them one at a time, instead of
patching the symptom.
- Example: `/investigate the dashboard shows yesterday's totals after I refresh`
- Needs: nothing extra.

### /script
Writes tests that prove a plan's risky assumptions against your real setup before you build, then
re-run later to catch regressions. The tests clean up after themselves. For when mistakes are
expensive (real user data, payments, production).
- Example: `/script tmp/ready-plans/2026-01-15-billing-migration.md`
- Needs: access to whatever the plan touches (a test database, an API key).

### /testplan
Writes a thorough, risk-ranked test plan for an app, a page or a feature, scaled to how risky it
is, with honest notes about what it couldn't test. It plans; it doesn't run the tests.
- Example: `/testplan the checkout flow`
- Needs: nothing extra.

---

## Review

### /codex-review
A report from several focused reviewers. Codex runs 4 passes (correctness, security, data
integrity, contracts) plus a verification pass; Claude runs architecture, integration and
adversarial reviewers and a final meta review. It changes nothing. Point it at a change, a file, a
plan, an idea or a bug.
- Example: `/codex-review` (reviews your current changes) or `/codex-review tmp/ready-plans/my-plan.md`
- Needs: Codex recommended. Without it Claude stand-ins run the 4 passes, and the verification
  pass is skipped (its findings are labeled unverified).

### /god-report
A whole-codebase review by a large team: broad reviewers from both models plus 24 principle
reviewers (security, data handling, tests and so on). Pure report; nothing changes. `--rounds N`
repeats it to filter out noise.
- Example: `/god-report` or `/god-report src/api`
- Needs: Codex recommended. Uses a lot of Claude usage.

### /god-review
The same team as `/god-report`, but it fixes what it finds and re-reviews until three rounds in a
row turn up nothing new. Risky changes (database schema, login and permissions, dependencies,
secrets, CI, tests) are held for your approval at the end. Set it loose and come back to a cleaner
codebase.
- Example: `/god-review` or `/god-review --max-wall-hours 4`
- Needs: Codex recommended (without it the "Codex checks Claude's work" step is skipped and
  labeled unverified). Uses a lot of Claude usage.

---

## Long sessions

### /pre-compact
The heart of the kit. Before the chat is compacted, it refreshes your project docs and writes a
detailed handoff note (`CLAUDE.local.<id>.md`): the active task, the plan, key decisions, what was
tried, open issues. Then it compacts. In the macOS Terminal app that happens automatically;
elsewhere, type `/compact` when it tells you to.
- Example: `/pre-compact` or `/pre-compact migrating auth to the new provider`
- Needs: nothing extra.

### /post-compact-resume
Reloads the handoff note after a compaction so Claude picks up exactly where it stopped. It
normally runs by itself. If it didn't, the startup banner shows the exact command to type,
including the session id.
- Example: `/post-compact-resume <session id from the banner>`
- Needs: nothing extra.

### /checkpoint
Saves a named snapshot of your code as a git tag, so you can get back to a known-good state.
- Example: `/checkpoint before-payments-refactor`
- Needs: a git repository.

---

## Browser & UI

### /devtools
Connects Claude to your real Chrome (your profile and open tabs) so it can see, click and debug
your app. It starts a debug copy of your Chrome on port 9222, clears stuck connections, and tells
you when to reconnect. The first run makes a separate copy of your Chrome profile; your original
profile is never touched.
- Example: `/devtools`, then "open localhost:3000 and tell me why the login button does nothing"
- Needs: Google Chrome. Setup registers the Chrome connection for you; if it's missing run:
  `claude mcp add --scope user chrome-devtools -- npx -y chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:9222`

### /ui-audit
Checks every element on one page of your running app and sorts it into: really works, static by
design, fake or dead, or couldn't verify. It combines a code trace, a live browser check and
screenshots, with Codex and Claude splitting the judging. It reports and never edits your code.
- Example: `/ui-audit http://localhost:3000/settings`
- Needs: Chrome on port 9222 (run `/devtools` first), Node. Codex recommended; `--codex-off`
  runs Claude-only on purpose.

### /speedeval
Clicks through your running app and times it: page loads, every button, and whether anything
visibly responds within 100ms. It sorts each slow spot by cause (server, network, rendering and so
on) and writes a report a fixing agent can act on. It never signs in or clicks destructive buttons.
- Example: `/speedeval http://localhost:3000`
- Needs: Chrome on port 9222 (run `/devtools` first), Node.

---

## Utilities

### /document
Audits or creates your project's documentation (database, backend, frontend, APIs, outside
services), readable by both people and AI.
- Example: `/document` or `/document backend only`
- Needs: nothing extra.

### /research-web
Deep web research on a technical question, with sources.
- Example: `/research-web best way to handle file uploads with Next.js and S3`
- Needs: nothing extra.

### /commit
Commits only the changes from this session and leaves unrelated edits alone.
- Example: `/commit` or `/commit fix the signup validation`
- Needs: a git repository.

### /prepare-pr
Commits your work grouped by finished plan, rebases on main, builds the project, runs a Codex
review loop (when Codex is available), and then opens or updates a pull request. It pushes, so it
confirms with you first.
- Example: `/prepare-pr`
- Needs: a git repository with a GitHub remote, the `gh` command. Codex optional.

### /line
Names this Claude window. The name shows in the status bar and becomes the address other windows
use to message this one. Run with no words to clear the caption.
- Example: `/line billing dashboard`
- Needs: Claude Code 2.1.224 or newer for messaging (older windows must be closed and reopened
  after updating). Messages from other windows are treated as untrusted information.

---

## Helper agents

These run inside the commands above; you can also ask for them by name ("have the criticer look
at this plan").

| Agent | Role |
|---|---|
| `plan-reviewer` | Checks a plan for gaps and simpler routes. |
| `criticer` | Asks whether the work is actually good: biggest gap, cheap wins, over-engineering. Advisory only. |
| `parallelizer` | Decides which pieces of work can safely run at the same time. |
| `implementer` | Builds one piece of a plan. |
| `implementation-reviewer` | Checks finished work against its plan. |
| `codebase-explorer` | Finds files and patterns, with exact line references. |
| `researcher` | Web plus codebase research with citations. |
| `research-dossier-writer` | Writes a research dossier for a feature brief. |
| `review-lane-sonnet` | Runs `/codex-review`'s architecture and integration lenses. |
| `review-worker` | Runs the reviewer prompts inside `/god-review` and `/god-report`. |
| `codex-fallback-reviewer` | Fills a Codex review slot when Codex isn't installed. |
| `devtools-worker` | Drives Chrome for `/devtools` tasks and reports back. |
| `lens-*` (6 agents) | Focused diff reviewers: backend and frontend architecture, circular imports, self-contained components, one way to do things, TanStack Query. Call them directly. |
