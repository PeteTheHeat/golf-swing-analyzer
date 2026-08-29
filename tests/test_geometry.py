import numpy as np

from golf_swing.geometry import angle_degrees, inclination_from_vertical, line_angle_degrees


def test_joint_angle_is_ninety_degrees() -> None:
    assert angle_degrees(np.array([1, 0]), np.array([0, 0]), np.array([0, 1])) == 90


def test_line_angle_uses_image_up_as_positive() -> None:
    assert line_angle_degrees(np.array([0, 1]), np.array([1, 0])) == 45


def test_line_angle_is_undirected() -> None:
    assert line_angle_degrees(np.array([1, 0]), np.array([0, 0])) == 0


def test_vertical_inclination() -> None:
    assert inclination_from_vertical(np.array([0, 1]), np.array([0, 0])) == 0
