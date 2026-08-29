import Foundation

public enum PoseGeometry {
    public static func midpoint(_ first: PosePoint, _ second: PosePoint) -> PosePoint {
        PosePoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2,
            confidence: min(first.confidence, second.confidence)
        )
    }

    public static func distance(_ first: PosePoint, _ second: PosePoint) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }

    /// Returns the smaller 2D angle at `vertex` in degrees.
    public static func jointAngle(
        first: PosePoint,
        vertex: PosePoint,
        third: PosePoint
    ) -> Double? {
        let firstX = first.x - vertex.x
        let firstY = first.y - vertex.y
        let secondX = third.x - vertex.x
        let secondY = third.y - vertex.y
        let denominator = hypot(firstX, firstY) * hypot(secondX, secondY)
        guard denominator.isFinite, denominator > 1e-9 else { return nil }
        let cosine = max(-1, min(1, (firstX * secondX + firstY * secondY) / denominator))
        return acos(cosine) * 180 / .pi
    }

    /// Signed image-plane line angle relative to horizontal in the range -90...90.
    public static func lineAngle(first: PosePoint, second: PosePoint) -> Double? {
        let deltaX = second.x - first.x
        let deltaY = second.y - first.y
        guard hypot(deltaX, deltaY) > 1e-9 else { return nil }
        var angle = atan2(-deltaY, deltaX) * 180 / .pi
        if angle > 90 {
            angle -= 180
        } else if angle <= -90 {
            angle += 180
        }
        return angle
    }

    /// Absolute image-plane inclination from vertical.
    public static func inclinationFromVertical(lower: PosePoint, upper: PosePoint) -> Double? {
        let deltaX = upper.x - lower.x
        let deltaY = upper.y - lower.y
        guard hypot(deltaX, deltaY) > 1e-9 else { return nil }
        return abs(atan2(deltaX, -deltaY) * 180 / .pi)
    }

    public static func safeRatio(_ numerator: Double, _ denominator: Double) -> Double? {
        guard numerator.isFinite, denominator.isFinite, abs(denominator) > 1e-9 else {
            return nil
        }
        return numerator / denominator
    }

    static func interpolated(_ first: PosePoint, _ second: PosePoint, fraction: Double) -> PosePoint {
        let amount = max(0, min(1, fraction))
        return PosePoint(
            x: first.x + (second.x - first.x) * amount,
            y: first.y + (second.y - first.y) * amount,
            confidence: min(first.confidence, second.confidence)
        )
    }
}

extension PoseFrame {
    func midpoint(_ first: PoseJoint, _ second: PoseJoint, minimumConfidence: Double) -> PosePoint? {
        guard let firstPoint = joints[first], let secondPoint = joints[second],
              firstPoint.confidence >= minimumConfidence,
              secondPoint.confidence >= minimumConfidence
        else {
            return nil
        }
        return PoseGeometry.midpoint(firstPoint, secondPoint)
    }

    func headCenter(minimumConfidence: Double) -> PosePoint? {
        let candidates = [PoseJoint.nose, .leftEye, .rightEye, .leftEar, .rightEar]
            .compactMap { joints[$0] }
            .filter { $0.confidence >= minimumConfidence }
        guard !candidates.isEmpty else { return nil }
        return PosePoint(
            x: candidates.map(\.x).reduce(0, +) / Double(candidates.count),
            y: candidates.map(\.y).reduce(0, +) / Double(candidates.count),
            confidence: candidates.map(\.confidence).reduce(0, +) / Double(candidates.count)
        )
    }
}
