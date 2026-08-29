from __future__ import annotations

import numpy as np

from golf_swing.types import PoseTrack, SwingEvents

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_WRIST = 15
RIGHT_WRIST = 16
LEFT_HIP = 23
RIGHT_HIP = 24
LEFT_ANKLE = 27
RIGHT_ANKLE = 28


class SegmentationError(RuntimeError):
    """Raised when no credible swing sequence can be found."""


def _nanmean_pair(values: np.ndarray, first: int, second: int) -> np.ndarray:
    pair = values[:, [first, second], :2]
    counts = np.isfinite(pair).sum(axis=1)
    totals = np.nansum(pair, axis=1)
    return np.divide(
        totals,
        counts,
        out=np.full_like(totals, np.nan, dtype=float),
        where=counts > 0,
    )


def _interpolate(values: np.ndarray, max_gap: int = 5) -> np.ndarray:
    output = np.asarray(values, dtype=float).copy()
    x = np.arange(len(output))
    for column in range(output.shape[1] if output.ndim > 1 else 1):
        series = output[:, column] if output.ndim > 1 else output
        good = np.isfinite(series)
        if good.sum() < 2:
            continue
        candidate = np.interp(x, x[good], series[good])
        missing = ~good
        starts = np.flatnonzero(missing & np.r_[True, ~missing[:-1]])
        ends = np.flatnonzero(missing & np.r_[~missing[1:], True])
        for start, end in zip(starts, ends, strict=True):
            if end - start + 1 <= max_gap and start > 0 and end < len(series) - 1:
                series[start : end + 1] = candidate[start : end + 1]
    return output


def _smooth(values: np.ndarray, window: int = 5) -> np.ndarray:
    if window <= 1:
        return values.copy()
    kernel = np.ones(window, dtype=float) / window
    if values.ndim == 1:
        return np.convolve(values, kernel, mode="same")
    return np.column_stack(
        [np.convolve(values[:, column], kernel, mode="same") for column in range(values.shape[1])]
    )


def _audio_impact(
    audio: np.ndarray,
    sample_rate: int,
    start: float,
    end: float,
) -> tuple[float | None, float]:
    if audio.size < sample_rate or end <= start:
        return None, 0.0
    # A ball strike is a very short, high-frequency transient. First differences
    # suppress speech and range ambience relative to the contact click.
    high_frequency = np.abs(np.diff(audio.astype(np.float64)))
    window = max(32, int(sample_rate * 0.005))
    usable = len(high_frequency) - len(high_frequency) % window
    if usable <= 0:
        return None, 0.0
    onset = high_frequency[:usable].reshape(-1, window).mean(axis=1)
    rate = sample_rate / window
    first = max(0, int(start * rate))
    last = min(len(onset), int(end * rate) + 1)
    if last - first < 3:
        return None, 0.0
    local = onset[first:last]
    index = int(np.argmax(local)) + first
    median = float(np.median(onset))
    mad = float(np.median(np.abs(onset - median))) + 1e-9
    prominence = float((onset[index] - median) / mad)
    return index / rate, prominence


