"""ASR stage: faster-whisper transcription with word-level timestamps."""

import logging
from dataclasses import dataclass
from pathlib import Path

from faster_whisper import WhisperModel

from .constants import (
    AUTO_LANGUAGE_SENTINEL,
    DEFAULT_BEAM_SIZE,
    DEFAULT_COMPUTE_TYPE,
    DEFAULT_DEVICE,
    DEFAULT_VAD_FILTER,
    DEFAULT_WHISPER_MODEL,
)

logger = logging.getLogger(__name__)


@dataclass
class Word:
    """A single transcribed word with its time span."""

    start: float
    end: float
    text: str


@dataclass
class TranscriptSegment:
    """A contiguous transcribed segment with word-level timing."""

    start: float
    end: float
    text: str
    words: list[Word]


def transcribe(
    audio_path: Path,
    model_size: str = DEFAULT_WHISPER_MODEL,
    language: str | None = None,
    device: str = DEFAULT_DEVICE,
    compute_type: str = DEFAULT_COMPUTE_TYPE,
    beam_size: int = DEFAULT_BEAM_SIZE,
    vad_filter: bool = DEFAULT_VAD_FILTER,
) -> list[TranscriptSegment]:
    """Transcribe an audio file to text segments with word timestamps.

    Args:
        audio_path: Path to the input audio file.
        model_size: faster-whisper model id (e.g. "large-v3", "medium").
        language: ISO language code (e.g. "he"). None or "auto" -> auto-detect.
        device: "cpu" or "cuda".
        compute_type: e.g. "int8" (CPU), "float16" (GPU).
        beam_size: Decoding beam width.
        vad_filter: Whether to apply voice-activity-detection filtering.

    Returns:
        Ordered list of transcript segments.

    Raises:
        FileNotFoundError: If the audio file does not exist.
        RuntimeError: If transcription produces no segments or fails.
    """
    if not audio_path.exists():
        raise FileNotFoundError(f"transcribe: audio file not found at '{audio_path}'")

    lang = None if not language or language == AUTO_LANGUAGE_SENTINEL else language

    try:
        logger.info(
            "Loading Whisper model",
            extra={"model": model_size, "device": device, "compute_type": compute_type},
        )
        model = WhisperModel(model_size, device=device, compute_type=compute_type)

        logger.info(
            "Starting transcription",
            extra={"audio_path": str(audio_path), "language": lang or "auto"},
        )
        segments_iter, info = model.transcribe(
            str(audio_path),
            language=lang,
            beam_size=beam_size,
            word_timestamps=True,
            vad_filter=vad_filter,
        )

        logger.info(
            "Transcription stream opened",
            extra={
                "detected_language": info.language,
                "language_probability": round(info.language_probability, 3),
                "duration_sec": round(info.duration, 1),
            },
        )

        segments: list[TranscriptSegment] = []
        for seg in segments_iter:
            words = [
                Word(start=w.start, end=w.end, text=w.word)
                for w in (seg.words or [])
                if w.start is not None and w.end is not None
            ]
            segments.append(
                TranscriptSegment(
                    start=seg.start, end=seg.end, text=seg.text.strip(), words=words
                )
            )
            logger.info(
                "Segment transcribed",
                extra={"start": round(seg.start, 1), "end": round(seg.end, 1)},
            )

        if not segments:
            raise RuntimeError("transcribe: no segments produced from audio")

        logger.info("Transcription complete", extra={"segment_count": len(segments)})
        return segments

    except Exception as exc:
        logger.error(
            "Transcription failed",
            extra={"audio_path": str(audio_path), "error": str(exc)},
        )
        raise
