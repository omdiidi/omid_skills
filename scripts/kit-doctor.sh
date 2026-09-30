#!/usr/bin/env bash
# kit-doctor.sh - health check for the omid_skills kit. Every line starts with OK, WARN or FAIL.
#
#   bash ~/.claude-kit/scripts/kit-doctor.sh --preflight   before installing: tools, bash, OS
#   bash ~/.claude-kit/scripts/kit-doctor.sh               after installing: the full check
#
# Exit 1 if any line is FAIL, else 0. WARN lines are things that still work, just less well.
set -uo pipefail

KIT="$HOME/.claude-kit"
CL="$HOME/.claude"
MANIFEST="$CL/.kit-install.json"
SETTINGS="$CL/settings.json"
NFAIL=0 NWARN=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { NWARN=$((NWARN+1)); printf 'WARN  %s\n' "$*"; }
bad()  { NFAIL=$((NFAIL+1)); printf 'FAIL  %s\n' "$*"; }

# version_ge A B -> 0 when dotted version A >= B
version_ge() {
  local IFS=. i; local -a a b
  read -r -a a <<< "$1"; read -r -a b <<< "$2"
  for i in 0 1 2 3; do
    local x=${a[$i]:-0} y=${b[$i]:-0}
    x=${x//[^0-9]/}; y=${y//[^0-9]/}; x=${x:-0}; y=${y:-0}
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 0
}

preflight() {
  local t hint
  case "$(uname -s)" in
    Darwin) ok "operating system: macOS (everything supported)"; hint="brew install" ;;
    Linux)  warn "operating system: Linux - works, but automatic /compact and the usage numbers are Mac-only"; hint="your package manager (apt/dnf/pacman) to install" ;;
    *)      warn "operating system: $(uname -s) - not tested; Linux or macOS recommended"; hint="your package manager to install" ;;
  esac
  for t in git jq python3 node; do
    if command -v "$t" >/dev/null 2>&1; then ok "$t found"
    else bad "$t is missing - use $hint $t$( [ "$t" = node ] && printf ' (or get it from https://nodejs.org)')"; fi
  done
  if command -v jq >/dev/null 2>&1; then
    local jv; jv=$(jq --version 2>/dev/null | sed 's/^jq-//')
    if version_ge "$jv" 1.6; then ok "jq version $jv"; else bad "jq $jv is too old - the kit needs jq 1.6 or newer"; fi
  fi
  if version_ge "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" 3.2; then ok "bash ${BASH_VERSION}"
  else bad "bash ${BASH_VERSION} is too old (needs 3.2+)"; fi
  command -v perl >/dev/null 2>&1 && ok "perl found (used for timeouts)" || warn "perl is missing - some timeouts will not be enforced"
}

if [ "${1:-}" = "--preflight" ]; then
  echo "omid_skills kit - preflight"
  preflight
  echo ""
  [ "$NFAIL" = 0 ] && echo "Preflight passed ($NWARN warning(s))." || echo "Preflight found $NFAIL problem(s). Fix the FAIL lines, then run it again."
  [ "$NFAIL" = 0 ]; exit $?
fi

echo "omid_skills kit - full check"
preflight

# ── install record + links ───────────────────────────────────────────────
if [ ! -d "$KIT" ]; then bad "the kit folder ~/.claude-kit is missing"; fi
if [ ! -f "$MANIFEST" ]; then
  bad "the kit is not installed (no ~/.claude/.kit-install.json) - run: bash ~/.claude-kit/install.sh"
elif ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  bad "the kit's install record ~/.claude/.kit-install.json is damaged - re-run install.sh"
else
  nl=0; broken=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue; nl=$((nl+1))
    { [ -L "$p" ] && [ -e "$p" ]; } || broken="$broken $p"
  done < <(jq -r '(.links // [])[]' "$MANIFEST")
  if [ -z "$broken" ]; then ok "$nl kit links resolve"
  else bad "broken or missing kit links:$(printf '%s' "$broken" | tr ' ' '\n' | head -5 | tr '\n' ' ')- re-run install.sh"; fi
  missing_r=""
  while IFS= read -r p; do [ -f "$p" ] || missing_r="$missing_r $p"; done < <(jq -r '(.renders // [])[].path' "$MANIFEST")
  if [ -z "$missing_r" ]; then ok "personalized kit files present"
  else bad "missing personalized files:$missing_r - re-run install.sh"; fi
  if grep -rl '__KIT_ABS__' "$CL/commands" "$CL/agents" "$CL/rules" 2>/dev/null | while IFS= read -r f; do [ -L "$f" ] || echo "$f"; done | grep -q .; then
    bad "some installed files still contain the __KIT_ABS__ placeholder - re-run install.sh"
  fi
fi

# ── settings: hooks + statusLine ─────────────────────────────────────────
if [ ! -f "$SETTINGS" ]; then
  bad "~/.claude/settings.json is missing - re-run install.sh"
