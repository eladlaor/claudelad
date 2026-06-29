---
name: transcribe-conversation
description: >-
  Transcribe a recording of a conversation or talk into a clearly documented,
  speaker-labeled transcript, fully locally. Uses faster-whisper for ASR
  (Hebrew by default, 90+ languages) and pyannote for speaker diarization.
  Use when the user says "transcribe this recording", "transcribe conversation",
  "transcribe the talk", "diarize this audio", "who said what", "make a
  transcript with speakers", or hands over an audio file and wants a labeled
  dialogue transcript. No audio leaves the machine.
argument-hint: "<audio-file> [--speakers N] [--language he|en|auto] [--format txt|md|srt] [--model large-v3|medium]"
allowed-tools:
  - Bash(cd * && uv run audio-transcribe *)
  - Bash(uv run audio-transcribe *)
  - Bash(uv sync *)
  - Bash(ffprobe *)
  - Bash(find * -type f*)
  - Bash(ls *)
  - Bash(test *)
  - Read
---

# Transcribe Conversation (local ASR + speaker diarization)

Produce a clearly documented, speaker-labeled transcript of a recording, entirely on the
local machine. Two stages: **ASR** (faster-whisper) turns speech into text with word-level
timestamps; **diarization** (pyannote) segments the audio by speaker. The two are aligned so
each line is attributed to a speaker.

The user's request is: $ARGUMENTS

## Prerequisites

1. **ffmpeg** on PATH (audio decoding). Check: `ffprobe -version`.
2. **HuggingFace token** for diarization (ASR alone needs none). The pipeline reads it from
   `$HF_TOKEN` (or `$HUGGINGFACE_TOKEN` / `$HF_API_TOKEN`). The user must also accept the model
   gates once. See `docs/SETUP.md` in this plugin. **Never ask the user to paste the token into
   chat** — instruct them to export it in their shell instead.
3. Dependencies are managed by `uv sync` (first run downloads torch + models; large-v3 is ~3GB).

## Resolve the plugin directory

All commands run from the installed plugin dir:

```bash
PLUGIN_DIR="$(find ~/.claude/plugins -path '*/audio-transcribe/pyproject.toml' -type f 2>/dev/null | head -1 | xargs dirname)"
cd "$PLUGIN_DIR" && uv sync
```

If not found under `~/.claude/plugins`, fall back to the marketplace source:
`~/Code/flagship_projects/claudelad/plugins/audio-transcribe`.

## Procedure

### 1. Inspect the audio first
```bash
ffprobe -v error -show_entries format=duration -show_entries stream=channels,sample_rate -of default=noprint_wrappers=1 "<audio>"
```
Report duration to the user — on CPU, large-v3 runs roughly real-time to a few× slower, so a
long recording takes a while. If there's no GPU, mention the expected wait.

### 2. Confirm the HF token is set (for diarization)
```bash
test -n "$HF_TOKEN" && echo "token set" || echo "no token"
```
If absent, point the user to `docs/SETUP.md` and have them export it. Do **not** proceed to
diarization without it — but you CAN run the transcription stage meanwhile (step 3a).

### 3. Run the pipeline

Prefer the **staged** approach for long recordings (cache survives, ASR runs once, relabeling is
cheap). Use `run` for short clips when the token is already set.

**3a. Transcribe (slow stage, no token needed):**
```bash
cd "$PLUGIN_DIR" && uv run audio-transcribe transcribe "<audio>" --language he
```
For very long CPU jobs, launch this as a background task and poll the output dir.

**3b. Diarize (needs token; pass the known speaker count):**
```bash
cd "$PLUGIN_DIR" && uv run audio-transcribe diarize "<audio>" --speakers 2
```
For a known two-person conversation always pass `--speakers 2` — it constrains clustering and
improves accuracy.

**3c. Align into a documented transcript:**
```bash
cd "$PLUGIN_DIR" && uv run audio-transcribe align "<audio>" --format md
```

**End-to-end (short clips):**
```bash
cd "$PLUGIN_DIR" && uv run audio-transcribe run "<audio>" --speakers 2 --language he --format md
```

Output goes to `<audio-dir>/<audio-stem>_transcript/` (override with `-o`). It contains
`segments.json`, `turns.json`, `transcript_plain.txt`, and the formatted transcript.

### 4. Name the speakers

Diarization emits generic labels (`Speaker A`, `Speaker B`, ...) ordered by who speaks first.
You cannot know which physical voice is which person from audio alone. Read the opening lines of
the transcript, infer or ASK the user who opens the conversation, then relabel **without
re-transcribing**:

```bash
cd "$PLUGIN_DIR" && uv run audio-transcribe relabel "<audio>" --map "Speaker A=Amir,Speaker B=Elad" --format md
```

### 5. Deliver

Read the final transcript and present it (or its path) to the user. For Hebrew, the `md` format
renders cleanly with speaker headers and timestamps.

## Options reference

| Option | Applies to | Default | Notes |
|--------|-----------|---------|-------|
| `--language` / `-l` | transcribe, run | `he` | ISO code or `auto` |
| `--speakers` / `-s` | diarize, run | `0` (auto) | Pass exact N for known conversations |
| `--model` / `-m` | transcribe, run | `large-v3` | `medium` is faster, less accurate |
| `--format` / `-f` | align, run, relabel | `txt` | `txt`, `md`, `srt` |
| `--device` | all | `cpu` | `cuda` if a GPU is available |
| `--compute-type` | transcribe, run | `int8` | `float16` on GPU |
| `--output-dir` / `-o` | all | `<stem>_transcript/` | Where cache + transcript land |

## Troubleshooting

- **`no HuggingFace token found`**: export `HF_TOKEN` (see `docs/SETUP.md`); restart the shell/session.
- **`pipeline failed to load` / 401**: the model gate isn't accepted on the user's HF account.
  Accept it at the two URLs in `docs/SETUP.md`.
- **Wrong number of speakers detected**: pass `--speakers N` explicitly.
- **Slow on CPU**: use `--model medium`, or run `transcribe` as a background task.
- **Names swapped**: re-run `relabel` with the corrected `--map`.
