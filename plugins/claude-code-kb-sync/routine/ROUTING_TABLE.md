# Routing Table

Maps a changelog entry to the KB file(s) it affects and the official doc page to
re-fetch. This exists because `code.claude.com` publishes no per-page
`last-modified` and no dated sitemap — the changelog is the only change signal, so
it has to double as the router.

## How to use it

For each changelog bullet in the delta:

1. Match it against **Signals** below. Matching is semantic, not literal — a bullet
   saying "added `--foo` flag" routes to `CLI_REFERENCE.md` whether or not it uses
   the word "CLI".
2. Union the resulting file set across all bullets. Fetch each affected file's
   doc page **once**, no matter how many bullets routed to it.
3. A bullet matching nothing → leave it unrouted and list it in the commit body
   under `Unrouted:`. Do not guess a file.

## Table

| KB file | Doc slug | Signals |
|---|---|---|
| `OVERVIEW.md` | `overview` | Installation, supported platforms, available surfaces, model lineup, top-level capability changes |
| `CLI_REFERENCE.md` | `cli-reference` | Any `claude` flag or subcommand added/changed/removed, output modes, `--print`, headless, system-prompt flags |
| `COMMANDS.md` | `slash-commands` | Built-in `/` commands added/changed/removed, command arguments |
| `INTERACTIVE_MODE.md` | `interactive-mode` | Keyboard shortcuts, Vim mode, multiline input, bash mode, background tasks, prompt suggestions, TUI behavior |
| `SETTINGS.md` | `settings` | `settings.json` keys, config scopes, environment variables, model/effort/theme defaults |
| `PERMISSIONS.md` | `iam` | Permission modes, rule syntax, tool-specific rules, auto-mode classifier, sandboxing, managed settings |
| `MEMORY.md` | `memory` | `CLAUDE.md` behavior, auto memory, rules directory, imports |
| `HOOKS.md` | `hooks` | Hook events added/changed, handler types, matchers, exit codes, hook payload fields |
| `SKILLS.md` | `skills` | Skill frontmatter, bundled skills, invocation control, dynamic context, skill-in-subagent execution |
| `SUBAGENTS.md` | `sub-agents` | Agent frontmatter, built-in agents, agent scopes, agent memory, `Agent` tool behavior |
| `AGENT_TEAMS.md` | `agent-teams` | Multi-agent coordination, team display modes, task assignment (experimental surface) |
| `MCP.md` | `mcp` | MCP server config, transports, tool search, MCP auth, managed MCP, connector behavior |
| `PLUGINS.md` | `plugins` | Plugin structure, marketplaces, plugin install/distribution, plugin manifest schema |
| `CLAUDE_DESIGN.md` | `claude-design` | Claude Design canvas, design systems, handoff to Claude Code |
| `claude_cowork/*.md` | (Cowork docs) | Anything scoped to Claude Cowork: VM sandbox, Dispatch, desktop Code tab, artifacts, computer use |

## Do not route

- **`REMOTE_ROUTINES.md`** — a deliberate 7-line pointer stub. Routines/scheduling
  are owned by `~/Code/workshops/claude-code-course/`, not this KB. Changelog
  entries about routines, `/schedule`, or cron triggers are **unrouted by design**;
  note them in the commit body and move on. Never expand this file.
- **`INDEX.md`** — not a routing target. It is always updated as bookkeeping
  (changelog block + `Latest version`), never because a bullet routed to it.

## Ambiguity rule

A bullet that plausibly touches several files routes to **all** of them; each
fetched page is then diffed against its KB file, and pages with nothing materially
new produce no edit. Over-fetching is cheap and self-correcting. Guessing a single
wrong file is not.

A bullet whose effect on documented behavior is unclear — internal refactors,
performance work, bug fixes with no doc-visible surface — is **skipped**, not
routed. Under-reporting beats fabricating.