elif ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  bad "~/.claude/settings.json is not valid JSON - Claude Code will ignore it"
else
  nh=0; hbad=""
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    p=$(printf '%s' "$cmd" | tr ' ' '\n' | grep '\.claude-kit/' | head -1)
    p=${p/#\~/$HOME}; p=${p//\$HOME/$HOME}; p=${p//\$\{HOME\}/$HOME}
    nh=$((nh+1))
    case "$cmd" in
      bash\ *|sh\ *|python3\ *|python\ *|node\ *) [ -r "$p" ] || hbad="$hbad $p(missing)" ;;
      *) [ -x "$p" ] || hbad="$hbad $p(missing-or-not-executable)" ;;
    esac
  done < <(jq -r '[.hooks // {} | .[] | .[] | (.hooks // [])[] | .command // empty] | .[]' "$SETTINGS" | grep '\.claude-kit/')
  if [ "$nh" = 0 ]; then bad "no kit hooks in ~/.claude/settings.json - re-run install.sh"
  elif [ -z "$hbad" ]; then ok "$nh kit hook commands point at files that exist"
  else bad "kit hook commands point at missing files:$hbad"; fi
  slc=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  case "$slc" in
    "") bad "no status bar set - the context % (and the /pre-compact nudges) need it; re-run install.sh" ;;
    *kit-statusline.sh|*kit-statusline-wrap.sh)
      sp=${slc/#\~/$HOME}
      if [ -x "$sp" ]; then ok "status bar: $slc"; else bad "status bar command $slc is missing or not executable"; fi ;;
    *) warn "status bar is '$slc', not the kit's - context % will not be tracked, so the /pre-compact nudges stay silent (re-run install.sh with --statusline=keep to fix)" ;;
  esac
fi

# ── CLAUDE.md import ─────────────────────────────────────────────────────
if [ -f "$CL/CLAUDE.md" ] && grep -qF '@~/.claude-kit/CLAUDE.md' "$CL/CLAUDE.md" 2>/dev/null; then
  if [ -f "$KIT/CLAUDE.md" ]; then ok "~/.claude/CLAUDE.md loads the kit rules"
  else bad "~/.claude/CLAUDE.md imports ~/.claude-kit/CLAUDE.md, but that file is missing - update the kit"; fi
elif [ "$(jq -r '.claude_md_mode // empty' "$MANIFEST" 2>/dev/null)" = skip ]; then
  warn "the kit rules are not loaded - you chose to add this line to ~/.claude/CLAUDE.md yourself: @~/.claude-kit/CLAUDE.md"
else
  bad "~/.claude/CLAUDE.md does not load the kit rules - re-run install.sh"
fi

# ── context-% folder ─────────────────────────────────────────────────────
if mkdir -p "$CL/progress" 2>/dev/null && t=$(mktemp "$CL/progress/.doctor.XXXXXX" 2>/dev/null); then
  rm -f "$t"; ok "context-% folder ~/.claude/progress is writable"
else
  bad "cannot write to ~/.claude/progress - the context % cannot be tracked"
fi

# ── Claude Code version ──────────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  cv=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$cv" ]; then warn "could not read the Claude Code version"
  elif version_ge "$cv" 2.1.224; then ok "Claude Code $cv"
  else warn "Claude Code $cv is older than 2.1.224 - /line messaging between windows needs 2.1.224+ (update Claude Code)"; fi
else
  warn "the 'claude' command was not found on PATH (fine if you only use the desktop/IDE app)"
fi

# ── Codex ────────────────────────────────────────────────────────────────
if command -v codex >/dev/null 2>&1; then ok "codex found - reviews use a second model (Codex)"
else warn "codex not found - reviews will use the Claude fallback (no second-model cross-check). Optional: npm i -g @openai/codex, then codex login"; fi

# ── terminal (automatic /compact) ────────────────────────────────────────
tp=${TERM_PROGRAM:-}
if [ "$(uname -s)" = Darwin ] && { [ -z "$tp" ] || [ "$tp" = Apple_Terminal ]; }; then
  ok "terminal: ${tp:-unknown (assumed Terminal.app)} - automatic /compact after /pre-compact works here"
  if [ "$tp" = Apple_Terminal ]; then ok "terminal: first auto-compact will ask permission to control Terminal - click OK"; fi
else
  warn "terminal: ${tp:-unknown} - automatic /compact is off here; type /compact after /pre-compact finishes"
fi

# ── usage numbers ────────────────────────────────────────────────────────
if [ -f "$CL/kit-usage-enabled" ]; then
  if [ "$(uname -s)" != Darwin ]; then
    warn "usage numbers are turned on, but they only work on a Mac"
  elif [ -f "$CL/ratelimit.json" ] && jq -e . "$CL/ratelimit.json" >/dev/null 2>&1; then
    age=$(( $(date +%s) - $(stat -f %m "$CL/ratelimit.json" 2>/dev/null || stat -c %Y "$CL/ratelimit.json") ))
    if [ "$age" -lt 3600 ]; then ok "usage numbers are fresh ($((age/60)) min old)"
    else warn "usage numbers are $((age/60)) min old - they refresh while the status bar runs; if it stays stale, run /login in Claude Code once"; fi
  else
    warn "usage numbers are on but no data yet (~/.claude/ratelimit.json) - run /login in Claude Code once, then check again"
  fi
else
  ok "usage numbers: off"
fi

# ── agent references ─────────────────────────────────────────────────────
if [ -f "$KIT/scripts/tests/check-agent-refs.sh" ]; then
  if r=$(bash "$KIT/scripts/tests/check-agent-refs.sh" 2>&1); then ok "every agent the skills call is installed"
  else bad "agent check failed: $(printf '%s' "$r" | tail -n +2 | tr '\n' ' ')"; fi
fi

echo ""
if [ "$NFAIL" = 0 ]; then echo "All good ($NWARN warning(s)). Restart Claude Code if you just installed or updated."
else echo "$NFAIL problem(s) found. Fix the FAIL lines (re-running install.sh fixes most), then run this again."; fi
[ "$NFAIL" = 0 ]
