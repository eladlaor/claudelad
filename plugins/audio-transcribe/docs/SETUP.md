# Setup: HuggingFace token for diarization

Speaker diarization uses the gated `pyannote` models. ASR (transcription) needs **no** token;
only the speaker-labeling stage does.

## 1. Create a token

1. Go to https://huggingface.co/settings/tokens
2. **Create new token** -> type **Read** -> name it (e.g. `diarization`) -> **Create**
3. Copy the value (starts with `hf_...`)

## 2. Accept the model gates (one time)

Visit each and click **"Agree and access repository"** while logged in:

- https://huggingface.co/pyannote/speaker-diarization-3.1
- https://huggingface.co/pyannote/segmentation-3.0

## 3. Export the token in your shell

The pipeline reads `HF_TOKEN` (or `HUGGINGFACE_TOKEN` / `HF_API_TOKEN`) from the environment.
**Never paste the token into a chat.** Add it to your shell profile:

```bash
echo 'export HF_TOKEN=hf_your_token_here' >> ~/.bashrc
export HF_TOKEN=hf_your_token_here   # current shell
```

Verify:

```bash
test -n "$HF_TOKEN" && echo "token set" || echo "no token"
```

## Notes

- The token is read at runtime from the environment; it is never written to disk by this plugin.
- ffmpeg must be installed and on PATH for audio decoding.
- First run downloads the Whisper model (large-v3 ~3GB) and the pyannote models; subsequent runs
  use the local cache.
