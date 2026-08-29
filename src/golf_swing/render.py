from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np

POSE_CONNECTIONS = (
    (0, 11),
    (0, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (11, 23),
    (12, 24),
    (23, 24),
    (23, 25),
    (25, 27),
    (27, 29),
    (29, 31),
    (24, 26),
    (26, 28),
    (28, 30),
    (30, 32),
)

CYAN = (242, 201, 65)
ORANGE = (55, 145, 255)
GREEN = (112, 214, 132)
WHITE = (245, 245, 245)
MUTED = (190, 195, 200)


def _pixel_points(landmarks: np.ndarray, width: int, height: int) -> np.ndarray:
    points = landmarks[:, :2].astype(float).copy()
    points[:, 0] *= width
    points[:, 1] *= height
    return points


def _valid(point: np.ndarray) -> bool:
    return bool(np.isfinite(point).all())


def _label(
    image: np.ndarray,
    text: str,
    origin: tuple[int, int],
    *,
    color: tuple[int, int, int] = WHITE,
    scale: float = 0.62,
    thickness: int = 2,
) -> None:
    x, y = origin
    (width, height), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thickness)
    cv2.rectangle(
        image,
        (x - 5, y - height - 6),
        (x + width + 5, y + baseline + 5),
        (18, 22, 27),
        -1,
        cv2.LINE_AA,
    )
    cv2.putText(
        image,
        text,
        (x, y),
        cv2.FONT_HERSHEY_SIMPLEX,
        scale,
        color,
        thickness,
        cv2.LINE_AA,
    )


def _draw_angle(
    image: np.ndarray,
    a: np.ndarray,
    vertex: np.ndarray,
    c: np.ndarray,
    value: float | None,
    *,
    color: tuple[int, int, int] = ORANGE,
) -> None:
    if value is None or not all(_valid(point) for point in (a, vertex, c)):
        return
    first_angle = math.atan2(a[1] - vertex[1], a[0] - vertex[0])
    second_angle = math.atan2(c[1] - vertex[1], c[0] - vertex[0])
    delta = (second_angle - first_angle + math.pi) % (2 * math.pi) - math.pi
    radius = max(20, int(min(np.linalg.norm(a - vertex), np.linalg.norm(c - vertex)) * 0.28))
    samples = np.linspace(first_angle, first_angle + delta, 24)
    arc = np.column_stack(
        [vertex[0] + radius * np.cos(samples), vertex[1] + radius * np.sin(samples)]
    ).astype(np.int32)
    cv2.polylines(image, [arc], False, color, 3, cv2.LINE_AA)
    text_at = vertex + np.array([radius + 8, -radius - 4])
    _label(
        image,
        f"{value:.0f} deg",
        (int(text_at[0]), int(text_at[1])),
        color=color,
        scale=0.50,
    )


