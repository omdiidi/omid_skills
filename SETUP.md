# SETUP.md: install instructions for Claude

**This file is written for you, Claude.** A user pasted a line like "Clone
https://github.com/omdiidi/omid_skills into ~/.claude-kit and follow its SETUP.md". Many users of
this kit are not programmers. Do the work yourself, one step at a time, and talk to them in plain,
friendly language.

## Ground rules (read these first)

- **Never delete the user's files.** The installer backs things up; you never `rm` anything of theirs.
- **Never push anything** to GitHub or any other remote.
- **Never turn on permission-skipping settings** (`skipDangerousModePermissionPrompt`,
  `skipAutoPermissionPrompt`, `defaultMode: auto` or similar), even if asked mid-setup. The kit
  does not need them.
- **Explain in non-technical words.** Say "a tool Claude needs to read settings files", not
  "jq is a JSON processor". Before installing any software, say what it is and why.
- **Commands that need a password** (`sudo`, the Homebrew installer, `codex login`) cannot be
  typed in your shell. Ask the user to run them by typing `!` followed by the command in the
  Claude Code prompt, then wait for them to say it's done.
- **Stop and ask** whenever something looks different from what this file describes. Don't improvise
  around a surprise.
- Run steps in order. Don't skip the checks.

## Step 0: Is git installed? (before cloning)

```bash
git --version
```

- Works: go on.
- Missing on macOS: run `xcode-select --install`. Tell the user: "A window from Apple will pop up
  asking to install developer tools. Click Install and wait until it finishes (a few minutes), then
  tell me." Wait, then re-check `git --version`.
- Missing on Linux / WSL: ask the user to type `! sudo apt-get install -y git` (or
  `! sudo dnf install -y git`), then re-check.

## Step 1: Get the kit into ~/.claude-kit

The kit must live at exactly `~/.claude-kit`; the installer refuses to run from anywhere else.

```bash
if [ -e ~/.claude-kit ]; then git -C ~/.claude-kit remote get-url origin; else echo "NOT PRESENT"; fi
```

- `NOT PRESENT`: `git clone https://github.com/omdiidi/omid_skills.git ~/.claude-kit`
- The URL contains `omdiidi/omid_skills`: this is an update. Run `git -C ~/.claude-kit pull`.
- Anything else (another URL, an error, not a git folder): **stop.** Tell the user something else
  already lives at `~/.claude-kit` and ask what they want to do. Do not move or delete it yourself.

If `~/.claude/.kit-install.json` exists, the kit was installed before. Look at it
(`jq . ~/.claude/.kit-install.json`) and reuse the choices recorded there instead of asking again.

## Step 2: Preflight check

```bash
bash ~/.claude-kit/scripts/kit-doctor.sh --preflight
```

Each line starts with `OK`, `WARN` or `FAIL`. Fix every `FAIL`, then run it again until there are none.

