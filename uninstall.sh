#!/usr/bin/env bash
# uninstall.sh - remove the omid_skills kit from ~/.claude, exactly as recorded in
# ~/.claude/.kit-install.json:
#   - removes the kit's links and generated files (only if they still point into / match the kit)
#   - removes the kit's hook commands and permission rules from settings.json (your own stay),
#     restores your original status bar, removes kit settings only if still set to the kit's value
#   - removes the kit block from ~/.claude/CLAUDE.md (and puts back a CLAUDE.md shortcut if the
#     installer replaced one)
#   - lists the backups it made; restores moved-aside files only with --restore-backups
#
# Flags: --yes (no "continue?" check), --dry-run, --restore-backups
# The logic lives in install.sh (one code path for adding and removing, so they cannot drift).
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/install.sh" --uninstall "$@"