def _draw_skeleton(image: np.ndarray, landmarks: np.ndarray) -> np.ndarray:
    height, width = image.shape[:2]
    points = _pixel_points(landmarks, width, height)
    for first, second in POSE_CONNECTIONS:
        if landmarks[first, 3] < 0.35 or landmarks[second, 3] < 0.35:
            continue
        if _valid(points[first]) and _valid(points[second]):
            cv2.line(
                image,
                tuple(points[first].astype(int)),
                tuple(points[second].astype(int)),
                CYAN,
                max(2, width // 360),
                cv2.LINE_AA,
            )
    for index, point in enumerate(points):
        if landmarks[index, 3] >= 0.35 and _valid(point):
            cv2.circle(
                image, tuple(point.astype(int)), max(3, width // 220), WHITE, -1, cv2.LINE_AA
            )
    return points


def annotate_keyframe(
    frame: np.ndarray,
    landmarks: np.ndarray,
    *,
    event: str,
    timestamp: float,
    event_metrics: dict[str, Any],
    address_landmarks: np.ndarray,
    view: str,
    swing_number: int,
) -> np.ndarray:
    image = frame.copy()
    height, width = image.shape[:2]
    overlay = image.copy()
    cv2.rectangle(overlay, (0, 0), (width, max(118, height // 14)), (12, 16, 21), -1)
    cv2.addWeighted(overlay, 0.82, image, 0.18, 0, image)

    points = _draw_skeleton(image, landmarks)
    address = _pixel_points(address_landmarks, width, height)
    address_head_x = int(np.nanmean(address[[0, 7, 8], 0]))
    address_hip_x = int(np.nanmean(address[[23, 24], 0]))
    cv2.line(image, (address_head_x, 0), (address_head_x, height), (175, 120, 70), 2, cv2.LINE_AA)
    cv2.line(image, (address_hip_x, 0), (address_hip_x, height), (100, 125, 190), 2, cv2.LINE_AA)

    for first, second, color in ((11, 12, GREEN), (23, 24, ORANGE)):
        if _valid(points[first]) and _valid(points[second]):
            cv2.line(
                image,
                tuple(points[first].astype(int)),
                tuple(points[second].astype(int)),
                color,
                4,
                cv2.LINE_AA,
            )
    shoulder_mid = np.nanmean(points[[11, 12]], axis=0)
    hip_mid = np.nanmean(points[[23, 24]], axis=0)
    if _valid(shoulder_mid) and _valid(hip_mid):
        cv2.line(
            image,
            tuple(hip_mid.astype(int)),
            tuple(shoulder_mid.astype(int)),
            GREEN,
            4,
            cv2.LINE_AA,
        )
        cv2.line(
            image,
            (int(hip_mid[0]), int(hip_mid[1] + min(260, height * 0.14))),
            (int(hip_mid[0]), int(hip_mid[1] - min(260, height * 0.14))),
            MUTED,
            2,
            cv2.LINE_AA,
        )

    if event in {"address", "impact", "finish"}:
        _draw_angle(image, points[23], points[25], points[27], event_metrics.get("left_knee_deg"))
        _draw_angle(image, points[24], points[26], points[28], event_metrics.get("right_knee_deg"))
    if event in {"top", "impact", "finish"}:
        _draw_angle(image, points[11], points[13], points[15], event_metrics.get("left_elbow_deg"))
        _draw_angle(image, points[12], points[14], points[16], event_metrics.get("right_elbow_deg"))

    title = f"SWING {swing_number:02d}  |  {event.upper()}  |  {timestamp:05.2f}s"
    cv2.putText(
        image,
        title,
        (24, 48),
        cv2.FONT_HERSHEY_SIMPLEX,
        max(0.72, width / 900),
        WHITE,
        2,
        cv2.LINE_AA,
    )
    subtitle = (
        f"{view.replace('-', ' ').upper()} | 2D PROJECTION | "
        f"POSE {event_metrics.get('pose_visibility', 0):.2f}"
    )
    cv2.putText(
        image,
        subtitle,
        (24, 86),
        cv2.FONT_HERSHEY_SIMPLEX,
        max(0.48, width / 1400),
        MUTED,
        1,
        cv2.LINE_AA,
    )

    readouts = [
        f"Torso {event_metrics.get('torso_inclination_deg', '-')} deg",
        f"Shoulders {event_metrics.get('shoulder_tilt_deg', '-')} deg",
        f"Hips {event_metrics.get('hip_tilt_deg', '-')} deg",
    ]
    shift = event_metrics.get("head_shift_shoulders")
    if shift is not None:
        readouts.append(f"Head shift {shift:+.2f} shoulder widths")
    panel_height = 54 + 34 * len(readouts)
    panel = image.copy()
    cv2.rectangle(
        panel,
        (18, height - panel_height - 18),
        (min(width - 18, 520), height - 18),
        (12, 16, 21),
        -1,
    )
    cv2.addWeighted(panel, 0.82, image, 0.18, 0, image)
    for row, text in enumerate(readouts):
        cv2.putText(
            image,
            text,
            (36, height - panel_height + 25 + row * 34),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.58,
            WHITE if row == 0 else MUTED,
            1,
            cv2.LINE_AA,
        )
    return image


def write_image(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(path), image, [cv2.IMWRITE_JPEG_QUALITY, 92]):
        raise RuntimeError(f"Could not write image: {path}")


def make_sequence(
    images: list[np.ndarray], labels: list[str], *, target_height: int = 720
) -> np.ndarray:
    panels: list[np.ndarray] = []
    for image, label in zip(images, labels, strict=True):
        scale = target_height / image.shape[0]
        width = int(round(image.shape[1] * scale))
        resized = cv2.resize(image, (width, target_height), interpolation=cv2.INTER_AREA)
        cv2.rectangle(resized, (0, 0), (width, 54), (12, 16, 21), -1)
        cv2.putText(
            resized,
            label.upper(),
            (18, 37),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.72,
            WHITE,
            2,
            cv2.LINE_AA,
        )
        panels.append(resized)
    return cv2.hconcat(panels)
