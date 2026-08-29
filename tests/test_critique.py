from golf_swing.critique import critique_swing


def test_large_head_shift_becomes_a_testable_priority() -> None:
    metrics = {
        "timing": {"backswing_seconds": 0.9, "downswing_seconds": 0.3, "tempo_ratio": 3.0},
        "events": {
            "address": {
                "left_knee_deg": 160,
                "right_knee_deg": 164,
                "torso_inclination_deg": 34,
            },
            "top": {"head_shift_shoulders": 0.55},
            "impact": {"head_shift_shoulders": 0.2, "torso_inclination_deg": 18},
        },
    }
    findings = critique_swing(metrics)
    assert any(finding.severity == "priority" for finding in findings)
    assert any("inclination" in finding.title.lower() for finding in findings)
