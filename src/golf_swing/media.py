from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from collections.abc import Iterator
from pathlib import Path

import cv2
import numpy as np

from golf_swing.types import VideoInfo

VIDEO_EXTENSIONS = {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm"}


class MediaError(RuntimeError):
    """Raised when FFmpeg cannot read or export media."""


def require_ffmpeg() -> None:
    missing = [name for name in ("ffmpeg", "ffprobe") if shutil.which(name) is None]
    if missing:
        joined = ", ".join(missing)
        raise MediaError(f"Missing required media tools: {joined}. Install FFmpeg first.")


def _run(args: list[str]) -> bytes:
    try:
        completed = subprocess.run(args, check=True, capture_output=True)
    except FileNotFoundError as exc:
        raise MediaError(f"Could not run {args[0]}; is FFmpeg installed?") from exc
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.decode("utf-8", errors="replace").strip()
        raise MediaError(message or f"Command failed: {' '.join(args)}") from exc
    return completed.stdout


def probe_video(path: Path) -> VideoInfo:
    require_ffmpeg()
    payload = json.loads(
        _run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration:stream=index,codec_type,width,height,avg_frame_rate,nb_frames:stream_side_data=rotation",
                "-of",
                "json",
                str(path),
            ]
        )
    )
    streams = payload.get("streams", [])
    video = next((stream for stream in streams if stream.get("codec_type") == "video"), None)
    if video is None:
        raise MediaError(f"No video stream found in {path}")

    rotation = 0
    for side_data in video.get("side_data_list", []):
        if "rotation" in side_data:
            rotation = int(round(float(side_data["rotation"])))
            break

    width = int(video["width"])
    height = int(video["height"])
    display_width, display_height = width, height
    if abs(rotation) % 180 == 90:
        display_width, display_height = height, width

    numerator, denominator = video.get("avg_frame_rate", "0/1").split("/")
    fps = float(numerator) / float(denominator) if float(denominator) else 0.0
    raw_count = video.get("nb_frames")
    frame_count = int(raw_count) if raw_count not in (None, "N/A") else None

    return VideoInfo(
        path=path,
        duration=float(payload["format"]["duration"]),
        encoded_width=width,
        encoded_height=height,
        display_width=display_width,
        display_height=display_height,
        fps=fps,
        frame_count=frame_count,
        rotation=rotation,
        has_audio=any(stream.get("codec_type") == "audio" for stream in streams),
    )


def inference_dimensions(info: VideoInfo, max_height: int = 960) -> tuple[int, int]:
    scale = min(1.0, max_height / info.display_height)
    width = max(2, int(round(info.display_width * scale)))
    height = max(2, int(round(info.display_height * scale)))
    width -= width % 2
    height -= height % 2
    return width, height


def iter_rgb_frames(
    info: VideoInfo,
    *,
    fps: float,
    max_height: int = 960,
    start: float | None = None,
    end: float | None = None,
) -> Iterator[tuple[float, np.ndarray]]:
    """Yield autorotated RGB frames at a constant analysis rate.

    FFmpeg applies the phone display matrix before the scale filter. Source time
    remains the reference for every yielded timestamp.
    """

    width, height = inference_dimensions(info, max_height=max_height)
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error"]
    if start is not None:
        command.extend(["-ss", f"{start:.6f}"])
    command.extend(["-i", str(info.path)])
    if end is not None:
        clip_start = start or 0.0
        command.extend(["-t", f"{max(0.0, end - clip_start):.6f}"])
    command.extend(
        [
            "-an",
            "-sn",
            "-dn",
            "-vf",
            f"fps={fps:.8f},scale={width}:{height}:flags=lanczos,format=rgb24",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ]
    )

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if process.stdout is None or process.stderr is None:
        raise MediaError("FFmpeg did not create output pipes")
    frame_bytes = width * height * 3
    index = 0
    origin = start or 0.0
    try:
        while True:
            chunk = process.stdout.read(frame_bytes)
            if not chunk:
                break
            if len(chunk) != frame_bytes:
                raise MediaError("FFmpeg returned a partial raw video frame")
            frame = np.frombuffer(chunk, dtype=np.uint8).reshape(height, width, 3).copy()
            yield origin + index / fps, frame
            index += 1
    finally:
        process.stdout.close()
        stderr = process.stderr.read().decode("utf-8", errors="replace").strip()
        return_code = process.wait()
        process.stderr.close()
        if return_code and stderr:
            raise MediaError(stderr)


def extract_frame(info: VideoInfo, timestamp: float) -> np.ndarray:
    encoded = _run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            f"{max(0.0, timestamp):.6f}",
            "-i",
            str(info.path),
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "png",
            "-",
        ]
    )
    image = cv2.imdecode(np.frombuffer(encoded, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise MediaError(f"Could not decode a frame from {info.path} at {timestamp:.3f}s")
    return image


def read_audio_mono(info: VideoInfo, sample_rate: int = 48_000) -> tuple[int, np.ndarray]:
    if not info.has_audio:
        return sample_rate, np.empty(0, dtype=np.float32)
    raw = _run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(info.path),
            "-map",
            "0:a:0",
            "-ac",
            "1",
            "-ar",
            str(sample_rate),
            "-f",
            "f32le",
            "-",
        ]
    )
    return sample_rate, np.frombuffer(raw, dtype="<f4").copy()


def discover_videos(paths: list[Path]) -> list[Path]:
    found: list[Path] = []
    for path in paths:
        if path.is_dir():
            found.extend(
                candidate
                for candidate in sorted(path.rglob("*"))
                if candidate.is_file() and candidate.suffix.lower() in VIDEO_EXTENSIONS
            )
        elif path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS:
            found.append(path)
        else:
            raise MediaError(f"Not a supported video file or directory: {path}")
    return list(dict.fromkeys(candidate.resolve() for candidate in found))


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()
