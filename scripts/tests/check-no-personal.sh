#!/usr/bin/env bash
# check-no-personal.sh - fail if personal data would ship in this public repo.
#
# Always checked (every text file, .git skipped):
#   - home paths /Users/<name>   (allowed: test fixtures and placeholders like /Users/test, /Users/me)
#   - the name of the private source repo this kit was copied from
#   - email addresses            (allowed: noreply@..., example.*, *.local / *.test / *.invalid, git@)
#   - IPv4 addresses             (allowed: 127.0.0.1, 0.0.0.0)
#   - password-manager secret references (the op + :// scheme)
#   - secret-looking values, via scripts/secret-scan.sh when it is present
# Extra: $KIT_DENYLIST_FILE, one extended regex per line (case-insensitive; use \b for word
# boundaries, e.g. \bdental\b). Blank lines and lines starting with # are ignored. Keep that file
# OUTSIDE the repo, since it names the very strings that must not ship.
#
# This file deliberately never spells its own forbidden strings literally (they are assembled
# from pieces) so it does not flag itself.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd "$REPO" || exit 2

HITS="$(mktemp "${TMPDIR:-/tmp}/nopersonal.XXXXXX")"
trap 'rm -f "$HITS" "$HITS.files"' EXIT

# Every text file, excluding .git and caches.
find . -type d \( -name .git -o -name __pycache__ -o -name node_modules \) -prune -o -type f -print \
  | sed 's#^\./##' | LC_ALL=C sort > "$HITS.files"

scan() {  # $1 = label, $2 = ERE, $3 = allow-ERE applied to the matched text (optional), $4 = grep flags
  local label="$1" re="$2" allow="${3:-}" flags="${4:-}" f m
  while IFS= read -r f; do
    # shellcheck disable=SC2086
    grep -IHnoE $flags -- "$re" "$f" 2>/dev/null | while IFS= read -r m; do
      text=${m#*:*:}
      if [ -n "$allow" ] && printf '%s' "$text" | grep -qE -- "$allow"; then continue; fi
      printf '  %-14s %s\n' "$label" "$m" >> "$HITS"
    done
  done < "$HITS.files"
}

SRC_REPO="claude-""dotfiles"
OPREF="op"":/""/"

scan "home-path"  '/Users/[a-z][A-Za-z0-9._-]*' '^/Users/(test|me|x|you|your-?name|user|username|name|example)$'
scan "source-repo" "\\b${SRC_REPO}\\b"
scan "email"      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' '^(noreply@|git@)|@(.*\.)?example\.[a-z]+$|\.(local|test|invalid|example)$'
scan "ipv4"       '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' '^(127\.0\.0\.1|0\.0\.0\.0)$'
scan "secret-ref" "$OPREF"

if [ -n "${KIT_DENYLIST_FILE:-}" ]; then
  if [ ! -r "$KIT_DENYLIST_FILE" ]; then
    echo "check-no-personal: FAIL - KIT_DENYLIST_FILE is set but not readable: $KIT_DENYLIST_FILE"; exit 1
  fi
  while IFS= read -r pat || [ -n "$pat" ]; do
    case "$pat" in ''|\#*) continue ;; esac
    scan "denylist" "$pat" "" "-i"
  done < "$KIT_DENYLIST_FILE"
fi

# Secret-looking values (rc 0 clean, 2 hit, anything else = could not scan -> fail closed).
if [ -x scripts/secret-scan.sh ] || [ -f scripts/secret-scan.sh ]; then
  set --
  while IFS= read -r f; do grep -Iq . "$f" 2>/dev/null && set -- "$@" "$f"; done < "$HITS.files"
  # Called directly (not via xargs, which would flatten the 0/2/3 exit vocabulary).
  SS_OUT=$(bash scripts/secret-scan.sh -- "$@" 2>&1); SS_RC=$?
  case "$SS_RC" in
    0) ;;
    2) printf '  %-14s %s\n' "secret" "secret-scan.sh reported possible secrets:" >> "$HITS"
       printf '%s\n' "$SS_OUT" | sed 's/^/                 /' >> "$HITS" ;;
    *) printf '  %-14s %s\n' "secret" "secret-scan.sh could not run (rc=$SS_RC): $(printf '%s' "$SS_OUT" | head -3)" >> "$HITS" ;;
  esac
fi

if [ -s "$HITS" ]; then
  echo "check-no-personal: FAIL - personal data found:"
  cat "$HITS"
  exit 1
fi
echo "check-no-personal: OK ($(wc -l < "$HITS.files" | tr -d ' ') files scanned${KIT_DENYLIST_FILE:+, with denylist})"
