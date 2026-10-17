---
name: permissions-master
description: Configure, audit, troubleshoot, and manage Claude Code permissions. Use when the user says "configure permissions", "set permissions", "permission rules", "allow rule", "deny rule", "audit permissions", "fix permissions", "permission mode", "settings.json permissions", "sandbox permissions", "managed settings", "permission syntax", or wants help with Claude Code tool permissions, permission modes, or security configuration.
allowed-tools: Read Write Edit Glob Grep Bash(cat *) Bash(jq *)
argument-hint: "[audit | configure | explain | troubleshoot]"
metadata:
  version: "1.0.0"
  category: "workflow-automation"
  tags: "permissions, security, settings, configuration, claude-code"
---

# Permissions Master

Claude Code's permission rule syntax, tool-specific patterns, permission modes, settings
scopes, sandboxing interaction, and managed settings.

---

## Subcommands

### `audit`
1. Read all settings files in precedence order:
   - `~/.claude/settings.json` (user global)
   - `.claude/settings.json` (project shared)
   - `.claude/settings.local.json` (project local)
2. Display all rules grouped by type (allow/ask/deny)
3. Flag conflicts: lower-precedence rules overridden by higher ones
4. Check `references/COMMON_ISSUES.md` for known problems
5. Report findings with actionable recommendations

### `configure`
1. Ask which scope: user, project, or local
2. Ask what to allow/deny/ask
3. Generate the rule syntax using the reference below
4. Read the target file, merge the new rules, write back
5. Verify

### `explain`
Explain a specific rule (exactly what it matches and doesn't), or the permission system
overview if the question is general.

### `troubleshoot`
1. Ask what behavior they expect vs. what's happening
2. Read all relevant settings files
3. Trace evaluation: deny → ask → allow (first match wins)
4. Identify the conflicting or missing rule
5. Suggest the fix

If no subcommand is given, infer from context or ask.

---

## Permission System Overview

### Evaluation Order
**deny → ask → allow**. First matching rule wins. Deny always takes precedence.

### Settings Precedence (highest to lowest)
1. **Managed** — cannot be overridden (IT-deployed)
2. **Command line arguments** — temporary overrides
3. **Local** — `.claude/settings.local.json` (personal, gitignored)
4. **Project** — `.claude/settings.json` (team-shared, committed)
5. **User** — `~/.claude/settings.json` (personal global)

Array settings (allow/ask/deny) concatenate and deduplicate across scopes.

### Permission Modes

| Mode | Description |
|------|-------------|
| `default` | Prompts on first use of each tool |
| `acceptEdits` | Auto-accepts file edit permissions for the session |
| `plan` | Read-only — analyze but not modify |
| `dontAsk` | Auto-denies unless pre-approved via allow rules |
| `bypassPermissions` | Skips all prompts (dangerous — containers/VMs only) |

Set via `"permissions": { "defaultMode": "acceptEdits" }`.

---

## Rule Syntax Quick Reference

Format: `Tool` or `Tool(specifier)`

### Bash
- `Bash` / `Bash(*)` — all commands
- `Bash(npm run build)` — exact command
- `Bash(npm run *)` — prefix wildcard (space before `*` = word boundary)
- `Bash(npm*)` — no space = no word boundary (matches `npm` and `npmx`)
- `Bash(* --version)` — suffix wildcard
- `Bash(git * main)` — middle wildcard
- Shell operators are handled — `Bash(safe-cmd *)` won't match `safe-cmd && evil-cmd`

### Read/Edit (gitignore syntax)
- `Read(./.env)` / `Read(.env)` — relative to current directory
- `Read(/src/**)` — relative to project root (recursive)
- `Read(~/Documents/*.pdf)` — home directory
- `Read(//etc/passwd)` — absolute path (double slash)
- `*` matches one directory level, `**` recursive
- `Read` (no specifier) — all file reads
- `Edit` rules apply to all built-in file modification tools

### WebFetch
- `WebFetch` — all requests
- `WebFetch(domain:example.com)` — specific domain
- `WebFetch(domain:*.example.com)` — wildcard subdomain

### MCP
- `mcp__server-name` / `MCP(server-name)` — all tools from a server
- `mcp__server-name__tool_name` / `MCP(server-name:tool.name)` — specific tool
- `mcp__server-name__*` — wildcard

### Agent
- `Agent(Explore)`, `Agent(my-custom-agent)`, `Agent(*)`

---

## Settings File Template

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "deny": [],
    "ask": [],
    "allow": [],
    "defaultMode": "default",
    "additionalDirectories": []
  }
}
```

---

## Gotchas

- `/Users/alice/file` is project-relative, NOT absolute. Use `//Users/alice/file` for absolute.
- Bash URL-constraining patterns are fragile. Prefer deny `curl`/`wget` + `WebFetch(domain:...)` allow rules.
- Sandboxing is complementary — permissions control Claude's decisions, the sandbox enforces OS-level Bash restrictions.

For common mistakes, troubleshooting patterns, and security templates, see `references/COMMON_ISSUES.md`.
