#!/bin/bash
# Shared secret-scanner (explicit-path mode only). Used by:
#   - commands/god-review/principles/secret-leak.md 2.4
#         Renders the exit code as prose, and applies the 3>2>0 precedence. It must tell
#         rc=2 (a real hit -> rotate) from any other non-zero (the scan could not run -> do
#         NOT tell anyone to rotate).
#
# KEEP THIS LIST COMPLETE. Anyone changing the exit-code vocabulary below must be able to
# enumerate every caller from here; a consumer missing from this list is a consumer that
# silently keeps the old contract.
#
# Usage: secret-scan.sh [--] <file> [<file> ...]
#
# Exit codes:
#   0 = clean
#   2 = secret(s) detected (caller should block)
#   3 = scan failure (caller should fail closed)
#
# Precedence is 3 > 2 > 0: if ANY input could not be proven clean, the run exits 3 even
# when another input produced a real hit. "Could not prove clean" is never reported as clean.
#
# SCOPE: this chain defends against ACCIDENTAL exposure. It is NOT a defense against
# deliberate circumvention by the person pushing (--no-verify, core.hooksPath, BASH_ENV,
# PATH shims, or editing this file).

set -o pipefail
export LC_ALL=C

# ANCHORING (2026-08-03): the `sk-` lane is LEFT-ANCHORED on an ALPHANUMERIC boundary.
# Unanchored it matched INSIDE a word: any word ending in those two letters, followed by a
# hyphen and a 20+ character hyphenated run, was a hit - so ordinary prose about a
# task-specific thing, a risk-based approach, or disk-space monitoring all returned rc=2.
# In a repo whose prose is full of long kebab-case identifiers, that is not a cosmetic
# false positive: every scan of that prose reports a secret.
#
# THE BOUNDARY EXCLUDES ONLY [A-Za-z0-9] - NOT `_` AND NOT `-`. This is load-bearing and was
# corrected after review: an earlier draft used [^A-Za-z0-9_-], which treats _ and - as part
# of the preceding word and therefore MISSED a real key written `backup_sk-<payload>` or
# `prefix-sk-<payload>`. That trades a false positive for a false NEGATIVE on the one control
# standing between a repo and a public remote - strictly the wrong direction. The
# false-positive cases only ever needed alphanumeric exclusion (task/risk/disk end in a, i, i),
# so this boundary rejects them AND still catches a key glued to a separator.
#
# NOT every other lane is self-anchoring. AKIA/ghp_/AIza/npm_/github_pat_ are, via fixed
# prefixes. `hf_`, `xox[abposr]-`, and `(rk|sk|pk)_(live|test)_` are NOT - measured rc=2 on
# `branchf_...`, `prefixoxb-...`, `network_live_...`. Left unanchored deliberately for now:
# they are far rarer in prose than the task/risk/disk family, and widening the fix without a
# measured false-positive is how the previous over-correction happened. Tracked, not closed.
#
# THE RESIDUAL GAP THIS BOUNDARY ACCEPTS (documented 2026-08-03 - three reviewers derived it
# independently because it was written down nowhere): an ALPHANUMERIC-glued key is a false
# negative. MEASURED: `PREFIXsk-<44 chars>` -> rc=0. That is the unavoidable cost of excluding
# only [A-Za-z0-9]; the alternative reintroduces the prose false positives above. It is a much
# narrower class than the `backup_sk-` case (a key run together with a preceding WORD, no
# separator at all, is not a shape secrets are normally written in), so the trade is accepted -
# but it is ACCEPTED, not absent. Do not "fix" it without a measured false-positive count.
#
# A NUL byte is a separator too, and deleting one used to close this boundary - see the note
# in scan_stdin about `tr` translating rather than deleting.
#
# Do NOT write those example words here with a separator between the two halves - a
# non-alphanumeric character in that position makes this very comment match the lane.
RX='((^|[^A-Za-z0-9])sk-(ant|proj|svcacct)?-?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}|ghu_[A-Za-z0-9]{36,}|ghs_[A-Za-z0-9]{36,}|ghr_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|npm_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[abposr]-[A-Za-z0-9-]{10,}|hf_[A-Za-z0-9]{30,}|ya29\.[A-Za-z0-9_-]{20,}|whsec_[A-Za-z0-9]{20,}|(rk|sk|pk)_(live|test)_[A-Za-z0-9]{20,}|-----BEGIN +(RSA +|OPENSSH +|EC +|DSA +|PGP +)?PRIVATE +KEY-----)'
export RX

