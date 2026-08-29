#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import Foundation

/// Deterministic pose motion for simulator-only UI and navigation QA.
/// The iOS Simulator runtime does not always contain Apple's body-pose weights.
enum SimulatorPoseFixture {
    static let environmentKey = "SWINGLAB_USE_SIMULATOR_POSE_FIXTURE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func make(
        selectedRange: CMTimeRange,
        sampleRate: Double
    ) -> PoseTrack {
        let start = selectedRange.start.seconds
        let duration = max(5, selectedRange.duration.seconds)
        let safeSampleRate = max(10, sampleRate)
        let frameCount = max(51, Int((duration * safeSampleRate).rounded()))
        let frames = (0 ..< frameCount).map { index -> PoseFrame in
            let fraction = Double(index) / Double(max(1, frameCount - 1))
            return frame(
                timestamp: start + (fraction * duration),
                normalizedTime: fraction * 5
            )
        }

        return PoseTrack(
            selectedRangeStartSeconds: start,
            selectedRangeDurationSeconds: duration,
            nominalSampleRate: safeSampleRate,
            orientation: .right,
            frames: frames
        )
    }

    private static func frame(
        timestamp: Double,
        normalizedTime: Double
    ) -> PoseFrame {
        let hands = handPosition(at: normalizedTime)
        let shoulderCenterX: Double
        if normalizedTime <= 2.5 {
            shoulderCenterX = 0.55
        } else if normalizedTime <= 3.1 {
            shoulderCenterX = 0.55 - ((normalizedTime - 2.5) / 0.6 * 0.06)
        } else {
            shoulderCenterX = 0.49
        }

        let confidence = 0.95
        let point: (Double, Double) -> PosePoint = {
            PosePoint(x: $0, y: $1, confidence: confidence)
        }
        let leftShoulderX = shoulderCenterX - 0.10
        let rightShoulderX = shoulderCenterX + 0.10
        let joints: [PoseJoint: PosePoint] = [
            .nose: point(shoulderCenterX + 0.03, 0.22),
            .leftEye: point(shoulderCenterX + 0.01, 0.21),
            .rightEye: point(shoulderCenterX + 0.05, 0.21),
            .leftEar: point(shoulderCenterX - 0.01, 0.23),
            .rightEar: point(shoulderCenterX + 0.07, 0.23),
            .neck: point(shoulderCenterX, 0.34),
            .root: point(0.47, 0.62),
            .leftShoulder: point(leftShoulderX, 0.40),
            .rightShoulder: point(rightShoulderX, 0.40),
            .leftElbow: point(
                (leftShoulderX + hands.x - 0.01) / 2,
                (0.40 + hands.y) / 2
            ),
            .rightElbow: point(
                (rightShoulderX + hands.x + 0.01) / 2,
                (0.40 + hands.y) / 2
            ),
            .leftWrist: point(hands.x - 0.01, hands.y),
            .rightWrist: point(hands.x + 0.01, hands.y),
            .leftHip: point(0.40, 0.62),
            .rightHip: point(0.54, 0.62),
            .leftKnee: point(0.38, 0.76),
            .rightKnee: point(0.56, 0.76),
            .leftAnkle: point(0.39, 0.91),
            .rightAnkle: point(0.55, 0.91),
        ]
        return PoseFrame(timestampSeconds: timestamp, joints: joints)
    }

    private static func handPosition(at time: Double) -> (x: Double, y: Double) {
        if time < 1.5 {
            return (0.67, 0.67)
        }
        if time <= 2.5 {
            let progress = (time - 1.5) / 1.0
            let inwardProgress = min(1, progress * 2)
            return (0.67 - inwardProgress * 0.14, 0.67 - progress * 0.40)
        }
        if time <= 3.1 {
            let progress = (time - 2.5) / 0.6
            return (0.70 - progress * 0.03, 0.27 + progress * 0.40)
        }
        if time <= 3.8 {
            let progress = (time - 3.1) / 0.7
            return (0.67 - progress * 0.12, 0.67 - progress * 0.42)
        }
        return (0.55, 0.25)
    }
}
#endif
