#!/bin/bash
# SessionStart hook: fast-forward the local Claude Code KB repo so the session
# sees whatever the cloud routine pushed since last time.
#
# Design constraints:
#   - Never block session startup. The pull is detached; this script returns
#     immediately after spawning it.
#   - Never merge. --ff-only means a divergent local tree fails loudly in the
#     log instead of silently auto-merging.
#   - Never clobber in-flight local edits. If the KB has uncommitted changes,
#     skip entirely.
#
# Configure the KB location with CLAUDE_CODE_KB_REPO; defaults below.

set -uo pipefail

KB_REPO="${CLAUDE_CODE_KB_REPO:-$HOME/Code/generic-docs}"
KB_SUBDIR="${CLAUDE_CODE_KB_SUBDIR:-claude_code}"
LOG_FILE="${CLAUDE_CODE_KB_LOG:-$HOME/.claude/kb-sync-pull.log}"

# Always emit valid hook JSON, whatever happens below.
emit_and_exit() { echo '{}'; exit 0; }

# Not a git repo (or not present) -> nothing to do, stay silent.
[ -d "$KB_REPO/.git" ] || emit_and_exit

# Spawn the actual work detached so session startup never waits on the network.
(
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

  log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE" 2>/dev/null; }

  # Refuse to touch a dirty KB — the user may be mid-edit.
  if ! git -C "$KB_REPO" diff --quiet -- "$KB_SUBDIR" 2>/dev/null ||
     ! git -C "$KB_REPO" diff --cached --quiet -- "$KB_SUBDIR" 2>/dev/null; then
    log "SKIP: uncommitted changes in $KB_SUBDIR/"
    exit 0
  fi

  # --ff-only: a diverged local branch is an error we want recorded, not merged.
  OUTPUT=$(git -C "$KB_REPO" pull --ff-only --quiet 2>&1)
  RC=$?
  if [ "$RC" -eq 0 ]; then
    [ -n "$OUTPUT" ] && log "OK: $OUTPUT"
  else
    log "FAIL (rc=$RC): ${OUTPUT:-no output}"
  fi
) >/dev/null 2>&1 &

# Detach the child so it survives this script and cannot hold up startup.
disown 2>/dev/null || true

emit_and_exit