# Connection strings and JWTs (added 2026-08-03 by explicit user decision on pd:2-rx-conn-scope,
# after an earlier measurement had argued AGAINST them). Folded into RX so they apply everywhere
# the primary lane does.
#
# FALSE POSITIVES ARE THE DOMINANT RISK HERE, not misses: a false positive makes every scan
# report a secret, which is strictly worse than one missed exotic secret. So both patterns are anchored to STRUCTURE, never to a loose prefix:
#
#   JWT - requires all THREE base64url segments AND a `eyJ` first segment (base64 of `{"`).
#         A bare `eyJ...` prefix rule would match ordinary base64 in docs; three dot-separated
#         segments of >=10 chars each is a shape prose does not accidentally produce.
#         MEASURED before adding: 0 hits across every tracked file.
#
#   CONN - requires scheme + BOTH a user and a password + host. `postgres://localhost/db` and
#          `https://example.com` correctly do NOT match; only an embedded credential pair does.
#          Schemes are enumerated (no generic `://`) so ordinary URLs cannot trip it.
#          An INTERPOLATED password (`${VAR}`, `$VAR`) is excluded - it is a reference, not a
#          literal secret, and matching it would red the tree on ordinary fixtures.
#          KNOWN BLIND SPOT, accepted deliberately: a real literal password CONTAINING `$` is
#          missed. That is the correct trade here - see the asymmetry argument above.
#          MEASURED before adding: 2 hits, both tracked test fixtures; one was an interpolated
#          password (now excluded by the pattern) and one was a literal that was converted to
#          runtime assembly, matching this repo's existing fixture convention.
RX_JWT='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
RX_CONN='(postgres|postgresql|mysql|mongodb(\+srv)?|redis|rediss|amqp|amqps|mssql)://[^:/@[:space:]]+:[^@/[:space:]$\{]+@[^[:space:]/]+'
RX="${RX%)}|${RX_JWT}|${RX_CONN})"
export RX RX_JWT RX_CONN

# scan_stdin <label>
# Reads candidate content on STDIN.
# Prints "<label>:<lineno>:<match>" lines on STDOUT.
# Returns: 0 clean, 2 hit, 3 scan failure.
#
# Every filter's status is checked. grep exits 0=match, 1=no-match, >1=error; treating an
# error as "no match" is precisely how a broken scanner reports a secret-bearing file clean.
scan_stdin() {
    f="$1"
    # NUL is TRANSLATED TO A SPACE, never deleted (2026-08-03, round-2 review - a real
    # false negative, found by one reviewer of seven).
    #
    # Bash cannot hold a NUL in a variable, so it has to go. But DELETING it closes the gap
    # between the bytes on either side, and the boundary-anchored lanes added in round 1
    # need that gap: `X\0sk-<key>` collapsed to `Xsk-<key>`, where `(^|[^A-Za-z0-9])` has
    # no non-alphanumeric character to match, so grep returned 1 and the scanner exited 0.
    # MEASURED: `X\0sk-<44 chars>` -> rc=0, while the identical content with a space ->
    # rc=2. The anchoring fix introduced this; the unanchored regex it replaced caught it.
    #
    # A space is the minimal correct substitute: it restores the word boundary while
    # preserving line numbering exactly (a newline would renumber every reported hit in a
    # NUL-bearing file). Any non-alphanumeric byte would do; space is the least surprising.
    content=$(tr "\000" " ") || return 3

    hits=$(printf '%s' "$content" | grep -anE -e "$RX"); rc=$?
    [ "$rc" -gt 1 ] && return 3

    [ -z "$hits" ] && return 0
    # Prefix the label WITHOUT interpolating it into a sed program. `sed "s|^|$f:|"` breaks
    # on any filename containing the delimiter `|`, a backslash, or a newline - probed: a
    # newline in the name made the sed script invalid and turned a real hit into rc=3.
    while IFS= read -r line; do
        printf '%s:%s\n' "$f" "$line"
    done <<< "$hits"
    return 2
}

