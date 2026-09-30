<div align="center">

# omid_skills

**We solve the current constraints of context windows, long-running sessions, misalignment, and squeezing performance out of frontier models at a feasible cost.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/omdiidi/omid_skills?style=social)](https://github.com/omdiidi/omid_skills/stargazers)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-d97757)](https://code.claude.com/docs/en/overview)

⭐ **If this helps you, please star the repo - it genuinely helps.**

</div>

---

This is a setup kit for **[Claude Code](https://code.claude.com/docs/en/overview)**.

A multi-model web of commands, built to be driven dynamically by an agent - the answer to vibe
coding. **This is agentic engineering.**

This is a web of specialized commands that agents call as they work. Each command can trigger
multiple specialist subagents for research, planning, implementation, testing, or review. Work
flows through a chain of experts instead of a single model. And with a system built to preserve
context, decisions, and progress across compactions (tested up to 38 hours non-stop), builds can
run for hours without losing track of their mission.

Use each model for what it does best. No single model carries the full workload - both are used
to squeeze max value out of artificial intelligence, as some models are trained for specific
things. The result is higher quality, more scalable, and much closer to what real software
engineering with AI should look like.

## Quick start

Paste this into your Claude Code chat:

```
Clone https://github.com/omdiidi/omid_skills into ~/.claude-kit and follow its SETUP.md
```

## What you get

**Long sessions that don't fall apart.** Every AI chat has a memory limit (its "context"). When
it fills up, Claude Code squeezes the conversation down ("compacts" it) and details get lost.
The agent isn't aware of its own context window. This clearly solves that: it makes sure the
agent is aware of, and aligned with, its own state realistically. The cliff becomes a smooth
handover:

1. **A context meter** sits in your status bar, so you and the agent always see how full the chat is.
2. **Gentle nudges** arrive at 50%, 65% and 75%: first a heads-up, then "finish this task", then
   "save now". Agents are more aware.
3. **`/pre-compact`** writes a detailed handoff note: what you're doing, what you decided, what
   you tried, what's left.
4. **Claude compacts automatically** if you're using Claude in the Terminal on a Mac.
5. **It picks up exactly where it left off.** It auto-compacts and auto-continues, picking up on
   its own. Not native, fully custom.

**`/mission`** rides on top of that loop for really big builds. You agree on a roadmap once, and
it plans, builds and reviews each part on its own, across as many compactions as it takes. Opt-in
and heavy; overkill for small work, unbeatable for big ones.

### The reviewers working between each step

```
/plan ─▶ plan-reviewer + criticer (+ Codex) ─▶ /implement ─▶ parallelizer ─▶ implementer(s)
      ─▶ implementation-reviewer + criticer ─▶ /codex-review ─▶ fixes ─▶ done
```

Every step writes its results to files on disk, and the next step reads them. The plan, the
decisions and the progress live **outside the model**, so nothing is lost when a chat compacts and
nothing depends on copy-paste. Every stage checks itself before handing off.

## Commands

Type these in Claude Code. Full details and example prompts: [docs/COMMANDS.md](docs/COMMANDS.md).

**Plan & build**

| Command | What it does | Use it when |
|---|---|---|
| `/discussion` | Talks an idea through with you and saves a short brief. Writes no code. | You're not sure what you want yet. |
| `/plan` | Researches your code and the web, writes a plan, and has reviewers check it. | You're starting a real feature. |
| `/simple-plan` | A quick look, a short plan, then it builds after you say yes. | The change is small and clear. |
| `/implement` | Builds an approved plan with parallel helpers, then reviews the result. | You have a plan you like. |
| `/mission` | Runs plan, build and review for each part of a big roadmap, for hours. | The build is genuinely large. |
| `/investigate` | Finds the real cause of a bug by testing guesses one at a time. | Something is broken. |
| `/script` | Writes tests that prove a plan's risky assumptions before you build. | Mistakes would be expensive. |
| `/testplan` | Writes a thorough test plan for any app or feature. It doesn't run it. | You want to know what to test. |

**Review**

| Command | What it does | Use it when |
|---|---|---|
| `/codex-review` | A report from several focused reviewers (Codex + Claude). Changes nothing. | You want a second opinion on a change. |
| `/god-report` | A whole-codebase review by a large team of reviewers. Report only. | You want the truth about a codebase. |
| `/god-review` | The same team, but it fixes things and re-checks until it's clean. | You want to set it loose and come back to a cleaner codebase. |

**Long sessions**

| Command | What it does | Use it when |
|---|---|---|
| `/pre-compact` | Saves a detailed handoff note, then compacts. | The context meter is getting high. |
| `/post-compact-resume` | Reloads the handoff note after a compaction. Usually runs itself. | The resume didn't start on its own. |
| `/checkpoint` | Saves a named snapshot of your code (a git tag). | You're about to try something risky. |

**Browser & UI** (need Google Chrome)

| Command | What it does | Use it when |
|---|---|---|
| `/devtools` | Connects Claude to your real Chrome so it can see and click your app. | Browser tools hang or won't connect. |
| `/ui-audit` | Checks every button and panel on a page to find ones that don't really work. | A screen looks done but you doubt it. |
| `/speedeval` | Clicks through your running app and times everything. | The app feels slow. |

**Utilities**

| Command | What it does | Use it when |
|---|---|---|
| `/document` | Writes or refreshes your project's docs. | The docs are missing or stale. |
| `/research-web` | Deep web research with sources. | You need outside facts or comparisons. |
| `/commit` | Commits only this session's changes. | You want a clean commit. |
| `/prepare-pr` | Commits, rebases, builds, reviews, and opens a pull request. | You're ready to share the work. |
| `/line` | Names this window so other windows can message it. | You run several Claude windows at once. |

It also installs 18 helper agents (the reviewers, the builder, the critic and friends) and three
short rule files. See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for how they fit together.

## FAQ

<details>
<summary><b>Do I need Codex?</b></summary>

Recommended, not required. Codex is OpenAI's coding tool and needs a ChatGPT account. With it,
two different AI models check each other's work, which is the whole point of the review steps.

Without it, everything still runs: a Claude reviewer fills each Codex slot. But be honest with
yourself about the trade: you lose the second-model cross-check. Steps whose only job is to have
the *other* model verify Claude's work are skipped and their findings are labeled
"unverified". Setup can install Codex for you. Details: [docs/codex-fallback.md](docs/codex-fallback.md).
</details>

<details>
<summary><b>Mac vs Windows / Linux?</b></summary>

Everything important works everywhere: the commands, the reviewers, the context meter, the
nudges, `/pre-compact` and the resume. Mac-only: automatic compaction (elsewhere you type
`/compact` yourself) and the usage numbers in the status bar. On Windows, use WSL.
</details>

<details>
<summary><b>I use VS Code / Cursor / iTerm / Ghostty. Does it work?</b></summary>

Yes. The one difference: automatic compaction only works in the macOS Terminal app. Everywhere
else, after `/pre-compact` finishes, type `/compact` yourself. The handoff note and the resume
work the same.
</details>

<details>
<summary><b>macOS asked to let something control Terminal. Is that expected?</b></summary>

Yes. The first time it auto-compacts, macOS asks to let it control Terminal - click OK. If you
clicked Don't Allow: System Settings → Privacy & Security → Automation → allow it.
</details>

<details>
<summary><b>What does setup change on my computer?</b></summary>

- It puts the kit in `~/.claude-kit` and adds links to it inside `~/.claude` (your Claude Code
  settings folder).
- It **merges** its settings into your `settings.json`, after saving a backup copy first. Your
  own settings stay.
- It adds one clearly marked line to your `~/.claude/CLAUDE.md` that loads the kit's rules.
- If a file with the same name already exists, it is renamed to a backup, never deleted.
- It never turns on any "skip permission prompts" setting.
- It pre-approves only its own helper scripts in `~/.claude-kit/scripts` (so `/pre-compact`,
  `/mission` and friends don't ask every time); uninstall removes those approvals.
</details>

<details>
<summary><b>What are the usage numbers?</b></summary>

Optional and Mac only. The status bar can show the time left in your 5-hour window and your
session and weekly usage. To get them it reads the login Claude Code already saved in your Mac's
Keychain and makes a tiny check about every 5 minutes. Setup asks before turning it on.
</details>

<details>
<summary><b>Can my Claude windows talk to each other?</b></summary>

Yes. Name a window with `/line billing dashboard` and other windows can message it by that name.
Setup turns on Claude Code's `crossSessionInbound` setting so windows can receive messages.
Messages from other windows are treated as untrusted information, never as instructions or as
your approval.
</details>

<details>
<summary><b>How do I update?</b></summary>

Ask Claude "update my omid_skills kit", or run:

```bash
git -C ~/.claude-kit pull && bash ~/.claude-kit/install.sh --yes
```

(Add the same options you chose the first time. Claude handles that for you.)
</details>

<details>
<summary><b>How do I uninstall?</b></summary>

```bash
bash ~/.claude-kit/uninstall.sh                     # remove the kit's links, hooks and CLAUDE.md line
bash ~/.claude-kit/uninstall.sh --restore-backups   # also put your backed-up files back
```
</details>

<details>
<summary><b>Does it cost extra?</b></summary>

The kit is free. Codex runs on your ChatGPT plan. The heavy commands, especially `/god-review`
and `/mission`, run many reviewers at once and use a lot of your Claude usage. Without Codex,
the Claude stand-in reviewers also count against your Claude usage. Start with `/plan` and
`/implement` and reach for the big ones when the job deserves it.
</details>

---

Built by [omdiidi](https://github.com/omdiidi). Released under the [MIT License](LICENSE).
