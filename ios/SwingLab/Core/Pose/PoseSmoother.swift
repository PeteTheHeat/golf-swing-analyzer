import Foundation

/// Confidence-weighted temporal smoothing for Vision's frame-to-frame pose jitter.
public enum PoseSmoother {
    public static func smooth(
        _ track: PoseTrack,
        radius: Int = 2,
        maximumGapSeconds: Double = 0.20,
        minimumConfidence: Double = 0.15
    ) -> PoseTrack {
        guard radius > 0, track.frames.count > 2 else { return track }
        let frames = track.frames
        var output: [PoseFrame] = []
        output.reserveCapacity(frames.count)

        for (index, frame) in frames.enumerated() {
            var joints: [PoseJoint: PosePoint] = [:]
            let first = max(0, index - radius)
            let last = min(frames.count - 1, index + radius)

            for joint in PoseJoint.allCases {
                var weightedX = 0.0
                var weightedY = 0.0
                var totalWeight = 0.0
                var confidenceTotal = 0.0
                var confidenceWeight = 0.0

                for neighborIndex in first...last {
                    let neighbor = frames[neighborIndex]
                    let delta = abs(neighbor.timestampSeconds - frame.timestampSeconds)
                    guard delta <= maximumGapSeconds,
                          let point = neighbor.joints[joint],
                          point.confidence >= minimumConfidence
                    else {
                        continue
                    }
                    let frameDistance = abs(neighborIndex - index)
                    let temporalWeight = 1 / Double(1 + frameDistance)
                    let weight = temporalWeight * point.confidence * point.confidence
                    weightedX += point.x * weight
                    weightedY += point.y * weight
                    totalWeight += weight
                    confidenceTotal += point.confidence * temporalWeight
                    confidenceWeight += temporalWeight
                }

                if totalWeight > 0, confidenceWeight > 0 {
                    joints[joint] = PosePoint(
                        x: weightedX / totalWeight,
                        y: weightedY / totalWeight,
                        confidence: confidenceTotal / confidenceWeight
                    )
                }
            }

            output.append(
                PoseFrame(
                    timestampSeconds: frame.timestampSeconds,
                    orientation: frame.orientation,
                    joints: joints
                )
            )
        }

        return PoseTrack(
            selectedRangeStartSeconds: track.selectedRangeStartSeconds,
            selectedRangeDurationSeconds: track.selectedRangeDurationSeconds,
            nominalSampleRate: track.nominalSampleRate,
            orientation: track.orientation,
            frames: output
        )
    }
}
