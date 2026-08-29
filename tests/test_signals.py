import numpy as np

from golf_swing.signals import detect_swings
from golf_swing.types import PoseTrack


def _synthetic_track() -> PoseTrack:
    fps = 10.0
    times = np.arange(0, 22, 1 / fps)
    landmarks = np.full((len(times), 33, 4), np.nan, dtype=np.float32)
    landmarks[:, :, 3] = 0.95
    landmarks[:, 11, :2] = (0.45, 0.40)
    landmarks[:, 12, :2] = (0.55, 0.40)
    landmarks[:, 27, :2] = (0.43, 0.90)
    landmarks[:, 28, :2] = (0.57, 0.90)
    for index in (0, 7, 8):
        landmarks[:, index, :2] = (0.50, 0.25)
    landmarks[:, 15, :2] = (0.49, 0.67)
    landmarks[:, 16, :2] = (0.51, 0.67)

    for top in (5.0, 15.0):
        up = (times >= top - 1.0) & (times <= top)
        down = (times > top) & (times <= top + 0.7)
        landmarks[up, 15:17, 1] = np.linspace(0.67, 0.27, up.sum())[:, None]
        landmarks[down, 15:17, 1] = np.linspace(0.27, 0.67, down.sum())[:, None]
    return PoseTrack(
        times=times,
        landmarks=landmarks,
        world_landmarks=landmarks.copy(),
        inference_width=540,
        inference_height=960,
        analysis_fps=fps,
    )


def test_detects_two_synthetic_swings_and_manual_impacts() -> None:
    events = detect_swings(_synthetic_track(), manual_impacts=[5.6, 15.6])
    assert len(events) == 2
    assert [event.impact for event in events] == [5.6, 15.6]
    assert all(event.top < event.impact < event.finish for event in events)