# scan_file <path> — scans the WORKTREE bytes at <path>.
# Returns: 0 clean, 2 hit, 3 scan failure.
scan_file() {
    f="$1"
    # Anchor on a real .git path component. The old `*.git/*` also matched ordinary
    # paths such as vendor/leak.git/secret.txt, which silently skipped them everywhere.
    case "$f" in .git/*|*/.git/*) return 0 ;; esac
    # A SYMLINK must be scanned as git stores it: the blob is the TARGET PATH string, not
    # the bytes it points at. Following it read content git never publishes (a tracked link
    # to ~/.aws/credentials produced a false positive) while never reading what git does.
    if [ -L "$f" ]; then
        # Guard an option-shaped name: a tracked symlink literally named `--help` or
        # `--version` would be parsed as a FLAG by GNU readlink, which then prints help and
        # exits 0 - so the link's real target (the bytes git publishes) is never scanned and
        # the file is reported clean. Prefixing `./` makes it unambiguously a path. Done with
        # a case test rather than `--`, whose support differs across BSD and GNU readlink.
        case "$f" in -*) _rl="./$f" ;; *) _rl="$f" ;; esac
        _t=$(readlink "$_rl") || return 3
        printf '%s' "$_t" | scan_stdin "$f"; return $?
    fi
    [ -f "$f" ] || return 0      # absent or non-regular: nothing to publish
    [ -r "$f" ] || return 3      # present but unreadable: cannot prove clean
    scan_stdin "$f" < "$f"; rc=$?
    [ "$rc" -eq 1 ] && return 3  # scan_stdin never returns 1; a 1 means the redirect failed
    return "$rc"
}

usage() {
    echo "Usage: $0 [--] <file>..." >&2
}

# Enumeration goes through a NUL-delimited temp file, never a newline-delimited scalar:
# bash cannot hold NUL in a variable, and a newline-delimited list silently splits any
# path containing a newline. A file also lets the producer's exit status be checked,
# which `< <(...)` process substitution structurally cannot report.
TMPLIST=$(mktemp "${TMPDIR:-/tmp}/secret-scan.XXXXXX") || exit 3
# Two separate traps on purpose: a single `trap ... EXIT HUP INT TERM` RESUMES after the
# handler and exits 0 (probe-confirmed fail-open). Signal handlers must exit explicitly.
trap 'rm -f "$TMPLIST"' EXIT
trap 'rm -f "$TMPLIST"; exit 3' HUP INT TERM

case "${1:-}" in
    "")
        usage
        exit 3
        ;;
    --)
        # Explicit end of options: everything after is a PATH, even if it looks like a
        # flag, so a tracked file named like an option cannot be misread as one.
        shift
        printf '%s\0' "$@" > "$TMPLIST" || exit 3
        ;;
    -*)
        # FAIL CLOSED on an unrecognized option (2026-08-03). Without this branch the
        # catch-all below treated `--stdin` / a typo / a renamed flag as a PATH: the file
        # does not exist, the per-file existence check skips it, and the scanner exits 0
        # having scanned NOTHING while reporting clean.
        #
        # THE PATTERN IS `-*`, NOT `--*`, so a single-dash typo fails closed too. The literal
        # `--` end-of-options token is claimed by the case above, so widening to `-*` cannot
        # swallow it, and a real file whose name begins with a dash is still
        # reachable via `--`.
        echo "secret-scan: unknown option '$1'" >&2
        usage
        exit 3
        ;;
    *)
        # Validate EVERY argument, not just $1 (2026-08-03, round-2 review). The `-*` guard
        # above inspects only the FIRST token, so `clean.txt --stdin` fell through to here:
        # the flag became a "path", the per-file existence check skipped it, and the scanner
        # exited 0 having scanned only `clean.txt` while silently dropping an argument it did
        # not understand. MEASURED before the fix: `secret-scan.sh ok.txt --stdin` -> rc=0.
        # Options are only ever meaningful in first position, so any later dash-leading token
        # is a mistake; `--` above remains the escape hatch for a real file named `-x`.
        for _a in "$@"; do
            case "$_a" in
                -*)
                    echo "secret-scan: unknown option '$_a' (use -- before a path starting with a dash)" >&2
                    usage
                    exit 3
                    ;;
            esac
        done
        printf '%s\0' "$@" > "$TMPLIST" || exit 3
        ;;
esac

WORST=0
HITS=""
SCANNED=0
ENUMERATED=0
while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    ENUMERATED=$((ENUMERATED + 1))
    {
        # An absent path is TOLERATED here but does NOT count as scanned. Two intents meet
        # at this line and both are legitimate:
        #   - Callers pipe `git ls-files` in, so a path that vanished between enumeration and
        #     scan must not turn the whole run red.
        #   - But a scanner told to scan ONE path that is not there, answering "clean", is
        #     "scanned nothing, reported success" - the class this whole effort exists to kill.
        # Counting rather than failing satisfies both: a mixed batch stays green, while an
        # invocation where NOTHING was scanned fails closed at the counter below.
        if [ ! -e "$f" ] && [ ! -L "$f" ]; then
            echo "secret-scan: no such path (not counted as scanned): $f" >&2
            continue
        fi
        # A dangling symlink is still scannable (scan_file reads the stored target string,
        # which is what git publishes), so -L is checked before the regular-file test.
        #
        # A non-regular entry: a submodule gitlink has no blob in THIS repository, so it is
        # accounted for (callers enumerate via `git ls-files`, which lists gitlinks). A plain
        # directory the caller named is NOT accounted for, so a lone directory argument still
        # trips the invariant and returns 3. A caller who asked for one thing and got nothing
        # scanned must not be told "clean".
        if [ ! -L "$f" ] && [ ! -f "$f" ]; then
            # The god-review 2.4 block ENUMERATES via `git ls-files` and then passes the result
            # as EXPLICIT PATHS, so a batch containing only gitlinks must not return rc=3.
            # A gitlink is identifiable from the index, so ask that directly.
            # The index lookup must match the ENTRY EXACTLY. `git ls-files -s -- <dir>`
            # applies the path as a PATHSPEC and lists the directory's CONTENTS recursively,
            # so a directory whose first sorted entry happened to be a gitlink was itself
            # counted as an accounted gitlink - and the scan exited 0 CLEAN having opened
            # nothing, with a real key sitting inside it. MEASURED (round 7): a repo with
            # `pkg/m` (mode 160000) and a secret-bearing `pkg/zsecret.txt` returned rc=0 for
            # `-- pkg`, while `-- pkg/zsecret.txt` returned 2. Compare the path field.
            if [ "$(git -c core.quotePath=false ls-files -s -- "$f" 2>/dev/null \
                    | awk -F'\t' -v p="$f" '$2==p{split($1,a," "); print a[1]; exit}')" = 160000 ]; then
                SCANNED=$((SCANNED + 1))   # no blob in THIS repo; legitimately accounted
            else
                # A plain directory the caller NAMED is still not accounted for, so a lone
                # directory argument keeps returning 3 rather than a bare "clean".
                echo "secret-scan: not a regular file, not counted as scanned: $f" >&2
            fi
            continue
        fi
        out=$(scan_file "$f"); rc=$?
        SCANNED=$((SCANNED + 1))   # only a REAL scan counts toward the invariant below
    }
    case "$rc" in
        0) ;;
        2)
            if [ -n "$out" ]; then
                if [ -n "$HITS" ]; then HITS=$(printf '%s\n%s' "$HITS" "$out"); else HITS="$out"; fi
            fi
            if [ "$WORST" -lt 2 ]; then WORST=2; fi
            ;;
        *)
            echo "secret-scan: SCAN FAILED (rc=$rc): $f" >&2
            WORST=3
            ;;
    esac
done < "$TMPLIST"

# THE INVARIANT, asserted rather than assumed (2026-08-03, round-2 review): an explicit-path
# invocation that scanned ZERO files has proved nothing, so it must not report clean. Every
# individual route to "scanned nothing, exited 0" that has been found here was a DIFFERENT
# route - an unknown flag, a nonexistent path, an empty argument list after `--`. Closing them
# one at a time is whack-a-mole; this counter closes the shape, including the next route.
# MEASURED before the fix: `secret-scan.sh --` (no paths) -> rc=0.
#
# TWO shapes, both meaning "nothing was proven":
# (a) We were given paths and reached NONE of them.
# (b) The caller passed nothing scannable at all (`--` with no paths).
if [ "$ENUMERATED" -gt 0 ] && [ "$SCANNED" -eq 0 ]; then
    echo "secret-scan: enumerated $ENUMERATED path(s) but scanned NONE - refusing to report clean" >&2
    WORST=3
elif [ "$ENUMERATED" -eq 0 ]; then
    echo "secret-scan: explicit-path invocation scanned ZERO files - refusing to report clean" >&2
    WORST=3
fi

if [ -n "$HITS" ]; then
    {
        echo "==============================================================="
        echo "BLOCKED: secret detected. Aborting."
        echo "==============================================================="
        printf '%s\n' "$HITS"
        echo ""
        echo "Action: remove the secret, ROTATE it at the provider, then retry."
        echo "If false positive: relocate the example into a non-tracked fixture."
    } >&2
fi

if [ "$WORST" -eq 3 ]; then
    echo "secret-scan: at least one input could not be proven clean - failing closed (exit 3)." >&2
fi

exit "$WORST"
