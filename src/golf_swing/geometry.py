from __future__ import annotations

import math

import numpy as np


def angle_degrees(a: np.ndarray, vertex: np.ndarray, c: np.ndarray) -> float:
    """Return the smaller 2D angle at *vertex* in degrees."""

    first = np.asarray(a, dtype=float)[:2] - np.asarray(vertex, dtype=float)[:2]
    second = np.asarray(c, dtype=float)[:2] - np.asarray(vertex, dtype=float)[:2]
    denominator = np.linalg.norm(first) * np.linalg.norm(second)
    if not np.isfinite(denominator) or denominator < 1e-9:
        return float("nan")
    cosine = float(np.clip(np.dot(first, second) / denominator, -1.0, 1.0))
    return math.degrees(math.acos(cosine))


def line_angle_degrees(a: np.ndarray, b: np.ndarray) -> float:
    """Return a signed image-plane line angle relative to horizontal."""

    delta = np.asarray(b, dtype=float)[:2] - np.asarray(a, dtype=float)[:2]
    if not np.isfinite(delta).all() or np.linalg.norm(delta) < 1e-9:
        return float("nan")
    angle = math.degrees(math.atan2(-float(delta[1]), float(delta[0])))
    # Shoulder and hip lines have no meaningful arrow direction. Keep the same
    # physical line in a readable -90..90 degree range.
    if angle > 90:
        angle -= 180
    elif angle <= -90:
        angle += 180
    return angle


def inclination_from_vertical(a: np.ndarray, b: np.ndarray) -> float:
    """Return absolute image-plane inclination from vertical."""

    delta = np.asarray(b, dtype=float)[:2] - np.asarray(a, dtype=float)[:2]
    if not np.isfinite(delta).all() or np.linalg.norm(delta) < 1e-9:
        return float("nan")
    return abs(math.degrees(math.atan2(float(delta[0]), -float(delta[1]))))


def midpoint(points: np.ndarray, first: int, second: int) -> np.ndarray:
    return np.nanmean(points[[first, second], :2], axis=0)


def safe_ratio(numerator: float, denominator: float) -> float:
    if not np.isfinite(numerator) or not np.isfinite(denominator) or abs(denominator) < 1e-9:
        return float("nan")
    return float(numerator / denominator)
