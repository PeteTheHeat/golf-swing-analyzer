from __future__ import annotations

from statistics import mean, pstdev
from typing import Any

from golf_swing.types import Finding


def _number(value: Any) -> float | None:
    return float(value) if isinstance(value, (int, float)) else None


def critique_swing(metrics: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    timing = metrics["timing"]
    ratio = _number(timing.get("tempo_ratio"))
    if ratio is not None:
        if ratio < 2.2:
            interpretation = (
                "The backswing is quick relative to the downswing. Test a calmer takeaway before "
                "changing mechanics, and compare strike quality rather than chasing a fixed ideal."
            )
            severity = "watch"
        elif ratio > 4.0:
            interpretation = (
                "There is a long backswing relative to the downswing. Check for a pause or extra "
                "motion at the top; use ball flight to decide whether it is harmful."
            )
            severity = "watch"
        else:
            interpretation = (
                "The measured rhythm is within a common broad coaching band. Treat repeatability "
                "across swings as more useful than one target number."
            )
            severity = "good"
        findings.append(
            Finding(
                title="Swing rhythm",
                observation=(
                    f"Backswing {timing['backswing_seconds']:.2f}s, downswing "
                    f"{timing['downswing_seconds']:.2f}s, ratio {ratio:.2f}:1."
                ),
                interpretation=interpretation,
                event="top",
                severity=severity,
                confidence="medium",
            )
        )

    top_shift = _number(metrics["events"]["top"].get("head_shift_shoulders"))
    impact_shift = _number(metrics["events"]["impact"].get("head_shift_shoulders"))
    largest = max(
        (abs(value) for value in (top_shift, impact_shift) if value is not None), default=0
    )
    if largest >= 0.45:
        findings.append(
            Finding(
                title="Head movement is a useful check",
                observation=f"Peak projected head movement is {largest:.2f} shoulder widths.",
                interpretation=(
                    "That is a visible change from address. Check whether it repeats and whether it "
                    "moves the low point or strike; the oblique camera cannot label it as true sway."
                ),
                event="impact" if impact_shift and abs(impact_shift) >= largest else "top",
                severity="priority",
                confidence="medium",
            )
        )
    else:
        findings.append(
            Finding(
                title="Head position is fairly contained",
                observation=f"Peak projected head movement is {largest:.2f} shoulder widths.",
                interpretation=(
                    "The head stays in a similar image-plane region. This does not prove centered "
                    "pressure or depth control, but no large lateral move is visible."
                ),
                event="impact",
                severity="good",
                confidence="medium",
            )
        )

    address = metrics["events"]["address"]
    left_knee = _number(address.get("left_knee_deg"))
    right_knee = _number(address.get("right_knee_deg"))
    if left_knee is not None and right_knee is not None:
        difference = abs(left_knee - right_knee)
        findings.append(
            Finding(
                title="Address knee geometry",
                observation=(
                    f"Projected knee angles are {left_knee:.0f}° left and {right_knee:.0f}° right "
                    f"({difference:.0f}° apart)."
                ),
                interpretation=(
                    "Use this as a setup repeatability marker. Perspective changes these angles, so "
                    "do not treat the left-right difference as a diagnosis by itself."
                ),
                event="address",
                severity="info" if difference < 15 else "watch",
                confidence="medium",
            )
        )

    address_torso = _number(address.get("torso_inclination_deg"))
    impact_torso = _number(metrics["events"]["impact"].get("torso_inclination_deg"))
    if address_torso is not None and impact_torso is not None:
        posture_change = address_torso - impact_torso
        if posture_change >= 10:
            findings.append(
                Finding(
                    title="Forward inclination decreases through impact",
                    observation=(
                        f"Projected torso inclination changes from {address_torso:.0f}° at address "
                        f"to {impact_torso:.0f}° at impact ({posture_change:.0f}° more upright)."
                    ),
                    interpretation=(
                        "This repeated pattern is worth a true down-the-line check for standing up "
                        "or early extension. The oblique view cannot separate that from torso "
                        "rotation, so test it before treating it as the cause of a miss."
                    ),
                    event="impact",
                    severity="priority",
                    confidence="medium",
                )
            )
    return findings


def consistency_findings(metric_sets: list[dict[str, Any]]) -> list[Finding]:
    if len(metric_sets) < 2:
        return []
    ratios = [
        float(item["timing"]["tempo_ratio"])
        for item in metric_sets
        if item["timing"].get("tempo_ratio") is not None
    ]
    stance = [
        float(item["events"]["address"]["stance_to_shoulders"])
        for item in metric_sets
        if item["events"]["address"].get("stance_to_shoulders") is not None
    ]
    findings: list[Finding] = []
    if len(ratios) >= 2:
        spread = pstdev(ratios)
        findings.append(
            Finding(
                title="Tempo repeatability",
                observation=f"Mean ratio {mean(ratios):.2f}:1; swing-to-swing spread {spread:.2f}.",
                interpretation=(
                    "A smaller spread means the sequence repeats more consistently. Compare this "
                    "with strike location before deciding that a timing change is needed."
                ),
                event="top",
                severity="good" if spread < 0.35 else "watch",
                confidence="medium",
            )
        )
    if len(stance) >= 2:
        spread = max(stance) - min(stance)
        findings.append(
            Finding(
                title="Setup width repeatability",
                observation=(
                    f"Stance-to-shoulder ratio ranges from {min(stance):.2f} to {max(stance):.2f}."
                ),
                interpretation=(
                    "This is a camera-normalized setup marker. A large range can make comparisons "
                    "between later swing positions less meaningful."
                ),
                event="address",
                severity="good" if spread < 0.12 else "watch",
                confidence="medium",
            )
        )
    return findings
