# audio-transcribe

Transcribe recordings of conversations or talks into clearly documented, speaker-labeled
transcripts — **fully locally**. No audio leaves the machine.

- **ASR**: [faster-whisper](https://github.com/SYSTRAN/faster-whisper) (CTranslate2). Hebrew by
  default; 90+ languages supported. Word-level timestamps.
- **Diarization**: [pyannote.audio](https://github.com/pyannote/pyannote-audio) speaker
  segmentation, aligned to the transcript by word-level temporal voting.
- **Output**: `txt`, `md`, or `srt`, plus cached `segments.json` / `turns.json` so the slow ASR
  stage runs only once and speaker names can be changed cheaply.

## Skill

`/audio-transcribe:transcribe-conversation <audio-file> [options]`

The skill inspects the audio, runs ASR + diarization, aligns them, and lets you name the speakers
after the fact (`relabel`) without re-transcribing.

## Requirements

- `ffmpeg` on PATH
- A HuggingFace token for diarization (ASR alone needs none) — see [`docs/SETUP.md`](docs/SETUP.md)
- `uv` (dependencies are installed via `uv sync`; first run downloads ~3GB of models)
- Python 3.10–3.12 (pyannote + torch CPU wheels pin `<3.13`)

## CLI

```bash
# End-to-end (short clips)
uv run audio-transcribe run AUDIO --speakers 2 --language he --format md

# Staged (long recordings): cache survives between stages
uv run audio-transcribe transcribe AUDIO --language he      # slow, no token
uv run audio-transcribe diarize    AUDIO --speakers 2        # needs HF token
uv run audio-transcribe align      AUDIO --format md
uv run audio-transcribe relabel    AUDIO --map "Speaker A=Amir,Speaker B=Elad" --format md
```

Output lands in `<audio-dir>/<audio-stem>_transcript/`.

## Why local

The recordings are private. This pipeline keeps audio and transcripts on your machine; the only
network calls are one-time model downloads from HuggingFace.
