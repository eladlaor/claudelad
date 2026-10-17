# permissions-master

Configures, audits, and troubleshoots Claude Code permissions.

## Why

Permission rules fail quietly. A pattern with the wrong path anchor, a `Bash` rule that
doesn't match the way the command is actually invoked, or a project setting overridden by a
user setting all look correct and simply don't apply, and the symptom is either a stream of
prompts or a tool that is allowed when you thought it was blocked. This skill carries the
rule syntax, tool-specific patterns, permission modes and settings precedence, plus a
reference of the common issues, so it can explain why a rule isn't matching and fix it.

## Modes

```
/permissions-master audit         # review current allow/deny/ask rules across settings files
/permissions-master configure     # add or change rules for a goal you describe
/permissions-master explain       # explain syntax, modes, or precedence
/permissions-master troubleshoot  # find why a rule isn't taking effect
```

Or say "configure permissions", "audit permissions", "why is this rule not working".

## Install

```
/plugin install permissions-master@claudelad
```
