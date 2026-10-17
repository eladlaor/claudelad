---
name: clip
description: Put a value straight onto the user's clipboard with a shell command, so they never copy text out of the chat. Use when the user types /clip, or says "copy it to my clipboard", "put it in my clipboard", "clipboard it", "copy that for me", "so I can paste it", or asks for a value (env var lines, a URL, a command, a config snippet, a secret from .env or 1Password) in a "copy-pastable" form. Works on macOS (pbcopy) and Linux (wl-copy / xclip / xsel). Secrets are copied without ever being printed.
argument-hint: "<what to copy, e.g. 'the two env var lines' or 'DATABASE_URL from app/.env'>"
allowed-tools: Bash, Read, Grep
metadata:
  version: "1.0.0"
  category: Productivity
---

# Clip — copy a value to the clipboard

## Summary

Resolve exactly what the user wants copied, pipe it into the platform's clipboard tool,
confirm with a **shape check** (line count / length), and tell the user it is ready to
paste. Never echo a secret into the transcript.

## STEP 0 — Pick the clipboard command

Detect once per session, in this order; fail loudly if none exists:

| Platform | Command |
|---|---|
| macOS | `pbcopy` |
| Linux, Wayland (`$WAYLAND_DISPLAY` set) | `wl-copy` |
| Linux, X11 | `xclip -selection clipboard` or `xsel --clipboard --input` |
| Over SSH, no display | No local clipboard. Say so, and offer an OSC 52 escape (`printf '\e]52;c;%s\a' "$(… \| base64 \| tr -d '\n')"`), which works in Ghostty/iTerm2/kitty. |

Call the chosen command `$CLIP` below.

## STEP 1 — Decide the exact content

- **Copy exactly what the user will paste**, and nothing else: no Markdown fences, no
  table borders, no leading or trailing blank lines.
- **Ask whether it's one string or several.** If a form takes separate name and value
  fields, it gets one value per copy. Offer to copy the next one when the user is ready.
- **For env vars that will be pasted into a `.env`-style box, use `NAME=value` lines.**
- **Strip the trailing newline from a single value** (`tr -d '\n'`). A newline inside a
  pasted secret or URL breaks it silently.

## STEP 2 — Copy it

**A non-secret literal.** Use `printf`, never `echo`, so escapes and a leading `-`
behave predictably:
```bash
printf '%s\n' 'LINE_ONE=value' 'LINE_TWO=value' | $CLIP
```

**A secret, or any value from a file or vault. It must never appear in the output.**
Read it inside the pipe; never `cat`, `echo` or `grep` it to stdout:
```bash
# one key from a .env file (value only, no trailing newline)
grep '^NAME=' /path/.env | cut -d= -f2- | tr -d '\n' | $CLIP
# from 1Password: needs a signed-in `op` session, or OP_SERVICE_ACCOUNT_TOKEN
# already exported from a secure store. Never print the token either.
op read 'op://Vault/item/field' | tr -d '\n' | $CLIP
```

## STEP 3 — Verify without revealing

Check the clipboard's **shape**, never its content:
```bash
pbpaste | wc -l        # expected line count (0 for a single value with no newline)
pbpaste | wc -c        # length, to catch an empty copy
```
On Linux use `wl-paste` or `xclip -selection clipboard -o` in place of `pbpaste`.

**An empty clipboard, or a match on 0 lines, is a failure.** Report it and stop; never
say "copied" when nothing was.

## STEP 4 — Tell the user

One line saying what is on the clipboard (by name, never by secret value) and where to
paste it. For example: "`DATABASE_URL`'s value is on your clipboard. Paste it
as the value of that variable."

## Rules

- **Read before you copy from a file.** Read it via the pipe only. A missing key is a
  failure: say which key wasn't found.
- **Never put a secret in the command text itself.** That puts it in the transcript and
  in shell history. Always pull it from its store inside the pipe.
- **The clipboard is a shared place.** After copying a secret, remind the user in one
  short clause to paste it now. Offer to clear it afterwards with `printf '' | $CLIP`.
