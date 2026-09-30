#!/usr/bin/env bash
# install.sh - install (or update, or remove) the omid_skills kit into ~/.claude.
#
# Safe to run again: every run first undoes what the previous run recorded in
# ~/.claude/.kit-install.json, then installs fresh, so updates leave nothing behind.
#
# Decisions are flags, never interactive questions. When a decision is needed and the flag is
# missing, the script prints ONE line and exits 3 without changing anything:
#     ASK_USER:<code>: <plain question>
# Claude (following SETUP.md) asks the user, then re-runs with the matching flag.
#
# Flags:
#   --yes                            go ahead without a final "continue?" check
#   --dry-run                        show what would change, change nothing
#   --statusline=replace|keep        you already have a status bar: replace it, or keep it
#   --usage=on|off                   show Claude usage numbers in the status bar (Mac only)
#   --claude-md=import|replace-link|skip
#   --dirs=abort|write-through       ~/.claude/commands|agents|rules is a symlink elsewhere
#   --uninstall [--restore-backups]  remove the kit (uninstall.sh calls this)
#
# Exit codes: 0 done, 1 stopped (message says why), 3 a decision is needed (ASK_USER line).
# macOS bash 3.2 compatible.

set -euo pipefail

KIT="$HOME/.claude-kit"
CL="$HOME/.claude"
MANIFEST="$CL/.kit-install.json"
BLOCK_BEGIN='<!-- >>> omid_skills >>> -->'
BLOCK_END='<!-- <<< omid_skills <<< -->'
IMPORT_LINE='@~/.claude-kit/CLAUDE.md'
TS=$(date +%Y%m%d-%H%M%S)

say()  { printf '%s\n' "$*"; }
die()  { printf 'STOPPED: %s\n' "$*" >&2; exit 1; }
ask_user() { printf 'ASK_USER:%s: %s\n' "$1" "$2"; exit 3; }

usage() { awk 'NR==1{next} /^#/{print; next} {exit}' "$0" | sed 's/^# \{0,1\}//'; }

# ── flags ────────────────────────────────────────────────────────────────────
MODE=install YES=0 DRY=0 SL_FLAG="" USAGE_FLAG="" CMD_FLAG="" DIRS_FLAG="" RESTORE=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY=1 ;;
    --statusline=replace|--statusline=keep) SL_FLAG=${arg#*=} ;;
    --usage=on|--usage=off) USAGE_FLAG=${arg#*=} ;;
    --claude-md=import|--claude-md=replace-link|--claude-md=skip) CMD_FLAG=${arg#*=} ;;
    --dirs=abort|--dirs=write-through) DIRS_FLAG=${arg#*=} ;;
    --uninstall) MODE=uninstall ;;
    --restore-backups) RESTORE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$arg'. Run with --help to see the options." ;;
  esac
done

# ── small helpers ────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || die "jq is not installed. On a Mac: brew install jq. On Linux: use your package manager (apt install jq)."

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kit-install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

sha_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

# Unique backup name next to the original: <name>.bak-<TS> (suffix -N if taken).
bak_name() {
  local b="$1.bak-$TS" n=1
  while [ -e "$b" ] || [ -L "$b" ]; do b="$1.bak-$TS-$n"; n=$((n+1)); done
  printf '%s' "$b"
}

