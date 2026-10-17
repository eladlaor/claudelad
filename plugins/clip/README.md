# clip

Puts a value straight onto your clipboard with a shell command, so you never select and
copy text out of the chat.

## Why

Copying from a terminal chat drags along Markdown fences, table borders, wrapped lines and
trailing newlines, and a stray newline inside a pasted token or URL breaks it silently.
Worse, asking Claude to "show me the value so I can copy it" prints a secret into the
transcript. This skill copies exactly what you will paste, and reads secrets inside the
pipe so they never appear in the output.

## What it does

1. Picks the clipboard tool for the platform: `pbcopy` (macOS), `wl-copy` (Wayland),
   `xclip` / `xsel` (X11), or an OSC 52 escape over SSH.
2. Decides the exact content: one value per copy, `NAME=value` lines for env boxes, no
   trailing newline on single values.
3. Copies it. Secrets are read from `.env` or 1Password (`op read`) inside the pipe.
4. Verifies the clipboard's **shape** (line count, length), never its content, and fails
   loudly on an empty copy.
5. Tells you what is on the clipboard by name, and offers to clear it after a secret.

## Usage

```
/clip the two env var lines
/clip DATABASE_URL from app/.env
```

Or say "copy it to my clipboard", "clipboard it", "so I can paste it".

## Requirements

- macOS: nothing extra. Linux: `wl-clipboard`, `xclip` or `xsel`.
- Optional: the 1Password CLI (`op`), signed in or with `OP_SERVICE_ACCOUNT_TOKEN` set.

## Install

```
/plugin install clip@claudelad
```
