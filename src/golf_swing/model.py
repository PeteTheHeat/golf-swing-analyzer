from __future__ import annotations

import hashlib
import os
import urllib.error
import urllib.request
from pathlib import Path

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_full/float16/1/pose_landmarker_full.task"
)
MODEL_FILENAME = "pose_landmarker_full_float16_v1.task"
MODEL_SHA256 = "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1"


class ModelError(RuntimeError):
    """Raised when a pose model cannot be loaded or downloaded."""


def default_cache_dir() -> Path:
    override = os.environ.get("SWINGLAB_CACHE_DIR")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".cache" / "golf-swing-analyzer"


def ensure_pose_model(explicit_path: Path | None = None) -> Path:
    if explicit_path is not None:
        path = explicit_path.expanduser().resolve()
        if not path.is_file():
            raise ModelError(f"Pose model does not exist: {path}")
        return path

    cache_dir = default_cache_dir()
    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / MODEL_FILENAME
    if destination.is_file() and destination.stat().st_size > 1_000_000:
        if model_sha256(destination) == MODEL_SHA256:
            return destination
        raise ModelError(f"Cached pose model failed its SHA-256 check: {destination}")

    partial = destination.with_suffix(".part")
    try:
        with (
            urllib.request.urlopen(MODEL_URL, timeout=60) as response,
            partial.open("wb") as output,
        ):
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    except (OSError, urllib.error.URLError) as exc:
        partial.unlink(missing_ok=True)
        raise ModelError(
            "Could not download the MediaPipe pose model. Check the network or pass --model."
        ) from exc

    if partial.stat().st_size < 1_000_000:
        partial.unlink(missing_ok=True)
        raise ModelError("The downloaded pose model is unexpectedly small")
    if model_sha256(partial) != MODEL_SHA256:
        partial.unlink(missing_ok=True)
        raise ModelError("The downloaded pose model failed its SHA-256 check")
    partial.replace(destination)
    return destination


def model_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()
