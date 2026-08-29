from __future__ import annotations

from typing import Any

import numpy as np

from golf_swing.geometry import (
    angle_degrees,
    inclination_from_vertical,
    line_angle_degrees,
    midpoint,
    safe_ratio,
)
from golf_swing.types import PoseTrack, SwingEvents

EVENT_NAMES = ("address", "top", "impact", "finish")


def nearest_pose(track: PoseTrack, timestamp: float) -> np.ndarray:
    index = int(np.nanargmin(np.abs(track.times - timestamp)))
    return track.landmarks[index]


def _rounded(value: float, digits: int = 1) -> float | None:
    return round(float(value), digits) if np.isfinite(value) else None


def event_metrics(points: np.ndarray) -> dict[str, float | None]:
    shoulder_mid = midpoint(points, 11, 12)
    hip_mid = midpoint(points, 23, 24)
    head = np.nanmean(points[[0, 7, 8], :2], axis=0)
    shoulder_width = float(np.linalg.norm(points[11, :2] - points[12, :2]))
    stance_width = float(np.linalg.norm(points[27, :2] - points[28, :2]))
    visibility = points[:, 3]
    return {
        "left_knee_deg": _rounded(angle_degrees(points[23], points[25], points[27])),
        "right_knee_deg": _rounded(angle_degrees(points[24], points[26], points[28])),
        "left_elbow_deg": _rounded(angle_degrees(points[11], points[13], points[15])),
        "right_elbow_deg": _rounded(angle_degrees(points[12], points[14], points[16])),
        "torso_inclination_deg": _rounded(inclination_from_vertical(hip_mid, shoulder_mid)),
        "shoulder_tilt_deg": _rounded(line_angle_degrees(points[11], points[12])),
        "hip_tilt_deg": _rounded(line_angle_degrees(points[23], points[24])),
        "stance_to_shoulders": _rounded(safe_ratio(stance_width, shoulder_width), 2),
        "shoulder_width_normalized": _rounded(shoulder_width, 4),
        "head_x": _rounded(float(head[0]), 5),
        "head_y": _rounded(float(head[1]), 5),
        "hip_x": _rounded(float(hip_mid[0]), 5),
        "hip_y": _rounded(float(hip_mid[1]), 5),
        "pose_visibility": _rounded(float(np.nanmedian(visibility)), 2),
    }


def swing_metrics(track: PoseTrack, events: SwingEvents) -> dict[str, Any]:
    poses = {name: nearest_pose(track, getattr(events, name)) for name in EVENT_NAMES}
    measured = {name: event_metrics(points) for name, points in poses.items()}
    address = measured["address"]
    shoulder_width = address["shoulder_width_normalized"]
    if shoulder_width is None or shoulder_width <= 1e-6:
        shoulder_width = None

    for name in ("top", "impact", "finish"):
        event = measured[name]
        if shoulder_width is None or address["head_x"] is None or event["head_x"] is None:
            event["head_shift_shoulders"] = None
        else:
            event["head_shift_shoulders"] = _rounded(
                (event["head_x"] - address["head_x"]) / shoulder_width,
                2,
            )
        if shoulder_width is None or address["hip_x"] is None or event["hip_x"] is None:
            event["hip_shift_shoulders"] = None
        else:
            event["hip_shift_shoulders"] = _rounded(
                (event["hip_x"] - address["hip_x"]) / shoulder_width,
                2,
            )

    backswing = events.top - events.address
    downswing = events.impact - events.top
    return {
        "timing": {
            "backswing_seconds": _rounded(backswing, 3),
            "downswing_seconds": _rounded(downswing, 3),
            "tempo_ratio": _rounded(safe_ratio(backswing, downswing), 2),
        },
        "events": measured,
        "measurement_scope": "2D image-plane projections from a single camera",
    }
