"""CLI for the local audio transcription + diarization pipeline.

Subcommands:
  transcribe  ASR only -> caches segments.json (slow stage; run once)
  diarize     Speaker segmentation only -> caches turns.json (needs HF token)
  align       Combine cached segments + turns -> formatted transcript
  run         End-to-end: transcribe + diarize + align in one go
  relabel     Rewrite speaker names in an existing transcript via a name map
"""

import json
import logging
import sys
from dataclasses import asdict
from pathlib import Path

import click
from rich.console import Console
from rich.logging import RichHandler

from .aligner import (
    DialogueLine,
    assign_speakers,
    build_label_map,
    format_transcript,
)
from .constants import (
    DEFAULT_BEAM_SIZE,
    DEFAULT_COMPUTE_TYPE,
    DEFAULT_DEVICE,
    DEFAULT_LANGUAGE,
    DEFAULT_WHISPER_MODEL,
    PLAIN_TRANSCRIPT_FILENAME,
    SEGMENTS_CACHE_FILENAME,
    OutputFormat,
)
from .diarizer import SpeakerTurn, diarize
from .transcriber import TranscriptSegment, Word, transcribe

console = Console()
TURNS_CACHE_FILENAME = "turns.json"


def _setup_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(message)s",
        handlers=[RichHandler(console=console, rich_tracebacks=True)],
    )


def _segments_to_json(segments: list[TranscriptSegment]) -> str:
    return json.dumps([asdict(s) for s in segments], ensure_ascii=False, indent=2)


def _segments_from_json(path: Path) -> list[TranscriptSegment]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return [
        TranscriptSegment(
            start=s["start"],
            end=s["end"],
            text=s["text"],
            words=[Word(**w) for w in s["words"]],
        )
        for s in raw
    ]


def _turns_to_json(turns: list[SpeakerTurn]) -> str:
    return json.dumps([asdict(t) for t in turns], ensure_ascii=False, indent=2)


def _turns_from_json(path: Path) -> list[SpeakerTurn]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return [SpeakerTurn(**t) for t in raw]


def _resolve_outdir(audio_path: Path, output_dir: Path | None) -> Path:
    out = output_dir or (audio_path.parent / f"{audio_path.stem}_transcript")
    out.mkdir(parents=True, exist_ok=True)
    return out


@click.group()
def cli() -> None:
    """Local audio transcription with speaker diarization."""


