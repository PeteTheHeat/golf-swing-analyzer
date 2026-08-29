from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import numpy as np

from golf_swing.critique import consistency_findings, critique_swing
from golf_swing.media import extract_frame, probe_video, read_audio_mono, sha256_file
from golf_swing.metrics import EVENT_NAMES, nearest_pose, swing_metrics
from golf_swing.model import ensure_pose_model, model_sha256
from golf_swing.pose import extract_pose_track
from golf_swing.render import annotate_keyframe, make_sequence, write_image
from golf_swing.report import write_collection_index, write_json, write_video_report
from golf_swing.signals import detect_swings
from golf_swing.types import SwingResult

Progress = Callable[[str], None]


def _quiet(_: str) -> None:
    return None


def analyze_video(
    video_path: Path,
    *,
    output_root: Path,
    model_path: Path,
    view: str,
    handedness: str,
    analysis_fps: float,
    max_height: int,
    manual_impacts: list[float] | None = None,
    progress: Progress = _quiet,
) -> tuple[Path, list[SwingResult]]:
    info = probe_video(video_path)
    destination = output_root / video_path.stem
    destination.mkdir(parents=True, exist_ok=True)
    progress(f"Tracking body pose in {video_path.name} at {analysis_fps:g} fps …")
    track = extract_pose_track(
        info,
        model_path,
        analysis_fps=analysis_fps,
        max_height=max_height,
    )
    progress(f"Reading the primary audio track in {video_path.name} …")
    sample_rate, audio = read_audio_mono(info)
    events = detect_swings(
        track,
        audio=audio,
        audio_sample_rate=sample_rate,
        manual_impacts=manual_impacts,
    )
    progress(f"Found {len(events)} complete swing(s) in {video_path.name}.")

    np.savez_compressed(
        destination / "pose_track.npz",
        times=track.times,
        landmarks=track.landmarks,
        world_landmarks=track.world_landmarks,
        analysis_fps=track.analysis_fps,
    )

    results: list[SwingResult] = []
    for number, swing_events in enumerate(events, start=1):
        metrics = swing_metrics(track, swing_events)
        swing_dir = destination / f"swing_{number:02d}"
        keyframe_dir = swing_dir / "keyframes"
        keyframe_dir.mkdir(parents=True, exist_ok=True)
        address_landmarks = nearest_pose(track, swing_events.address)
        sequence_frames: list[np.ndarray] = []
        keyframes: dict[str, str] = {}
        for event in EVENT_NAMES:
            timestamp = getattr(swing_events, event)
            source_frame = extract_frame(info, timestamp)
            event_landmarks = nearest_pose(track, timestamp)
            annotated = annotate_keyframe(
                source_frame,
                event_landmarks,
                event=event,
                timestamp=timestamp,
                event_metrics=metrics["events"][event],
                address_landmarks=address_landmarks,
                view=view,
                swing_number=number,
            )
            image_path = keyframe_dir / f"{event}.jpg"
            write_image(image_path, annotated)
            keyframes[event] = str(image_path.relative_to(destination))
            sequence_frames.append(annotated)
        sequence = make_sequence(sequence_frames, list(EVENT_NAMES))
        sequence_path = swing_dir / "sequence.jpg"
        write_image(sequence_path, sequence)
        result = SwingResult(
            number=number,
            events=swing_events,
            metrics=metrics,
            findings=critique_swing(metrics),
            keyframes=keyframes,
            sequence_image=str(sequence_path.relative_to(destination)),
        )
        results.append(result)

    collection = consistency_findings([result.metrics for result in results])
    manifest: dict[str, Any] = {
        "source_name": video_path.name,
        "source_sha256": sha256_file(video_path),
        "model_sha256": model_sha256(model_path),
        "view": view,
        "handedness": handedness,
        "analysis_fps": analysis_fps,
        "source": {
            "duration": info.duration,
            "fps": info.fps,
            "display_width": info.display_width,
            "display_height": info.display_height,
            "rotation": info.rotation,
        },
        "limitations": [
            "Single-view measurements are 2D projections.",
            "Impact may fall between source frames at this frame rate.",
            "The body-pose model does not track the golf club or ball.",
            "Model-estimated world coordinates are saved for research but not reported as metric 3D.",
        ],
        "swings": [
            {
                "number": result.number,
                "events": result.events.as_dict(),
                "metrics": result.metrics,
                "findings": [finding.as_dict() for finding in result.findings],
                "keyframes": result.keyframes,
                "sequence_image": result.sequence_image,
            }
            for result in results
        ],
        "consistency_findings": [finding.as_dict() for finding in collection],
    }
    write_json(destination / "analysis.json", manifest)
    write_video_report(
        destination / "report.html",
        info=info,
        results=results,
        collection_findings=collection,
        view=view,
        manifest=manifest,
    )
    progress(f"Wrote {destination / 'report.html'}")
    return destination / "report.html", results


def analyze_collection(
    video_paths: list[Path],
    *,
    output_root: Path,
    requested_model: Path | None,
    view: str,
    handedness: str,
    analysis_fps: float,
    max_height: int,
    manual_impacts: list[float] | None = None,
    progress: Progress = _quiet,
) -> Path:
    progress("Locating the MediaPipe pose model …")
    model_path = ensure_pose_model(requested_model)
    output_root.mkdir(parents=True, exist_ok=True)
    report_links: list[dict[str, Any]] = []
    all_metrics: list[dict[str, Any]] = []
    for index, video_path in enumerate(video_paths):
        impacts = manual_impacts if len(video_paths) == 1 else None
        report_path, results = analyze_video(
            video_path,
            output_root=output_root,
            model_path=model_path,
            view=view,
            handedness=handedness,
            analysis_fps=analysis_fps,
            max_height=max_height,
            manual_impacts=impacts,
            progress=progress,
        )
        report_links.append(
            {
                "name": video_path.name,
                "swings": len(results),
                "href": str(report_path.relative_to(output_root)),
                "order": index,
            }
        )
        all_metrics.extend(result.metrics for result in results)
    index_path = output_root / "index.html"
    collection = consistency_findings(all_metrics)
    write_collection_index(index_path, report_links, collection)
    write_json(
        output_root / "collection.json",
        {
            "reports": report_links,
            "total_swings": len(all_metrics),
            "consistency_findings": [finding.as_dict() for finding in collection],
        },
    )
    progress(f"Collection report: {index_path}")
    return index_path