sed_escape() { printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'; }

points_into_kit() {  # $1 = link path, $2 = kit dir as recorded
  local t; t=$(readlink "$1" 2>/dev/null) || return 1
  case "$t" in "$2"/*) return 0 ;; esac
  local real; real=$(cd "$2" 2>/dev/null && pwd -P) || return 1
  case "$t" in "$real"/*) return 0 ;; esac
  return 1
}

# Remove now-empty folders left behind under ~/.claude/{commands,agents,rules} (never the tops).
prune_empty_parents() {
  local d; d=$(dirname "$1")
  while :; do
    case "$d" in "$CL/commands"|"$CL/agents"|"$CL/rules"|"$CL"|/|.) break ;; esac
    rmdir "$d" 2>/dev/null || break
    d=$(dirname "$d")
  done
}

# Settings path: write THROUGH a symlinked settings.json (keeps the link) rather than replace it.
SETTINGS="$CL/settings.json"
settings_real_path() {
  if [ -L "$SETTINGS" ]; then
    local t; t=$(readlink "$SETTINGS")
    case "$t" in /*) printf '%s' "$t" ;; *) printf '%s/%s' "$(dirname "$SETTINGS")" "$t" ;; esac
  else printf '%s' "$SETTINGS"; fi
}

atomic_write_json() {  # $1 = source json file, $2 = destination path
  local dst="$2" tmp
  mkdir -p "$(dirname "$dst")"
  tmp=$(mktemp "$(dirname "$dst")/.settings.XXXXXX")
  jq . "$1" > "$tmp"
  [ -f "$dst" ] && chmod "$(stat -f '%Lp' "$dst" 2>/dev/null || stat -c '%a' "$dst")" "$tmp" 2>/dev/null || true
  mv "$tmp" "$dst"
}

# ── previous install (the manifest) ──────────────────────────────────────────
PREV="$WORK/prev.json"
if [ -f "$MANIFEST" ]; then
  jq -e 'type == "object"' "$MANIFEST" >/dev/null 2>&1 \
    || die "the kit's record file $MANIFEST is damaged (not valid JSON). Move it aside and re-run."
  cp "$MANIFEST" "$PREV"
else
  printf '{}\n' > "$PREV"
fi
prev() { jq -r "$1 // empty" "$PREV"; }
PREV_KIT=$(prev .kit_dir); PREV_KIT=${PREV_KIT:-$KIT}

# Current settings (or {}).
S0="$WORK/s0.json"
SETTINGS_REAL=$(settings_real_path)
if [ -f "$SETTINGS_REAL" ]; then
  jq -e 'type == "object"' "$SETTINGS_REAL" >/dev/null 2>&1 \
    || die "$SETTINGS is not valid JSON, so the kit will not touch it. Fix it (or move it aside) and re-run. Nothing was changed."
  cp "$SETTINGS_REAL" "$S0"
else
  printf '{}\n' > "$S0"
fi

# jq: undo exactly what a manifest ($m) says we added to settings.
JQ_REMOVE='
  def created($k): any(($m.created_keys // [])[]; . == $k);
  ([ ($m.hook_commands // [])[] | .event ] | unique) as $events
  | reduce ($m.hook_commands // [])[] as $h (.;
      if (.hooks[$h.event] // null) == null then .
      else .hooks[$h.event] |= map(.hooks |= map(select(.command != $h.command))) end)
  | reduce $events[] as $ev (.;
      if (.hooks[$ev] // null) == null then .
      else .hooks[$ev] |= map(select((.hooks // []) | length > 0))
        | (if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end) end)
  | (if (.permissions.allow // null) != null
       then .permissions.allow |= map(select(. as $r | any(($m.allow_rules // [])[]; . == $r) | not))
       else . end)
  | reduce (($m.settings_keys_added // {}) | to_entries[]) as $k (.;
      if .[$k.key] == $k.value then del(.[$k.key]) else . end)
  | (if ($m.statusline_value // null) != null and .statusLine == $m.statusline_value
       then (if ($m.original_statusline // null) != null then .statusLine = $m.original_statusline
             else del(.statusLine) end)
       else . end)
  | (if created("permissions.allow") and .permissions.allow == [] then del(.permissions.allow) else . end)
  | (if created("permissions") and .permissions == {} then del(.permissions) else . end)
  | (if created("hooks") and .hooks == {} then del(.hooks) else . end)
'

# Remove the files a manifest recorded (links + generated files). Prints one line per skip.
remove_recorded_files() {
  local p sha
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$p" ] && points_into_kit "$p" "$PREV_KIT"; then
      rm -f "$p"; prune_empty_parents "$p"
    fi
  done < <(jq -r '(.links // [])[]' "$PREV")
  while IFS=$'\t' read -r p sha; do
    [ -n "$p" ] || continue
    if [ -f "$p" ] && [ ! -L "$p" ]; then
      if [ "$(sha_of "$p")" = "$sha" ]; then rm -f "$p"; prune_empty_parents "$p"
      else say "  - left in place (you edited it since install): $p"; fi
    fi
  done < <(jq -r '(.renders // [])[] | [.path, .sha256] | @tsv' "$PREV")
  # Safety net: any link under the kit folders that points into the kit but is dangling.
  local d
  for d in commands agents rules; do
    [ -d "$CL/$d" ] || continue
    while IFS= read -r p; do
      if points_into_kit "$p" "$PREV_KIT" && [ ! -e "$p" ]; then rm -f "$p"; prune_empty_parents "$p"; fi
    done < <(find "$CL/$d/" -type l 2>/dev/null)
  done
}

remove_claude_md_block() {  # $1 = file
  local f="$1" tmp
  [ -f "$f" ] && grep -qF "$BLOCK_BEGIN" "$f" || return 0
  tmp=$(mktemp "$WORK/cmd.XXXXXX")
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0 == b { skip = 1; hp = 0; next }
    skip && $0 == e { skip = 0; next }
    skip { next }
    { if (hp) print pend; if ($0 == "") { pend = $0; hp = 1 } else { print; hp = 0 } }
    END { if (hp) print pend }' "$f" > "$tmp"
  cat "$tmp" > "$f"
}

confirm_or_ask() {  # $1 = question
  [ "$YES" = 1 ] || [ "$DRY" = 1 ] && return 0
  if [ -t 0 ]; then
    printf '%s [y/N] ' "$1"; local a; read -r a
    case "$a" in y|Y|yes|YES) return 0 ;; *) say "Stopped. Nothing was changed."; exit 1 ;; esac
  fi
  ask_user confirm "$1 (re-run with --yes to go ahead)"
}

# ═════════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ═════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = uninstall ]; then
  if [ ! -f "$MANIFEST" ]; then
    say "The kit does not look installed (no $MANIFEST). Nothing to remove."
    exit 0
  fi
  confirm_or_ask "Remove the omid_skills kit from ~/.claude?"

  S1="$WORK/s1.json"
  jq --slurpfile mm "$PREV" "\$mm[0] as \$m | $JQ_REMOVE" "$S0" > "$S1"

  if [ "$DRY" = 1 ]; then
    say "DRY RUN - nothing will change. Uninstall would:"
    say "  - remove $(jq '(.links // []) | length' "$PREV") links and $(jq '(.renders // []) | length' "$PREV") generated files"
    say "  - remove $(jq '(.hook_commands // []) | length' "$PREV") hook commands and $(jq '(.allow_rules // []) | length' "$PREV") permission rules from settings.json"
    say "  - remove the kit block from ~/.claude/CLAUDE.md"
    exit 0
  fi

  say "Removing the omid_skills kit..."
  remove_recorded_files

  if ! jq -e --slurpfile a "$S1" '. == $a[0]' "$S0" >/dev/null; then
    if [ -f "$SETTINGS_REAL" ]; then B=$(bak_name "$SETTINGS_REAL"); cp -p "$SETTINGS_REAL" "$B"; say "  - saved a copy of settings.json first: $B"; fi
    atomic_write_json "$S1" "$SETTINGS_REAL"
    say "  - took the kit's hooks and settings out of settings.json (your own settings are untouched)"
  fi

  # CLAUDE.md
  CMD_FILE="$CL/CLAUDE.md"
  if [ -f "$CMD_FILE" ] && [ ! -L "$CMD_FILE" ] && grep -qF "$BLOCK_BEGIN" "$CMD_FILE"; then
    remove_claude_md_block "$CMD_FILE"
    if ! grep -q '[^[:space:]]' "$CMD_FILE" 2>/dev/null; then
      LT=$(prev .claude_md_link_target)
      if [ -n "$LT" ]; then rm -f "$CMD_FILE"; ln -s "$LT" "$CMD_FILE"; say "  - put your CLAUDE.md shortcut back (-> $LT)"
      elif [ "$(prev .claude_md_created)" = "true" ]; then rm -f "$CMD_FILE"; fi
    fi
    say "  - removed the kit block from ~/.claude/CLAUDE.md"
  fi

  rm -f "$CL/kit-usage-enabled"
  for d in commands agents rules; do [ -L "$CL/$d" ] || rmdir "$CL/$d" 2>/dev/null || true; done

  # Backups: list them; restore file backups only when asked and the spot is free.
  NB=$(jq '(.backups // []) | length' "$PREV")
  if [ "$NB" -gt 0 ]; then
    if [ "$RESTORE" = 1 ]; then
      while IFS=$'\t' read -r orig bak kind; do
        [ "$kind" = file ] || continue
        if [ -e "$bak" ] || [ -L "$bak" ]; then
          if [ -e "$orig" ] || [ -L "$orig" ]; then say "  - NOT restored (something is already at $orig): $bak"
          else mkdir -p "$(dirname "$orig")"; mv "$bak" "$orig"; say "  - restored $orig"; fi
        fi
      done < <(jq -r '(.backups // [])[] | [.original, .backup, (.kind // "file")] | @tsv' "$PREV")
    else
      say "Backups the kit made while installing (kept; nothing was restored automatically):"
      while IFS=$'\t' read -r orig bak kind; do
        if [ -e "$bak" ] || [ -L "$bak" ]; then say "  - $bak   (was $orig)"; fi
      done < <(jq -r '(.backups // [])[] | [.original, .backup, (.kind // "file")] | @tsv' "$PREV")
      say "To put your own files back, run: bash ~/.claude-kit/uninstall.sh --restore-backups (files only; settings.json copies are never restored automatically)"
    fi
  fi

  rm -f "$MANIFEST"
  say ""
  say "Done. The kit is removed from ~/.claude. The ~/.claude-kit folder itself is still there;"
  say "delete it yourself if you want it gone. Restart Claude Code to finish."
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# INSTALL
# ═════════════════════════════════════════════════════════════════════════════

# 1. Location: the kit must live at exactly ~/.claude-kit.
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
KIT_REAL=$(cd "$KIT" 2>/dev/null && pwd -P || true)
if [ "$SELF_DIR" != "$KIT_REAL" ]; then
  die "the kit must live in the folder ~/.claude-kit, but this copy is at $SELF_DIR.
Fix: git clone https://github.com/omdiidi/omid_skills ~/.claude-kit
then run: bash ~/.claude-kit/install.sh"
fi

# 2. Preflight: required tools.
MISSING=""
for t in jq git python3 node; do command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"; done
if [ -n "$MISSING" ]; then
  die "these tools are missing:$MISSING. The kit needs them to work.
On a Mac: brew install$MISSING   (Homebrew: https://brew.sh)
On Linux: install them with your package manager. Node also comes from https://nodejs.org"
fi
[ -f "$KIT/settings/kit-settings.json" ] || die "the kit looks incomplete ($KIT/settings/kit-settings.json is missing). Re-clone it."

# 3. Decisions (all checked BEFORE anything changes).
#    Symlinked kit folders.
DIRS_MODE=${DIRS_FLAG:-$(prev .dirs_mode)}
LINKED_DIRS=""
for d in commands agents rules; do
  if [ -L "$CL/$d" ]; then
    LINKED_DIRS="$LINKED_DIRS $d"
    if [ -d "$KIT/$d" ] && [ "$(cd "$CL/$d" 2>/dev/null && pwd -P)" = "$(cd "$KIT/$d" && pwd -P)" ]; then
      die "~/.claude/$d is a shortcut straight into the kit itself. Remove that shortcut (rm ~/.claude/$d) and re-run; the installer links file by file."
    fi
  fi
done
if [ -n "$LINKED_DIRS" ]; then
  FIRST=${LINKED_DIRS# }; FIRST=${FIRST%% *}
  case "$DIRS_MODE" in
    write-through) ;;
    abort) say "Stopped as asked (--dirs=abort): ~/.claude/$FIRST is a shortcut to $(readlink "$CL/$FIRST"). Nothing was changed."; exit 1 ;;
    *) ask_user dirs_symlink "Your ~/.claude/$FIRST folder is a shortcut (symlink) to $(readlink "$CL/$FIRST"), so installing would add the kit's files inside that other folder. Allow that (--dirs=write-through) or stop (--dirs=abort)?" ;;
  esac
fi

#    CLAUDE.md.
CMD_FILE="$CL/CLAUDE.md"
CMD_MODE=${CMD_FLAG:-$(prev .claude_md_mode)}; CMD_MODE=${CMD_MODE:-import}
if [ -L "$CMD_FILE" ]; then
  case "$CMD_MODE" in
    replace-link|skip) ;;
    *) ask_user claude_md_symlink "Your ~/.claude/CLAUDE.md is a shortcut (symlink) to $(readlink "$CMD_FILE"), and the kit never writes through shortcuts. Replace the shortcut with a normal file that loads the kit (--claude-md=replace-link; uninstall puts the shortcut back), or leave it alone and add one line by hand (--claude-md=skip)?" ;;
  esac
fi

#    Status bar. Work out what the user's own status bar is once the previous kit install is undone.
PREV_SLV=$(jq -cS '.statusline_value // empty' "$PREV")
PREV_ORIG=$(jq -cS '.original_statusline // empty' "$PREV")
CUR_SL=$(jq -cS '.statusLine // empty' "$S0")
if [ -n "$PREV_SLV" ] && [ "$CUR_SL" = "$PREV_SLV" ]; then BASE_SL=$PREV_ORIG; else BASE_SL=$CUR_SL; fi
if [ -n "$BASE_SL" ] && printf '%s' "$BASE_SL" | jq -e '(.command // "") | test("kit-statusline(-wrap)?\\.sh")' >/dev/null; then
  BASE_SL=""   # it is ours already; nothing of the user's to keep
fi
SL_MODE=$SL_FLAG
if [ -z "$SL_MODE" ]; then
  if [ -z "$BASE_SL" ]; then SL_MODE=replace
  elif [ -n "$(prev .statusline_mode)" ] && [ "$PREV_ORIG" = "$BASE_SL" ]; then SL_MODE=$(prev .statusline_mode)
  else
    ask_user statusline "You already have your own status bar command ($(printf '%s' "$BASE_SL" | jq -r '.command // "?"')). Replace it with the kit's status bar (--statusline=replace, recommended: shows context % and session info), or keep yours and run the kit's context tracking quietly behind it (--statusline=keep)?"
  fi
fi
SL_NOTE=""
if [ "$SL_MODE" = keep ] && [ -z "$BASE_SL" ]; then SL_MODE=replace; SL_NOTE=" (you had no status bar of your own, so the kit's is used)"; fi

USAGE_MODE=${USAGE_FLAG:-$(prev .usage)}; USAGE_MODE=${USAGE_MODE:-off}

# Updates (a previous install is recorded) go ahead; only a first install asks once.
[ -f "$MANIFEST" ] || confirm_or_ask "Install the omid_skills kit into ~/.claude?"

# 4. Settings: compute the whole result in memory first (S0 -> S1 undo previous -> S2 merged).
FRAG="$WORK/frag.json"
jq --arg kit "$KIT" --arg home "$HOME" --argjson nodetach "$([ -f "$KIT/scripts/hooks/no-detach-gate.py" ] && echo true || echo false)" '
  def r: if type == "object" then map_values(r) elif type == "array" then map(r)
         elif type == "string" then gsub("__KIT__"; $kit) | gsub("__HOME__"; $home) else . end;
  r
  | if $nodetach then . else
      .hooks |= map_values(map(.hooks |= map(select(.command | test("no-detach-gate\\.py") | not)))
                           | map(select(.hooks | length > 0)))
    end' "$KIT/settings/kit-settings.json" > "$FRAG"

WRAPPER="$CL/kit-statusline-wrap.sh"
KIT_SL_LINK="$CL/kit-statusline.sh"
if [ "$SL_MODE" = keep ]; then
  NEW_SL=$(printf '%s' "$BASE_SL" | jq -c --arg w "$WRAPPER" '.command = $w | .type = "command"')
else
  NEW_SL=$(jq -c '.statusLine' "$FRAG")
fi

S1="$WORK/s1.json"; S2="$WORK/s2.json"; ADDED="$WORK/added.json"
jq --slurpfile mm "$PREV" "\$mm[0] as \$m | $JQ_REMOVE" "$S0" > "$S1"
jq --slurpfile ff "$FRAG" --argjson sl "$NEW_SL" '
  $ff[0] as $f | . as $before
  | reduce ($f.hooks | to_entries[]) as $e (.;
      reduce $e.value[] as $g (.;
        ([ (.hooks[$e.key] // [])[] | (.hooks // [])[] | .command ]) as $have
        | ([ $g.hooks[] | select(.command as $c | any($have[]; . == $c) | not) ]) as $new
        | if ($new | length) > 0 then .hooks[$e.key] = ((.hooks[$e.key] // []) + [ $g + {hooks: $new} ]) else . end))
  | .permissions.allow = ((.permissions.allow // [])
      + ([ $f.permissions.allow[] | select(. as $r | any(($before.permissions.allow // [])[]; . == $r) | not) ] | unique))
  | reduce ($f | to_entries[] | select(.key != "hooks" and .key != "permissions" and .key != "statusLine")) as $k (.;
      if has($k.key) then . else .[$k.key] = $k.value end)
  | .statusLine = $sl' "$S1" > "$S2"
jq -n --slurpfile a "$S1" --slurpfile b "$S2" --slurpfile ff "$FRAG" '
  $a[0] as $s1 | $b[0] as $s2 | $ff[0] as $f
  | def cmds($s; $ev): [ ($s.hooks[$ev] // [])[] | (.hooks // [])[] | .command ];
  {
    hook_commands: [ $f.hooks | keys[] as $ev
      | cmds($s2; $ev)[] as $c | select(any(cmds($s1; $ev)[]; . == $c) | not) | {event: $ev, command: $c} ],
    allow_rules: [ ($s2.permissions.allow // [])[] as $r | select(any(($s1.permissions.allow // [])[]; . == $r) | not) | $r ],
    settings_keys_added: ([ $f | to_entries[] | select(.key != "hooks" and .key != "permissions" and .key != "statusLine")
      | select(.key as $k | ($s1 | has($k)) | not) | {key: .key, value: $s2[.key]} ] | from_entries),
    created_keys: ([ (if $s1.hooks == null and $s2.hooks != null then "hooks" else empty end),
                     (if $s1.permissions == null and $s2.permissions != null then "permissions" else empty end),
                     (if ($s1.permissions.allow // null) == null and ($s2.permissions.allow // null) != null then "permissions.allow" else empty end) ]),
    statusline_value: $s2.statusLine,
    original_statusline: $s1.statusLine
  }' > "$ADDED"

SETTINGS_CHANGES=1
jq -e --slurpfile a "$S2" '. == $a[0]' "$S0" >/dev/null && SETTINGS_CHANGES=0

# 5. File plan: every file under commands/, agents/*.md, rules/*.md.
LIST="$WORK/files.txt"
( cd "$KIT" && {
    find commands -type f ! -name '.DS_Store' ! -name '*.pyc' ! -path '*/__pycache__/*' 2>/dev/null
    find agents rules -maxdepth 1 -type f -name '*.md' 2>/dev/null
  } | LC_ALL=C sort ) > "$LIST"

LINKS="$WORK/links.txt"; RENDERS="$WORK/renders.tsv"; BACKUPS="$WORK/backups.tsv"
: > "$LINKS"; : > "$RENDERS"; : > "$BACKUPS"
KIT_ESC=$(sed_escape "$KIT")

# Move a foreign file/link out of the way (records it). In dry-run only reports.
backup_foreign() {  # $1 = path
  local b; b=$(bak_name "$1")
  if [ "$DRY" = 1 ]; then say "  - would move your existing $1 to $b"; return; fi
  mv "$1" "$b"
  printf '%s\t%s\tfile\n' "$1" "$b" >> "$BACKUPS"
}

link_one() {  # $1 = source (absolute), $2 = target
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then printf '%s\n' "$dst" >> "$LINKS"; return; fi
  if [ -L "$dst" ] && points_into_kit "$dst" "$KIT"; then [ "$DRY" = 1 ] || rm -f "$dst"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    [ -d "$dst" ] && [ ! -L "$dst" ] && die "$dst is a folder where the kit wants to put a file. Move it aside and re-run."
    backup_foreign "$dst"
  fi
  if [ "$DRY" = 0 ]; then mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; fi
  printf '%s\n' "$dst" >> "$LINKS"
}

render_one() {  # $1 = source, $2 = target
  local src="$1" dst="$2" tmp
  tmp="$WORK/render.tmp"
  sed "s#__KIT_ABS__#${KIT_ESC}#g" "$src" > "$tmp"
  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$tmp" "$dst"; then :
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] && points_into_kit "$dst" "$KIT"; then [ "$DRY" = 1 ] || rm -f "$dst"; else backup_foreign "$dst"; fi
  fi
  if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$dst")"
    cmp -s "$tmp" "$dst" 2>/dev/null || { cp "$tmp" "$dst"; chmod "$( [ -x "$src" ] && echo 755 || echo 644 )" "$dst"; }
  fi
  printf '%s\t%s\n' "$dst" "$(sha_of "$tmp")" >> "$RENDERS"
}

if [ "$DRY" = 1 ]; then
  say "DRY RUN - nothing will change. Here is what install would do:"
  [ "$(jq '(.links // []) | length' "$PREV")" -gt 0 ] && say "  - first undo the previous install ($(jq '(.links // []) | length' "$PREV") links, $(jq '(.hook_commands // []) | length' "$PREV") hook commands)"
else
  say "Installing the omid_skills kit into ~/.claude ..."
  remove_recorded_files
  [ -f "$WRAPPER" ] && ! jq -e --arg w "$WRAPPER" 'any((.renders // [])[]; .path == $w)' "$PREV" >/dev/null \
    && grep -q 'generated by omid_skills install.sh' "$WRAPPER" 2>/dev/null && rm -f "$WRAPPER"
fi

N_LINK=0 N_RENDER=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if grep -q '__KIT_ABS__' "$KIT/$rel" 2>/dev/null; then
    render_one "$KIT/$rel" "$CL/$rel"; N_RENDER=$((N_RENDER+1))
  else
    link_one "$KIT/$rel" "$CL/$rel"; N_LINK=$((N_LINK+1))
  fi
done < "$LIST"

# 6. Status bar files.
link_one "$KIT/scripts/statusline.sh" "$KIT_SL_LINK"
if [ "$SL_MODE" = keep ]; then
  ORIG_CMD=$(printf '%s' "$BASE_SL" | jq -r '.command')
  cat > "$WORK/wrap.sh" <<EOF
#!/usr/bin/env bash
# generated by omid_skills install.sh - keeps your own status bar and quietly feeds the
# kit's context-% tracker. Your original command is restored when you uninstall the kit.
input=\$(cat)
printf '%s' "\$input" | $(printf '%q' "$KIT_SL_LINK") --ctx-only >/dev/null 2>&1 || true
printf '%s' "\$input" | bash -c $(printf '%q' "$ORIG_CMD")
EOF
  if [ -e "$WRAPPER" ] || [ -L "$WRAPPER" ]; then
    cmp -s "$WORK/wrap.sh" "$WRAPPER" || backup_foreign "$WRAPPER"
  fi
  if [ "$DRY" = 0 ]; then cp "$WORK/wrap.sh" "$WRAPPER"; chmod 755 "$WRAPPER"; fi
  printf '%s\t%s\n' "$WRAPPER" "$(sha_of "$WORK/wrap.sh")" >> "$RENDERS"
fi

# 7. Settings.
SETTINGS_BAK=""
if [ "$DRY" = 1 ]; then
  if [ "$SETTINGS_CHANGES" = 1 ]; then
    say "  - settings.json: add $(jq '.hook_commands | length' "$ADDED") hook commands and $(jq '.allow_rules | length' "$ADDED") permission rule(s); status bar mode: $SL_MODE"
  else say "  - settings.json: already up to date"; fi
elif [ "$SETTINGS_CHANGES" = 1 ]; then
  if [ -f "$SETTINGS_REAL" ]; then
    SETTINGS_BAK=$(bak_name "$SETTINGS_REAL"); cp -p "$SETTINGS_REAL" "$SETTINGS_BAK"
    printf '%s\t%s\tsettings\n' "$SETTINGS_REAL" "$SETTINGS_BAK" >> "$BACKUPS"
  fi
  atomic_write_json "$S2" "$SETTINGS_REAL"
fi

# 8. Usage numbers.
USAGE_NOTE=""
if [ "$USAGE_MODE" = on ]; then
  if [ "$DRY" = 1 ]; then USAGE_NOTE="would turn on usage numbers"
  else
    touch "$CL/kit-usage-enabled"
    if [ "$(uname -s)" = Darwin ]; then
      RL="$CL/ratelimit.json"
      # shellcheck source=scripts/lib/portable-timeout.sh
      . "$KIT/scripts/lib/portable-timeout.sh"
      pt_run 45 bash "$KIT/scripts/refresh-ratelimit.sh" >/dev/null 2>&1 || true
      RL_AGE=$( [ -f "$RL" ] && echo $(( $(date +%s) - $(stat -f %m "$RL" 2>/dev/null || stat -c %Y "$RL") )) || echo 999999 )
      if [ "$RL_AGE" -lt 3600 ] && jq -e . "$RL" >/dev/null 2>&1; then
        USAGE_NOTE="on - first usage check worked"
      else
        USAGE_NOTE="on - but the first usage check did not return data yet (usually fixed by running /login in Claude Code once)"
      fi
    else
      USAGE_NOTE="marker set, but usage numbers only work on a Mac, so they stay hidden here"
    fi
  fi
else
  [ "$DRY" = 1 ] || rm -f "$CL/kit-usage-enabled"
  USAGE_NOTE="off"
fi

# 9. CLAUDE.md import block.
CMD_CREATED=$(prev .claude_md_created); CMD_CREATED=${CMD_CREATED:-false}
CMD_LINK_TARGET=$(prev .claude_md_link_target)
CMD_NOTE=""
write_block() {  # $1 = file ; appends the block
  if [ -s "$1" ]; then printf '\n%s\n%s\n%s\n' "$BLOCK_BEGIN" "$IMPORT_LINE" "$BLOCK_END" >> "$1"
  else printf '%s\n%s\n%s\n' "$BLOCK_BEGIN" "$IMPORT_LINE" "$BLOCK_END" > "$1"; fi
}
case "$CMD_MODE" in
  skip)
    CMD_NOTE="left alone as asked. To load the kit, add this line to your CLAUDE.md yourself: $IMPORT_LINE" ;;
  replace-link|import)
    if [ -L "$CMD_FILE" ]; then   # only reachable with replace-link
      if [ "$DRY" = 0 ]; then CMD_LINK_TARGET=$(readlink "$CMD_FILE"); rm -f "$CMD_FILE"; write_block "$CMD_FILE"; fi
      CMD_NOTE="your CLAUDE.md shortcut was replaced by a normal file that loads the kit (it pointed to $(readlink "$CMD_FILE" 2>/dev/null || echo "$CMD_LINK_TARGET"); uninstall puts it back)"
    elif [ -f "$CMD_FILE" ] && grep -qF "$BLOCK_BEGIN" "$CMD_FILE"; then
      CMD_NOTE="already loads the kit"
    else
      if [ "$DRY" = 0 ]; then
        [ -f "$CMD_FILE" ] || CMD_CREATED=true
        mkdir -p "$CL"; touch "$CMD_FILE"; write_block "$CMD_FILE"
      fi
      CMD_NOTE="added a small block that loads the kit (your own text is untouched)"
    fi ;;
esac

if [ "$DRY" = 1 ]; then
  say "  - link $N_LINK files and write $N_RENDER personalized files into ~/.claude/{commands,agents,rules}"
  say "  - status bar: $SL_MODE$SL_NOTE; usage numbers: $USAGE_NOTE"
  say "  - CLAUDE.md: $CMD_NOTE"
  exit 0
fi

# 10. Manifest.
VERSION=$(git -C "$KIT" describe --tags --always 2>/dev/null || echo unknown)
tmpm="$WORK/manifest.json"
jq -n \
  --arg version "$VERSION" --arg kit "$KIT" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --rawfile links "$LINKS" --rawfile renders "$RENDERS" --rawfile backups "$BACKUPS" \
  --slurpfile added "$ADDED" --slurpfile pv "$PREV" \
  --arg slmode "$SL_MODE" --arg usage "$USAGE_MODE" --arg cmdmode "$CMD_MODE" \
  --argjson cmdcreated "$CMD_CREATED" --arg cmdlt "$CMD_LINK_TARGET" --arg dirs "${DIRS_MODE:-}" \
  --arg settings "$SETTINGS_REAL" '
  def lines($s): $s | split("\n") | map(select(length > 0));
  $added[0] as $a | $pv[0] as $p
  | {
      version: $version, kit_dir: $kit, installed_at: $at, settings_path: $settings,
      links: lines($links),
      renders: [ lines($renders)[] | split("\t") | {path: .[0], sha256: .[1]} ],
      backups: ((($p.backups // []) + [ lines($backups)[] | split("\t") | {original: .[0], backup: .[1], kind: .[2]} ]) | unique_by(.backup)),
      hook_commands: $a.hook_commands, allow_rules: $a.allow_rules,
      settings_keys_added: $a.settings_keys_added, created_keys: $a.created_keys,
      statusline_mode: $slmode, statusline_value: $a.statusline_value, original_statusline: $a.original_statusline,
      usage: $usage,
      claude_md_mode: $cmdmode, claude_md_created: $cmdcreated,
      claude_md_link_target: (if $cmdlt == "" then null else $cmdlt end),
      dirs_mode: (if $dirs == "" then null else $dirs end)
    }' > "$tmpm"
# A previous run's settings keys/containers stay "ours" even though this run found them present.
jq --slurpfile pv "$PREV" '
  $pv[0] as $p
  | .created_keys = ((.created_keys + ($p.created_keys // [])) | unique)' "$tmpm" > "$tmpm.2"
mkdir -p "$CL"; mv "$tmpm.2" "$MANIFEST"

# 11. Plain-English summary.
say ""
say "Done. The omid_skills kit is installed."
say "  - $N_LINK files linked and $N_RENDER personalized files written into ~/.claude (commands, agents, rules)"
if [ "$SETTINGS_CHANGES" = 1 ]; then
  say "  - settings.json: kit hooks added, your own settings kept$( [ -n "$SETTINGS_BAK" ] && printf ' (copy saved first: %s)' "$SETTINGS_BAK")"
else
  say "  - settings.json: already up to date"
fi
if [ "$SL_MODE" = keep ]; then say "  - status bar: kept yours; the kit tracks context % quietly behind it"
else say "  - status bar: the kit's status bar$SL_NOTE"; fi
say "  - usage numbers: $USAGE_NOTE"
say "  - CLAUDE.md: $CMD_NOTE"
if [ -s "$BACKUPS" ] && grep -q $'\tfile$' "$BACKUPS"; then
  say "  - some of your files had the same names as kit files, so they were moved aside (not deleted):"
  grep $'\tfile$' "$BACKUPS" | while IFS=$'\t' read -r o b k; do say "      $o  ->  $b"; done
fi
say ""
say "Restart Claude Code to load everything."
