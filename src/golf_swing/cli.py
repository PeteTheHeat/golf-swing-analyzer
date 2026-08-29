from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from golf_swing.media import MediaError, discover_videos, probe_video
from golf_swing.model import ModelError
from golf_swing.signals import SegmentationError


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="golf-swing",
        description="Analyze golf swing videos locally and produce evidence-linked reports.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe = subparsers.add_parser("probe", help="Show media facts without running pose analysis.")
    probe.add_argument("inputs", nargs="+", type=Path)
    probe.add_argument("--json", action="store_true", help="Print machine-readable JSON.")

    analyze = subparsers.add_parser("analyze", help="Find swings and create annotated reports.")
    analyze.add_argument("inputs", nargs="+", type=Path)
    analyze.add_argument("--out", type=Path, default=Path("output"))
    analyze.add_argument("--model", type=Path, help="Use an existing MediaPipe .task file.")
    analyze.add_argument(
        "--view",
        choices=("auto", "face-on", "down-the-line", "oblique"),
        default="auto",
        help="Camera view label used to gate interpretation.",
    )
    analyze.add_argument("--handedness", choices=("right", "left"), default="right")
    analyze.add_argument("--analysis-fps", type=float, default=10.0)
    analyze.add_argument("--max-height", type=int, default=960)
    analyze.add_argument(
        "--impact",
        action="append",
        type=float,
        default=[],
        help="Manual impact time in seconds; repeat in swing order for one input video.",
    )
    return parser


def _probe(args: argparse.Namespace) -> int:
    videos = discover_videos(args.inputs)
    records = []
    for video in videos:
        info = probe_video(video)
        records.append(
            {
                "path": str(video),
                "duration": info.duration,
                "fps": info.fps,
                "encoded_size": [info.encoded_width, info.encoded_height],
                "display_size": [info.display_width, info.display_height],
                "rotation": info.rotation,
                "frame_count": info.frame_count,
                "has_audio": info.has_audio,
            }
        )
    if args.json:
        print(json.dumps(records, indent=2))
    else:
        for record in records:
            print(record["path"])
            print(
                f"  {record['duration']:.3f}s · {record['fps']:.3f} fps · "
                f"display {record['display_size'][0]}×{record['display_size'][1]} · "
                f"rotation {record['rotation']}° · audio {record['has_audio']}"
            )
    return 0


def _analyze(args: argparse.Namespace) -> int:
    # Keep lightweight commands such as `probe` independent of ML imports and
    # Matplotlib's optional font-cache initialization.
    from golf_swing.analysis import analyze_collection

    videos = discover_videos(args.inputs)
    if not videos:
        raise MediaError("No supported video files found")
    if args.impact and len(videos) != 1:
        raise MediaError("Manual --impact values can be used only with one input video")
    index_path = analyze_collection(
        videos,
        output_root=args.out.resolve(),
        requested_model=args.model,
        view=args.view,
        handedness=args.handedness,
        analysis_fps=args.analysis_fps,
        max_height=args.max_height,
        manual_impacts=args.impact or None,
        progress=lambda message: print(message, file=sys.stderr, flush=True),
    )
    print(index_path)
    return 0


def main(argv: list[str] | None = None) -> None:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        code = _probe(args) if args.command == "probe" else _analyze(args)
    except (MediaError, ModelError, SegmentationError, RuntimeError) as exc:
        parser.exit(2, f"error: {exc}\n")
    raise SystemExit(code)