def detect_swings(
    track: PoseTrack,
    *,
    audio: np.ndarray | None = None,
    audio_sample_rate: int = 48_000,
    manual_impacts: list[float] | None = None,
) -> list[SwingEvents]:
    landmarks = track.landmarks
    times = track.times
    fps = track.analysis_fps
    if len(times) < int(4 * fps):
        raise SegmentationError("Video is too short for automatic swing segmentation")

    hands = _interpolate(_nanmean_pair(landmarks, LEFT_WRIST, RIGHT_WRIST))
    shoulders = _interpolate(_nanmean_pair(landmarks, LEFT_SHOULDER, RIGHT_SHOULDER))
    ankles = _interpolate(_nanmean_pair(landmarks, LEFT_ANKLE, RIGHT_ANKLE))
    body_lengths = np.linalg.norm(shoulders - ankles, axis=1)
    body_scale = float(np.nanmedian(body_lengths[np.isfinite(body_lengths)]))
    if not np.isfinite(body_scale) or body_scale < 0.1:
        raise SegmentationError("Body pose was not stable enough to segment swings")

    hands = _smooth(hands, window=3)
    shoulder_y = shoulders[:, 1]
    relative_hand_y = (hands[:, 1] - shoulder_y) / body_scale
    displacement = np.linalg.norm(np.diff(hands, axis=0, prepend=hands[[0]]), axis=1)
    speed = _smooth(displacement * fps / body_scale, window=3)

    pre_frames = int(round(3.0 * fps))
    post_frames = int(round(1.4 * fps))
    edge = int(round(1.0 * fps))
    candidates: list[tuple[float, int, float]] = []
    for index in range(max(pre_frames, edge), len(times) - max(post_frames, edge)):
        neighborhood = relative_hand_y[index - edge : index + edge + 1]
        if not np.isfinite(relative_hand_y[index]) or relative_hand_y[index] > 0.30:
            continue
        if relative_hand_y[index] > np.nanmin(neighborhood) + 0.03:
            continue
        pre = relative_hand_y[index - pre_frames : index - max(1, int(0.25 * fps))]
        rise = float(np.nanpercentile(pre, 90) - relative_hand_y[index])
        post_speed = float(np.nanmax(speed[index : index + post_frames]))
        if rise < 0.42 or post_speed < 0.55:
            continue
        confidence = min(1.0, 0.45 + rise * 0.45 + min(post_speed, 2.0) * 0.12)
        score = rise + 0.3 * min(post_speed, 2.5)
        candidates.append((score, index, confidence))

    chosen: list[tuple[float, int, float]] = []
    separation = 7.0
    for candidate in sorted(candidates, reverse=True):
        candidate_time = times[candidate[1]]
        if all(abs(candidate_time - times[item[1]]) >= separation for item in chosen):
            chosen.append(candidate)
    chosen.sort(key=lambda item: item[1])
    if not chosen:
        raise SegmentationError(
            "No complete swing was found automatically. Try a brighter clip or manual phase overrides."
        )

    events: list[SwingEvents] = []
    for _, top_index, confidence in chosen:
        top_time = float(times[top_index])
        address_window_start = max(0, top_index - int(round(3.0 * fps)))
        address_window_end = max(address_window_start + 1, top_index - int(round(0.25 * fps)))
        address_series = relative_hand_y[address_window_start:address_window_end]
        baseline = float(np.nanpercentile(address_series, 90))
        address_index = address_window_start + int(np.nanargmax(address_series))
        for index in range(address_window_end - 1, address_window_start - 1, -1):
            if relative_hand_y[index] >= baseline - 0.07 and speed[index] < 0.55:
                address_index = index
                break
        address_time = float(times[address_index])

        # Reject arm raises, walking, and pose-identity jumps that can mimic a
        # backswing. A real golf setup has a plausible camera-normalized stance,
        # and the same tracked head remains near the address position at the top.
        address_points = landmarks[address_index]
        top_points = landmarks[top_index]
        address_shoulders = np.linalg.norm(
            address_points[LEFT_SHOULDER, :2] - address_points[RIGHT_SHOULDER, :2]
        )
        address_stance = np.linalg.norm(
            address_points[LEFT_ANKLE, :2] - address_points[RIGHT_ANKLE, :2]
        )
        address_head = np.nanmean(address_points[[0, 7, 8], :2], axis=0)
        top_head = np.nanmean(top_points[[0, 7, 8], :2], axis=0)
        stance_ratio = address_stance / max(address_shoulders, 1e-6)
        head_shift = np.linalg.norm(top_head - address_head) / max(address_shoulders, 1e-6)
        if not (0.45 <= stance_ratio <= 2.4) or head_shift > 1.2:
            continue

        fallback_first = min(len(times) - 1, top_index + max(1, int(round(0.25 * fps))))
        fallback_last = min(len(times), top_index + max(2, int(round(1.55 * fps))))
        fallback_slice = relative_hand_y[fallback_first:fallback_last]
        if fallback_slice.size:
            impact_index = fallback_first + int(np.nanargmin(np.abs(fallback_slice - baseline)))
        else:
            impact_index = min(len(times) - 1, top_index + int(round(0.7 * fps)))
        impact_time = float(times[impact_index])
        impact_source = "pose hand-height crossing"

        accepted_index = len(events)
        if manual_impacts and accepted_index < len(manual_impacts):
            impact_time = float(manual_impacts[accepted_index])
            impact_source = "manual override"
        elif audio is not None and audio.size:
            candidate_time, prominence = _audio_impact(
                audio,
                audio_sample_rate,
                top_time + 0.20,
                min(float(times[-1]), top_time + 1.65),
            )
            if candidate_time is not None and prominence >= 8.0:
                impact_time = candidate_time
                impact_source = "pose-gated audio transient"
                confidence = min(1.0, confidence + 0.08)

        finish_window = np.flatnonzero(
            (times >= impact_time + 0.40)
            & (times <= impact_time + 1.45)
            & np.isfinite(relative_hand_y)
            & (relative_hand_y < 0.18)
        )
        if finish_window.size:
            finish_scores = speed[finish_window] + 1.5 * np.maximum(
                relative_hand_y[finish_window], 0
            )
            finish_index = int(finish_window[int(np.nanargmin(finish_scores))])
        else:
            finish_target = impact_time + 1.0
            finish_index = int(np.nanargmin(np.abs(times - finish_target)))
        finish_time = float(times[finish_index])
        start_time = max(0.0, address_time - 0.75)
        end_time = min(float(times[-1]), max(finish_time + 0.75, impact_time + 2.0))
        events.append(
            SwingEvents(
                address=address_time,
                top=top_time,
                impact=impact_time,
                finish=finish_time,
                start=start_time,
                end=end_time,
                impact_source=impact_source,
                confidence=round(confidence, 3),
            )
        )
    if not events:
        raise SegmentationError(
            "Candidate motions were found, but none passed the golf-setup and tracking checks."
        )
    return events
