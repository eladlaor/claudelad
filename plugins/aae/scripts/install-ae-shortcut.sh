#!/usr/bin/env bash
#
# install-ae-shortcut.sh — create an `ae` shortcut for the `agentengine` CLI.
#
# This is a SYMLINK on PATH, deliberately not a shell alias. Aliases are
# interactive-only: they live in a shell rc file and are not inherited by
# scripts or by non-interactive shells. Claude Code and Codex both run commands
# in non-interactive shells, so an alias would work when the developer types it
# and fail for every agent-issued command. A symlink works everywhere, and it
# touches no dotfile.
#
# Collision is treated as a hard stop, not something to resolve automatically:
# if `ae` already means something on this machine, shadowing it silently would
# break whatever depends on it, possibly days later.
#
# Usage: install-ae-shortcut.sh {install|uninstall|status} [--force]

set -euo pipefail

readonly SHORTCUT="ae"
readonly TARGET_CMD="agentengine"

ACTION="${1:-}"
[ $# -gt 0 ] && shift

FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    *) printf 'install-ae-shortcut: ERROR: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

die() { printf 'install-ae-shortcut: ERROR: %s\n' "$1" >&2; exit 1; }
note() { printf '%s\n' "$1"; }

# Resolve the real agentengine binary. Fail fast: installing a shortcut to a
# CLI that is not present would produce a dangling link.
find_target() {
  local path
  path="$(command -v "$TARGET_CMD" 2>/dev/null)" \
    || die "${TARGET_CMD} not found on PATH; install the CLI before adding the shortcut"
  # Follow one level so the link points at the real binary, not another link.
  if [ -L "$path" ]; then
    local resolved
    resolved="$(readlink "$path")"
    case "$resolved" in
      /*) path="$resolved" ;;
      *)  path="$(cd "$(dirname "$path")" && cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")" ;;
    esac
  fi
  printf '%s' "$path"
}

# Where the shortcut goes: alongside the binary it points at, which is by
# definition already on PATH. Avoids inventing a new PATH entry.
link_dir() { dirname "$(find_target)"; }
link_path() { printf '%s/%s' "$(link_dir)" "$SHORTCUT"; }

# True when the given path is a symlink we own (points at agentengine).
is_our_link() {
  local p="$1"
  [ -L "$p" ] || return 1
  [ "$(basename "$(readlink "$p")")" = "$TARGET_CMD" ]
}

# Shell aliases and functions BEAT a PATH symlink in interactive shells, so an
# existing `alias ae=` would silently defeat this install for the human while
# still working for agents — the worst possible split. We cannot see a running
# shell's aliases from here, so scan the usual rc files and report.
scan_rc_files() {
  local found=0 f
  for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
           "$HOME/.zprofile" "$HOME/.config/fish/config.fish"; do
    [ -f "$f" ] || continue
    if grep -qE "^[[:space:]]*(alias[[:space:]]+${SHORTCUT}=|function[[:space:]]+${SHORTCUT}[[:space:]]*(\(|\{)|${SHORTCUT}[[:space:]]*\(\))" "$f" 2>/dev/null; then
      printf '  %s\n' "$f"
      found=1
    fi
  done
  return $((1 - found))
}

do_status() {
  local target link
  target="$(find_target)"
  link="$(link_path)"

  printf '%-12s %s\n' "agentengine:" "$target"
  printf '%-12s %s\n' "shortcut:" "$link"

  if is_our_link "$link"; then
    printf '%-12s installed -> %s\n' "state:" "$(readlink "$link")"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    printf '%-12s OCCUPIED by something else\n' "state:"
  else
    printf '%-12s not installed\n' "state:"
  fi

  local resolved
  if resolved="$(command -v "$SHORTCUT" 2>/dev/null)"; then
    printf '%-12s %s\n' "'ae' is:" "$resolved"
  else
    printf "%-12s unresolved\n" "'ae' is:"
  fi

  printf '\nShell rc files defining an alias/function named %s:\n' "$SHORTCUT"
  if scan_rc_files; then
    printf '  (an alias or function overrides the PATH symlink in interactive shells)\n'
  else
    printf '  none found\n'
  fi
}

do_install() {
  local target link existing
  target="$(find_target)"
  link="$(link_path)"

  [ -x "$target" ] || die "target is not executable: ${target}"

  # Idempotent: a correct link already in place is success, not an error.
  if is_our_link "$link"; then
    note "Already installed: ${link} -> $(readlink "$link")"
    return 0
  fi

  # --- collision handling: alert, then hand the decision to the human ---
  local collision=0 detail=""

  if [ -e "$link" ] || [ -L "$link" ]; then
    collision=1
    if [ -L "$link" ]; then
      detail="${link} is a symlink to $(readlink "$link")"
    else
      detail="${link} is an existing file"
    fi
  elif existing="$(command -v "$SHORTCUT" 2>/dev/null)"; then
    # Not in our directory, but `ae` resolves to something else on PATH.
    collision=1
    detail="'${SHORTCUT}' already resolves to ${existing}"
  fi

  local rc_hits=""
  if rc_hits="$(scan_rc_files)"; then
    collision=1
    detail="${detail:+${detail}; }an alias or function named '${SHORTCUT}' is defined in a shell rc file"
  fi

  if [ "$collision" -eq 1 ]; then
    printf '\n'
    printf 'COLLISION: the name %s is already in use on this machine.\n' "$SHORTCUT"
    printf '  %s\n' "$detail"
    [ -n "$rc_hits" ] && printf '%s\n' "$rc_hits"
    printf '\n'
    printf 'Installing anyway may shadow a tool you or another program depends on.\n'
    printf 'An alias or shell function also takes precedence over this symlink in\n'
    printf 'interactive shells, so the shortcut could work for agents and not for you.\n'
    printf '\n'

    if [ "$FORCE" -eq 1 ]; then
      note "--force given; proceeding despite the collision."
    elif [ -t 0 ] && [ -t 1 ]; then
      printf 'Create the shortcut anyway? [y/N] '
      local reply
      IFS= read -r reply || reply=""
      # Some terminals deliver a trailing CR; without stripping it, a plain "y"
      # arrives as "y\r" and falls through to the abort branch.
      reply="${reply%$'\r'}"
      case "$reply" in
        [yY]|[yY][eE][sS]) note "Proceeding." ;;
        *) die "aborted by user; nothing was changed" ;;
      esac
    else
      die "collision detected and no terminal available to ask; re-run interactively, or pass --force if you are certain"
    fi
  fi

  # Never clobber a real file without having passed the gate above.
  if [ -e "$link" ] || [ -L "$link" ]; then
    rm -f "$link" || die "could not remove existing ${link}"
  fi

  ln -s "$target" "$link" || die "could not create symlink ${link}"
  note "Installed: ${link} -> ${target}"
  note "Run '${SHORTCUT} --help' in a new shell to confirm."
}

do_uninstall() {
  local link
  link="$(link_path)"

  # Refuse to delete anything that is not demonstrably our own symlink.
  if is_our_link "$link"; then
    rm -f "$link"
    note "Removed ${link}"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    die "${link} exists but is not a symlink to ${TARGET_CMD}; refusing to remove it"
  else
    note "Not installed (no ${link})"
  fi
}

case "$ACTION" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  *) die "usage: install-ae-shortcut.sh {install|uninstall|status} [--force]" ;;
esac