@cli.command(name="transcribe")
@click.argument("audio", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", "-o", type=click.Path(path_type=Path), default=None)
@click.option("--model", "-m", default=DEFAULT_WHISPER_MODEL, help="Whisper model size.")
@click.option("--language", "-l", default=DEFAULT_LANGUAGE, help="Language code or 'auto'.")
@click.option("--device", default=DEFAULT_DEVICE)
@click.option("--compute-type", default=DEFAULT_COMPUTE_TYPE)
@click.option("--beam-size", default=DEFAULT_BEAM_SIZE, type=int)
@click.option("--verbose", "-v", is_flag=True)
def transcribe_cmd(audio, output_dir, model, language, device, compute_type, beam_size, verbose):
    """ASR only. Caches segments for later diarization + alignment."""
    _setup_logging(verbose)
    try:
        out = _resolve_outdir(audio, output_dir)
        segments = transcribe(
            audio, model_size=model, language=language, device=device,
            compute_type=compute_type, beam_size=beam_size,
        )
        (out / SEGMENTS_CACHE_FILENAME).write_text(
            _segments_to_json(segments), encoding="utf-8"
        )
        (out / PLAIN_TRANSCRIPT_FILENAME).write_text(
            "\n".join(s.text for s in segments) + "\n", encoding="utf-8"
        )
        console.print(
            f"\n[bold green]Transcribed[/] {len(segments)} segments -> "
            f"{out / SEGMENTS_CACHE_FILENAME}"
        )
    except Exception as exc:
        console.print(f"[red]Error:[/] {exc}")
        sys.exit(1)


@cli.command(name="diarize")
@click.argument("audio", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", "-o", type=click.Path(path_type=Path), default=None)
@click.option("--speakers", "-s", default=0, type=int, help="Exact speaker count (0=auto).")
@click.option("--device", default=DEFAULT_DEVICE)
@click.option("--verbose", "-v", is_flag=True)
def diarize_cmd(audio, output_dir, speakers, device, verbose):
    """Speaker segmentation only. Caches turns. Requires an HF token."""
    _setup_logging(verbose)
    try:
        out = _resolve_outdir(audio, output_dir)
        turns = diarize(audio, num_speakers=speakers or None, device=device)
        (out / TURNS_CACHE_FILENAME).write_text(_turns_to_json(turns), encoding="utf-8")
        distinct = sorted({t.speaker for t in turns})
        console.print(
            f"\n[bold green]Diarized[/] {len(turns)} turns, "
            f"{len(distinct)} speakers -> {out / TURNS_CACHE_FILENAME}"
        )
    except Exception as exc:
        console.print(f"[red]Error:[/] {exc}")
        sys.exit(1)


def _write_outputs(lines: list[DialogueLine], out: Path, stem: str, fmt: OutputFormat) -> Path:
    rendered = format_transcript(lines, fmt=fmt, title=stem)
    target = out / f"{stem}.{fmt}"
    target.write_text(rendered, encoding="utf-8")
    return target


@cli.command(name="align")
@click.argument("audio", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", "-o", type=click.Path(path_type=Path), default=None)
@click.option("--format", "-f", "fmt", type=click.Choice([f.value for f in OutputFormat]), default=OutputFormat.TXT.value)
@click.option("--verbose", "-v", is_flag=True)
def align_cmd(audio, output_dir, fmt, verbose):
    """Combine cached segments + turns into a formatted transcript."""
    _setup_logging(verbose)
    try:
        out = _resolve_outdir(audio, output_dir)
        seg_path = out / SEGMENTS_CACHE_FILENAME
        turn_path = out / TURNS_CACHE_FILENAME
        if not seg_path.exists():
            raise FileNotFoundError(f"align: missing {seg_path}. Run `transcribe` first.")
        if not turn_path.exists():
            raise FileNotFoundError(f"align: missing {turn_path}. Run `diarize` first.")

        segments = _segments_from_json(seg_path)
        turns = _turns_from_json(turn_path)
        label_map = build_label_map(turns)
        lines = assign_speakers(segments, turns, label_map)
        target = _write_outputs(lines, out, Path(audio).stem, OutputFormat(fmt))
        console.print(f"\n[bold green]Transcript[/] -> {target}")
        console.print(f"[dim]Speaker map: {label_map}[/]")
    except Exception as exc:
        console.print(f"[red]Error:[/] {exc}")
        sys.exit(1)


@cli.command(name="run")
@click.argument("audio", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", "-o", type=click.Path(path_type=Path), default=None)
@click.option("--model", "-m", default=DEFAULT_WHISPER_MODEL)
@click.option("--language", "-l", default=DEFAULT_LANGUAGE)
@click.option("--speakers", "-s", default=0, type=int, help="Exact speaker count (0=auto).")
@click.option("--device", default=DEFAULT_DEVICE)
@click.option("--compute-type", default=DEFAULT_COMPUTE_TYPE)
@click.option("--format", "-f", "fmt", type=click.Choice([f.value for f in OutputFormat]), default=OutputFormat.TXT.value)
@click.option("--verbose", "-v", is_flag=True)
def run_cmd(audio, output_dir, model, language, speakers, device, compute_type, fmt, verbose):
    """End-to-end: transcribe + diarize + align."""
    _setup_logging(verbose)
    try:
        out = _resolve_outdir(audio, output_dir)
        segments = transcribe(
            audio, model_size=model, language=language, device=device,
            compute_type=compute_type,
        )
        (out / SEGMENTS_CACHE_FILENAME).write_text(
            _segments_to_json(segments), encoding="utf-8"
        )
        turns = diarize(audio, num_speakers=speakers or None, device=device)
        (out / TURNS_CACHE_FILENAME).write_text(_turns_to_json(turns), encoding="utf-8")

        label_map = build_label_map(turns)
        lines = assign_speakers(segments, turns, label_map)
        target = _write_outputs(lines, out, Path(audio).stem, OutputFormat(fmt))
        console.print(f"\n[bold green]Done![/] Transcript -> {target}")
        console.print(f"[dim]Speaker map: {label_map}[/]")
    except Exception as exc:
        console.print(f"[red]Error:[/] {exc}")
        sys.exit(1)


@cli.command(name="relabel")
@click.argument("audio", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", "-o", type=click.Path(path_type=Path), default=None)
@click.option("--map", "-M", "name_map", required=True, help='e.g. "Speaker A=Amir,Speaker B=Elad"')
@click.option("--format", "-f", "fmt", type=click.Choice([f.value for f in OutputFormat]), default=OutputFormat.TXT.value)
@click.option("--verbose", "-v", is_flag=True)
def relabel_cmd(audio, output_dir, name_map, fmt, verbose):
    """Rewrite speaker names from cached data using a name map (no re-transcribe)."""
    _setup_logging(verbose)
    try:
        out = _resolve_outdir(audio, output_dir)
        segments = _segments_from_json(out / SEGMENTS_CACHE_FILENAME)
        turns = _turns_from_json(out / TURNS_CACHE_FILENAME)

        generic_map = build_label_map(turns)
        overrides = {}
        for pair in name_map.split(","):
            k, _, v = pair.partition("=")
            overrides[k.strip()] = v.strip()
        # Compose: pyannote label -> generic -> user name.
        final_map = {
            pyannote: overrides.get(generic, generic)
            for pyannote, generic in generic_map.items()
        }
        lines = assign_speakers(segments, turns, final_map)
        target = _write_outputs(lines, out, Path(audio).stem, OutputFormat(fmt))
        console.print(f"\n[bold green]Relabeled[/] transcript -> {target}")
        console.print(f"[dim]Final speaker map: {final_map}[/]")
    except Exception as exc:
        console.print(f"[red]Error:[/] {exc}")
        sys.exit(1)


if __name__ == "__main__":
    cli()
