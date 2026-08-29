from __future__ import annotations

from pathlib import Path

import mediapipe as mp
import numpy as np

from golf_swing.media import inference_dimensions, iter_rgb_frames
from golf_swing.types import PoseTrack, VideoInfo

LANDMARK_COUNT = 33


def _landmark_array(result_landmarks: list[object] | None) -> np.ndarray:
    output = np.full((LANDMARK_COUNT, 4), np.nan, dtype=np.float32)
    if not result_landmarks:
        return output
    for index, landmark in enumerate(result_landmarks[:LANDMARK_COUNT]):
        output[index] = (
            float(getattr(landmark, "x", np.nan)),
            float(getattr(landmark, "y", np.nan)),
            float(getattr(landmark, "z", np.nan)),
            float(getattr(landmark, "visibility", np.nan)),
        )
    return output


def extract_pose_track(
    info: VideoInfo,
    model_path: Path,
    *,
    analysis_fps: float = 10.0,
    max_height: int = 960,
) -> PoseTrack:
    BaseOptions = mp.tasks.BaseOptions
    PoseLandmarker = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    RunningMode = mp.tasks.vision.RunningMode

    options = PoseLandmarkerOptions(
        # CPU is the portable default. The macOS GPU delegate can require a
        # Metal graph service that is unavailable in sandboxed/headless runs.
        base_options=BaseOptions(
            model_asset_path=str(model_path),
            delegate=BaseOptions.Delegate.CPU,
        ),
        running_mode=RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.45,
        min_pose_presence_confidence=0.45,
        min_tracking_confidence=0.45,
        output_segmentation_masks=False,
    )

    times: list[float] = []
    image_landmarks: list[np.ndarray] = []
    world_landmarks: list[np.ndarray] = []
    last_timestamp_ms = -1

    with PoseLandmarker.create_from_options(options) as landmarker:
        for timestamp, rgb in iter_rgb_frames(info, fps=analysis_fps, max_height=max_height):
            timestamp_ms = max(last_timestamp_ms + 1, int(round(timestamp * 1000)))
            last_timestamp_ms = timestamp_ms
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(image, timestamp_ms)
            pose = result.pose_landmarks[0] if result.pose_landmarks else None
            world = result.pose_world_landmarks[0] if result.pose_world_landmarks else None
            times.append(timestamp)
            image_landmarks.append(_landmark_array(pose))
            world_landmarks.append(_landmark_array(world))

    width, height = inference_dimensions(info, max_height=max_height)
    return PoseTrack(
        times=np.asarray(times, dtype=np.float64),
        landmarks=np.asarray(image_landmarks, dtype=np.float32),
        world_landmarks=np.asarray(world_landmarks, dtype=np.float32),
        inference_width=width,
        inference_height=height,
        analysis_fps=analysis_fps,
    )
