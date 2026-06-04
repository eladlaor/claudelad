# worktree-manager

Manage persistent git worktrees for parallel Claude Code development on separate branches.

## Why This Plugin?

Claude Code has a built-in `EnterWorktree` tool that creates temporary worktrees for agent isolation. But these are **session-scoped**: they're created inside `.claude/`, disappear when the session ends, and aren't designed for humans to work in alongside the AI.

If your workflow involves parallel branches (you working on feature-auth while Claude handles feature-tests on a separate branch, across multiple sessions) you need worktrees that:

- **Persist across sessions**: survive restarts, don't auto-delete
- **Live as sibling directories**: visible, navigable, `cd`-able from your terminal
- **Auto-detect context**: Claude knows when it's in a worktree and which branch it's on
- **Merge back cleanly**: conflict-aware merge with dependency ordering and verification

This plugin provides all of that.

## Install

```
/plugin install worktree-manager@claudelad
```

## Setup

No setup required. Works immediately after install.

## Usage

### Worktree management

```
/worktree-manager:worktree <command> [branch-name]
```

| Command | What it does |
|---------|-------------|
| `/worktree-manager:worktree create feature-auth` | Create a new worktree for a branch |
| `/worktree-manager:worktree list` | List all active worktrees |
| `/worktree-manager:worktree status` | Show status of all worktrees (uncommitted changes, etc.) |
| `/worktree-manager:worktree remove feature-auth` | Remove a worktree (warns if uncommitted changes) |

### Merge all worktrees

```
/worktree-manager:merge
```

Merges all worktree branches back with dependency-ordered merges, conflict resolution, auto-detected verification, and cleanup.

## How It Works

Worktrees are created as sibling directories: `../<project>-<branch>`. For example, if your main repo is at `~/Code/myapp`, a worktree for `feature-auth` lives at `~/Code/myapp-feature-auth`. Each worktree is a full working directory sharing the same git history. A `SessionStart` hook automatically detects when you're inside a worktree and injects context about the branch, main repo path, and sibling worktrees (up to 5 shown; additional worktrees are summarized as "and more...").

## Uninstall

```
/plugin uninstall worktree-manager@claudelad
```
