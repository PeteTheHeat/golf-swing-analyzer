from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np


@dataclass(frozen=True)
class VideoInfo:
    path: Path
    duration: float
    encoded_width: int
    encoded_height: int
    display_width: int
    display_height: int
    fps: float
    frame_count: int | None
    rotation: int
    has_audio: bool


@dataclass
class PoseTrack:
    times: np.ndarray
    landmarks: np.ndarray
    world_landmarks: np.ndarray
    inference_width: int
    inference_height: int
    analysis_fps: float


@dataclass(frozen=True)
class SwingEvents:
    address: float
    top: float
    impact: float
    finish: float
    start: float
    end: float
    impact_source: str
    confidence: float

    def as_dict(self) -> dict[str, Any]:
        return {
            "address": self.address,
            "top": self.top,
            "impact": self.impact,
            "finish": self.finish,
            "start": self.start,
            "end": self.end,
            "impact_source": self.impact_source,
            "confidence": self.confidence,
        }


@dataclass(frozen=True)
class Finding:
    title: str
    observation: str
    interpretation: str
    event: str
    severity: str = "info"
    confidence: str = "medium"

    def as_dict(self) -> dict[str, str]:
        return {
            "title": self.title,
            "observation": self.observation,
            "interpretation": self.interpretation,
            "event": self.event,
            "severity": self.severity,
            "confidence": self.confidence,
        }


@dataclass
class SwingResult:
    number: int
    events: SwingEvents
    metrics: dict[str, Any]
    findings: list[Finding] = field(default_factory=list)
    keyframes: dict[str, str] = field(default_factory=dict)
    sequence_image: str = ""
