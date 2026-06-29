"""Diarization stage: pyannote speaker segmentation."""

import logging
import os
from dataclasses import dataclass
from pathlib import Path

import torch
from pyannote.audio import Pipeline

from .constants import DIARIZATION_MODEL, HF_TOKEN_ENV_VARS

logger = logging.getLogger(__name__)


@dataclass
class SpeakerTurn:
    """A time span attributed to a single pyannote speaker label."""

    start: float
    end: float
    speaker: str  # e.g. "SPEAKER_00"


def _resolve_hf_token() -> str:
    """Read the HuggingFace token from any of the supported env vars.

    Raises:
        RuntimeError: If no token is found in the environment.
    """
    for var in HF_TOKEN_ENV_VARS:
        token = os.environ.get(var)
        if token:
            return token
    raise RuntimeError(
        "diarize: no HuggingFace token found. Set one of "
        f"{', '.join(HF_TOKEN_ENV_VARS)} and accept the model gate at "
        f"https://huggingface.co/{DIARIZATION_MODEL}"
    )


def diarize(
    audio_path: Path,
    num_speakers: int | None = None,
    device: str = "cpu",
) -> list[SpeakerTurn]:
    """Run speaker diarization over an audio file.

    Args:
        audio_path: Path to the input audio file.
        num_speakers: Exact speaker-count hint. Pass for a known N-person
            conversation to constrain clustering; None lets pyannote decide.
        device: "cpu" or "cuda".

    Returns:
        Ordered list of speaker turns.

    Raises:
        FileNotFoundError: If the audio file does not exist.
        RuntimeError: If the token is missing or diarization fails.
    """
    if not audio_path.exists():
        raise FileNotFoundError(f"diarize: audio file not found at '{audio_path}'")

    hf_token = _resolve_hf_token()

    try:
        logger.info("Loading diarization pipeline", extra={"model": DIARIZATION_MODEL})
        # pyannote v4 uses `token`; v3 used `use_auth_token`. Try v4 first.
        try:
            pipeline = Pipeline.from_pretrained(DIARIZATION_MODEL, token=hf_token)
        except TypeError:
            pipeline = Pipeline.from_pretrained(
                DIARIZATION_MODEL, use_auth_token=hf_token
            )

        if pipeline is None:
            raise RuntimeError(
                "diarize: pipeline failed to load. Confirm the model gate is "
                f"accepted for {DIARIZATION_MODEL} on your HF account."
            )
        pipeline.to(torch.device(device))

        logger.info(
            "Starting diarization",
            extra={"audio_path": str(audio_path), "num_speakers": num_speakers},
        )
        kwargs = {"num_speakers": num_speakers} if num_speakers else {}
        annotation = pipeline(str(audio_path), **kwargs)

        turns = [
            SpeakerTurn(start=segment.start, end=segment.end, speaker=speaker)
            for segment, _, speaker in annotation.itertracks(yield_label=True)
        ]

        if not turns:
            raise RuntimeError("diarize: no speaker turns produced")

        distinct = sorted({t.speaker for t in turns})
        logger.info(
            "Diarization complete",
            extra={"turn_count": len(turns), "speakers": distinct},
        )
        return turns

    except Exception as exc:
        logger.error(
            "Diarization failed",
            extra={"audio_path": str(audio_path), "error": str(exc)},
        )
        raise