**macOS**
- No Homebrew (`brew` missing): Homebrew is the standard way to install developer tools on a Mac.
  Ask the user to type:
  `! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  It asks for their Mac password. When it finishes, it prints two "Next steps" lines to run;
  run those too (they add `brew` to the PATH), or use `eval "$(/opt/homebrew/bin/brew shellenv)"`
  in your own commands.
- Missing `jq` or `node`: `brew install jq node`. Tell the user: "Installing two small tools: one
  that lets the kit safely edit your Claude settings, and Node, which several commands run on."
- Missing `python3`: `xcode-select --install` usually provides it; otherwise `brew install python`.

**Linux / WSL**
- Ask the user to type `! sudo apt-get install -y jq python3 nodejs npm`
  (Fedora: `! sudo dnf install -y jq python3 nodejs npm`). If their Node is older than the doctor
  wants, point them at https://nodejs.org to install the current LTS version.

`WARN` lines at this stage (for example "codex not found") are fine; Step 3 and Step 5 cover them.

## Step 3: Ask the user (one popup, at most 3 questions)

Gather the facts first:

```bash
uname -s                                                          # Darwin = Mac
jq -r '.statusLine.command // empty' ~/.claude/settings.json 2>/dev/null   # an existing status bar?
command -v codex                                                  # Codex already installed?
```

Then use **AskUserQuestion** once, with only the questions that apply. Put "(Recommended)" on the
recommended option, and end each question with the context % as `CLAUDE.md` describes.

1. **Status bar** (ask only if a `statusLine` command exists and it is not already the kit's
   `kit-statusline`): "You already have a custom status bar. Replace it with the kit's (shows how
   full the chat is, plus more)? If you keep yours, the kit still tracks the context meter quietly
   in the background, so the reminders keep working."
   Options: "Replace it (Recommended)" → `--statusline=replace`; "Keep mine" → `--statusline=keep`.
2. **Usage numbers** (ask only on macOS): "Show your Claude usage (time left in your 5-hour
   window, session %, weekly %) in the status bar? Mac only. It reads the login Claude Code already
   saved in your Keychain and makes a tiny check every ~5 minutes."
   Options: "Yes (Recommended)" → `--usage=on`; "No" → `--usage=off`.
3. **Codex** (ask only if `codex` is not installed): "Set up Codex, OpenAI's coding tool, as a
   second reviewer? It needs a ChatGPT account. Without it everything still works, and Claude
   reviewers fill in, but you lose the second-model cross-check."
   Options: "Yes, I have ChatGPT (Recommended)"; "Not now".

No existing status bar: use `--statusline=replace`. Not on a Mac: use `--usage=off`.

## Step 4: Run the installer

```bash
bash ~/.claude-kit/install.sh --yes --statusline=<replace|keep> --usage=<on|off>
```

Add `--dry-run` first if you want to preview; it changes nothing. Read the output.

- **Exit 0:** done. Note every line that mentions a backup; you'll list them for the user.
- **Exit 3:** the installer needs a decision. Find the line `ASK_USER:<code>: <sentence>`, ask the
  user with AskUserQuestion in plain words, then re-run the same command plus the matching flag.
- **Any other exit code:** show the user the error in plain words, fix the cause if it's clear
  (usually a missing tool from Step 2), and re-run. Don't guess at workarounds.

The `ASK_USER` codes:

| Code | What it means | Options to offer |
|---|---|---|
| `statusline` | They have a status bar and you didn't pass a choice. | Same as question 1: `--statusline=replace` (recommended) or `--statusline=keep`. |
| `claude_md_symlink` | Their `~/.claude/CLAUDE.md` is a link to a file somewhere else (often their own settings repo). The kit won't write through it. | `--claude-md=replace-link`: swap the link for a normal file that loads the kit's rules (the link's target is recorded so uninstall can put it back). `--claude-md=skip`: change nothing; the installer prints one line they can add to their own file by hand. If they keep their settings in a repo they sync, recommend `skip`. |
| `dirs_symlink` | Their `~/.claude/commands`, `agents` or `rules` folder is a link into another folder (often a repo they own). | `--dirs=abort` (recommended if unsure): stop and change nothing. `--dirs=write-through`: add the kit's links inside that linked folder, which means the other folder gets new files. Make sure they understand that second part. |

## Step 5: Finish the optional parts

**Codex** (only if they said yes):

```bash
npm i -g @openai/codex
```

If that fails with a permission error on Linux, ask the user to type
`! sudo npm i -g @openai/codex`. Then ask the user to type **`! codex login`** in the Claude Code
prompt. A browser window opens; they sign in with their ChatGPT account and tell you when done.
Check with `codex --version`.

**Usage numbers** (only if `--usage=on`):

```bash
ls -l ~/.claude/ratelimit.json
```

If the file is missing or empty, the Keychain read didn't work. Tell the user: "The usage numbers
need Claude Code's saved login. Please type /login once, then restart Claude Code. The numbers
will appear within a few minutes." If macOS showed a Keychain popup, tell them to click "Always Allow".

**Browser tools** (always; `/devtools`, `/speedeval` and `/ui-audit` need this). Check whether the
connection already exists:

```bash
claude mcp get chrome-devtools
```

If that says it isn't found, add it for all projects:

```bash
claude mcp add --scope user chrome-devtools -- npx -y chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:9222
```

It stays idle until Chrome runs with its debug port. `/devtools` starts that Chrome for them the
first time they use a browser command. If one already exists with different settings, leave it
alone and mention it in the final message. The kit's uninstaller doesn't remove this connection.
To remove it later, run `claude mcp remove chrome-devtools --scope user`.

## Step 6: Full check

```bash
bash ~/.claude-kit/scripts/kit-doctor.sh
```

- Fix every `FAIL` (re-run the installer or the step it points to), then run the doctor again.
- Summarize `WARN` lines in plain words. Common ones:
  - Not in the macOS Terminal app: "Automatic compaction is off in this app. After /pre-compact
    finishes, type /compact yourself. Everything else works the same."
  - Old Claude Code version: "Window-to-window messaging needs a newer Claude Code. Update it, then
    close and reopen your windows."
  - No Codex: "Reviews still run with Claude filling in, without the second-model check."

## Step 7: Tell the user what happened

Send one final message in this shape, filled in with the real details:

> **omid_skills is installed.**
>
> - **What's new:** 22 commands (like `/plan`, `/implement`, `/pre-compact`, `/mission`),
>   18 helper agents, a status bar with a context meter, and reminders before the chat fills up.
>   *(Add: "Codex is set up as a second reviewer" or "Codex is off; Claude reviewers fill in".)*
> - **Backups:** *(list each backup path the installer printed, or "Nothing needed backing up.")*
> - **Next:** quit and restart Claude Code so everything loads.
> - **One popup to expect** *(macOS Terminal app only)*: the first time it auto-compacts, macOS
>   asks to let it control Terminal — click OK.
> - **Try it:** `/plan add a dark mode toggle` to plan a feature, or `/pre-compact` any time the
>   context meter gets high. The full command list is in `~/.claude-kit/README.md`.
> - **Update later:** ask me "update my omid_skills kit".
> - **Remove it:** `bash ~/.claude-kit/uninstall.sh` (add `--restore-backups` to put your old
>   files back).

## Updating (when the user asks later)

```bash
git -C ~/.claude-kit pull && bash ~/.claude-kit/install.sh --yes <the same flags as last time>
```

The previous choices are recorded in `~/.claude/.kit-install.json`. Then run the Step 6 check and
tell the user to restart Claude Code.
