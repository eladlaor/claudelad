"""Alignment stage: attribute transcript segments to speakers, format output."""

import logging
from dataclasses import dataclass

from .constants import GENERIC_SPEAKER_LABELS, UNKNOWN_SPEAKER_LABEL, OutputFormat
from .diarizer import SpeakerTurn
from .transcriber import TranscriptSegment, Word

logger = logging.getLogger(__name__)


@dataclass
class DialogueLine:
    """A transcript segment attributed to a named speaker."""

    start: float
    end: float
    speaker: str  # display name
    text: str


def build_label_map(turns: list[SpeakerTurn]) -> dict[str, str]:
    """Map pyannote labels to generic ordered names by first appearance.

    Args:
        turns: Diarization speaker turns.

    Returns:
        Mapping from pyannote label (SPEAKER_00, ...) to display name.
    """
    seen: list[str] = []
    for t in sorted(turns, key=lambda x: x.start):
        if t.speaker not in seen:
            seen.append(t.speaker)
    return {
        spk: (GENERIC_SPEAKER_LABELS[i] if i < len(GENERIC_SPEAKER_LABELS) else spk)
        for i, spk in enumerate(seen)
    }


def _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    """Return the length of the temporal overlap between two spans (>= 0)."""
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def _dominant_speaker(
    span_start: float, span_end: float, turns: list[SpeakerTurn]
) -> str | None:
    """Find the pyannote speaker whose turn overlaps a span the most."""
    best_speaker: str | None = None
    best_overlap = 0.0
    for turn in turns:
        ov = _overlap(span_start, span_end, turn.start, turn.end)
        if ov > best_overlap:
            best_overlap = ov
            best_speaker = turn.speaker
    return best_speaker


def assign_speakers(
    segments: list[TranscriptSegment],
    turns: list[SpeakerTurn],
    label_map: dict[str, str],
) -> list[DialogueLine]:
    """Attribute each transcript segment to a speaker via word-level voting.

    Each word is assigned to the speaker turn it overlaps most; the segment
    inherits the majority speaker across its words. Consecutive segments by the
    same speaker are merged into one dialogue line.

    Args:
        segments: Transcribed segments with word timing.
        turns: Speaker turns from diarization.
        label_map: Maps pyannote labels to display names.

    Returns:
        Ordered, speaker-merged dialogue lines.

    Raises:
        ValueError: If inputs are empty.
    """
    if not segments:
        raise ValueError("assign_speakers: no transcript segments provided")
    if not turns:
        raise ValueError("assign_speakers: no speaker turns provided")

    try:
        raw_lines: list[DialogueLine] = []
        for seg in segments:
            votes: dict[str, float] = {}
            sources: list[Word] = seg.words or [
                Word(start=seg.start, end=seg.end, text=seg.text)
            ]
            for w in sources:
                spk = _dominant_speaker(w.start, w.end, turns)
                if spk is not None:
                    votes[spk] = votes.get(spk, 0.0) + (w.end - w.start)

            if votes:
                pyannote_label = max(votes, key=votes.get)
                display = label_map.get(pyannote_label, UNKNOWN_SPEAKER_LABEL)
            else:
                display = UNKNOWN_SPEAKER_LABEL

            raw_lines.append(
                DialogueLine(
                    start=seg.start, end=seg.end, speaker=display, text=seg.text
                )
            )

        merged = _merge_consecutive(raw_lines)
        logger.info(
            "Speaker assignment complete",
            extra={"raw_lines": len(raw_lines), "merged_lines": len(merged)},
        )
        return merged

    except Exception as exc:
        logger.error("Speaker assignment failed", extra={"error": str(exc)})
        raise


def _merge_consecutive(lines: list[DialogueLine]) -> list[DialogueLine]:
    """Collapse adjacent lines spoken by the same speaker into one line."""
    if not lines:
        return []
    merged: list[DialogueLine] = [
        DialogueLine(lines[0].start, lines[0].end, lines[0].speaker, lines[0].text)
    ]
    for line in lines[1:]:
        last = merged[-1]
        if line.speaker == last.speaker:
            last.end = line.end
            last.text = f"{last.text} {line.text}".strip()
        else:
            merged.append(
                DialogueLine(line.start, line.end, line.speaker, line.text)
            )
    return merged


def _fmt_clock(seconds: float) -> str:
    """Format seconds as HH:MM:SS."""
    total = int(round(seconds))
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def _fmt_srt_time(seconds: float) -> str:
    """Format seconds as SRT timestamp HH:MM:SS,mmm."""
    millis = int(round(seconds * 1000))
    h, rem = divmod(millis, 3_600_000)
    m, rem = divmod(rem, 60_000)
    s, ms = divmod(rem, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def format_transcript(
    lines: list[DialogueLine],
    fmt: OutputFormat = OutputFormat.TXT,
    title: str | None = None,
) -> str:
    """Render dialogue lines in the requested format.

    Args:
        lines: Speaker-attributed dialogue lines.
        fmt: Output format (txt, srt, md).
        title: Optional document title (used by md).

    Returns:
        Rendered transcript string.

    Raises:
        ValueError: If there are no lines to render.
    """
    if not lines:
        raise ValueError("format_transcript: no dialogue lines to render")

    if fmt is OutputFormat.SRT:
        blocks = []
        for i, line in enumerate(lines, start=1):
            blocks.append(
                f"{i}\n"
                f"{_fmt_srt_time(line.start)} --> {_fmt_srt_time(line.end)}\n"
                f"{line.speaker}: {line.text}\n"
            )
        return "\n".join(blocks)

    if fmt is OutputFormat.MD:
        header = f"# {title}\n\n" if title else ""
        body = "\n\n".join(
            f"**{line.speaker}** _[{_fmt_clock(line.start)}]_\n\n{line.text}"
            for line in lines
        )
        return header + body + "\n"

    # TXT (default)
    body = "\n\n".join(
        f"[{_fmt_clock(line.start)}] {line.speaker}: {line.text}" for line in lines
    )
    return body + "\n"
