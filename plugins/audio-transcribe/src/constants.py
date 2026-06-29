"""App-wide immutable constants for the transcription pipeline."""

from enum import StrEnum

# --- ASR (faster-whisper) ---
DEFAULT_WHISPER_MODEL: str = "large-v3"
DEFAULT_LANGUAGE: str = "he"  # Hebrew; pass None/"auto" for auto-detect
DEFAULT_DEVICE: str = "cpu"
DEFAULT_COMPUTE_TYPE: str = "int8"  # fastest CPU path; minimal accuracy loss
DEFAULT_BEAM_SIZE: int = 5
DEFAULT_VAD_FILTER: bool = True  # trim long silences -> faster, cleaner segments

# --- Diarization (pyannote) ---
# pyannote v4's current pipeline. Has its own HF gate (separate from 3.x).
DIARIZATION_MODEL: str = "pyannote/speaker-diarization-community-1"
SEGMENTATION_MODEL: str = "pyannote/segmentation-3.0"
HF_TOKEN_ENV_VARS: tuple[str, ...] = ("HF_TOKEN", "HUGGINGFACE_TOKEN", "HF_API_TOKEN")

# --- Speaker labeling ---
UNKNOWN_SPEAKER_LABEL: str = "Unknown"
# Generic ordered labels assigned by first appearance until the user names them.
GENERIC_SPEAKER_LABELS: tuple[str, ...] = (
    "Speaker A",
    "Speaker B",
    "Speaker C",
    "Speaker D",
    "Speaker E",
    "Speaker F",
)

# --- Output ---
SEGMENTS_CACHE_FILENAME: str = "segments.json"
PLAIN_TRANSCRIPT_FILENAME: str = "transcript_plain.txt"


class OutputFormat(StrEnum):
    """Supported transcript output formats."""

    TXT = "txt"
    SRT = "srt"
    MD = "md"


# Auto-detect sentinel accepted on the CLI for the --language option.
AUTO_LANGUAGE_SENTINEL: str = "auto"
