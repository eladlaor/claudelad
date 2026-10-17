# Common Permission Issues & Troubleshooting

## Table of Contents
- [Summary](#summary)
- [Audit Checklist](#audit-checklist)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting Patterns](#troubleshooting-patterns)
- [Security Templates](#security-templates)

---

## Summary

Common permission configuration mistakes, audit checks, and starter security templates for Claude Code.

---

## Audit Checklist

When auditing permissions, check for:

1. **Sensitive file exposure** — No deny rules for `.env`, `.env.*`, `secrets/`, credentials
2. **Overly broad Bash allows** — `Bash(*)` in allow without sandbox enabled
3. **Missing deny for network tools** — `curl`, `wget` allowed without URL constraints
4. **Shadowed allow rules** — Allow rule that can never match because a deny rule covers it
5. **Wrong path prefix** — Using `/path` (project-relative) when meaning `//path` (absolute)
6. **Unsafe mode** — `bypassPermissions` enabled outside containers/VMs
7. **Scope confusion** — Rule in user settings when it should be project-scoped (or vice versa)
8. **Missing MCP permissions** — MCP servers configured but no permission rules for their tools

---

## Common Mistakes

### 1. Absolute path confusion
```json
// WRONG — relative to project root, not filesystem root
"deny": ["Read(/etc/passwd)"]

// CORRECT — double slash for absolute paths
"deny": ["Read(//etc/passwd)"]
```

### 2. Wildcard word boundary
```json
// "Bash(ls *)" — matches "ls -la" but NOT "lsof" (space enforces word boundary)
// "Bash(ls*)"  — matches BOTH "ls -la" AND "lsof" (no boundary)
```

### 3. Fragile URL constraints
```json
// FRAGILE — won't catch "curl -X GET http://...", "curl https://...", etc.
"allow": ["Bash(curl http://github.com/ *)"]

// BETTER — deny network tools, use WebFetch for allowed domains
"deny": ["Bash(curl *)", "Bash(wget *)"],
"allow": ["WebFetch(domain:github.com)"]
```

### 4. Single vs recursive glob
```json
// "Read(/src/*)"  — only direct children of src/
// "Read(/src/**)" — all files recursively under src/
```

### 5. Deny always wins
```json
// deny is evaluated first — this allow rule will NEVER match
"deny": ["Read(.env)"],
"allow": ["Read(.env)"]
```

---

## Troubleshooting Patterns

### "Claude keeps asking for permission"
- Verify the rule is in `allow` (not `ask`)
- Check the rule syntax matches exactly what Claude attempts
- Look for a deny rule at a higher-precedence scope overriding it
- Run `/permissions` to see all active rules

### "Claude can do something it shouldn't"
- Check all settings files for conflicting allow rules
- Arrays merge across scopes (concatenate + deduplicate), so an allow in any scope takes effect unless a deny covers it
- Deny rules always win regardless of which scope they're in

### "Permission mode isn't working"
- `defaultMode` must be inside the `permissions` object, not at root level
- Check spelling: `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan`, `default`
- Managed settings may override your mode
- `bypassPermissions` can be disabled via managed `disableBypassPermissionsMode: "disable"`

### "MCP tools always prompt"
- Format: `mcp__servername__toolname` or `MCP(servername:toolname)`
- Server name must match exactly what's configured in Claude Code
- Use `mcp__servername` (no tool suffix) to allow all tools from a server

---

## Security Templates

### Base deny rules (recommended for all setups)
```json
"deny": [
  "Read(./.env)",
  "Read(./.env.*)",
  "Read(./secrets/**)",
  "Read(~/.aws/**)",
  "Read(~/.ssh/**)",
  "Bash(curl *)",
  "Bash(wget *)",
  "Bash(rm -rf *)"
]
```

### Team project settings (.claude/settings.json)
Extends the base deny rules with team-specific allows:
```json
{
  "permissions": {
    "deny": ["...base deny rules above..."],
    "allow": [
      "Bash(npm run *)",
      "Bash(npm test *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git status)",
      "Read(/src/**)",
      "Edit(/src/**)"
    ],
    "ask": [
      "Bash(git push *)",
      "Bash(git commit *)"
    ],
    "defaultMode": "acceptEdits"
  }
}
```

### Managed settings (organization-wide)
Add to managed settings file to enforce org policy:
```json
{
  "permissions": {
    "deny": ["...base deny rules above..."],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": false
}
```
