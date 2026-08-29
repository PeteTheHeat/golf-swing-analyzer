import Foundation

struct BodyTrajectorySample: Sendable {
    var frameIndex: Int
    var timestamp: Double
    var hands: PosePoint
    var shoulders: PosePoint
    var pelvis: PosePoint?
    var ankles: PosePoint
    var head: PosePoint?
    var shoulderWidth: Double
    var bodyScale: Double
    var relativeHandY: Double
    var handSpeed: Double
}

enum BodyTrajectory {
    static func samples(
        from frames: [PoseFrame],
        minimumConfidence: Double
    ) -> [BodyTrajectorySample] {
        struct RawSample {
            var frameIndex: Int
            var timestamp: Double
            var hands: PosePoint
            var shoulders: PosePoint
            var pelvis: PosePoint?
            var ankles: PosePoint
            var head: PosePoint?
            var shoulderWidth: Double
            var bodyScale: Double
        }

        var raw: [RawSample] = []
        for (index, frame) in frames.enumerated() {
            guard let hands = frame.midpoint(.leftWrist, .rightWrist, minimumConfidence: minimumConfidence),
                  let shoulders = frame.midpoint(
                    .leftShoulder,
                    .rightShoulder,
                    minimumConfidence: minimumConfidence
                  ),
                  let ankles = frame.midpoint(
                    .leftAnkle,
                    .rightAnkle,
                    minimumConfidence: minimumConfidence
                  ),
                  let leftShoulder = frame[.leftShoulder],
                  let rightShoulder = frame[.rightShoulder]
            else {
                continue
            }
            let bodyScale = PoseGeometry.distance(shoulders, ankles)
            let shoulderWidth = PoseGeometry.distance(leftShoulder, rightShoulder)
            guard bodyScale > 0.08, shoulderWidth > 0.025 else { continue }
            raw.append(
                RawSample(
                    frameIndex: index,
                    timestamp: frame.timestampSeconds,
                    hands: hands,
                    shoulders: shoulders,
                    pelvis: frame.midpoint(.leftHip, .rightHip, minimumConfidence: minimumConfidence),
                    ankles: ankles,
                    head: frame.headCenter(minimumConfidence: minimumConfidence),
                    shoulderWidth: shoulderWidth,
                    bodyScale: bodyScale
                )
            )
        }

        let stableScale = Statistics.median(raw.map(\.bodyScale)) ?? 0
        guard stableScale > 0.08 else { return [] }
        var result: [BodyTrajectorySample] = []
        result.reserveCapacity(raw.count)
        for (index, sample) in raw.enumerated() {
            let speed: Double
            if index == 0 {
                speed = 0
            } else {
                let previous = raw[index - 1]
                let deltaTime = sample.timestamp - previous.timestamp
                if deltaTime > 0, deltaTime < 0.5 {
                    speed = PoseGeometry.distance(sample.hands, previous.hands) / deltaTime / stableScale
                } else {
                    speed = 0
                }
            }
            result.append(
                BodyTrajectorySample(
                    frameIndex: sample.frameIndex,
                    timestamp: sample.timestamp,
                    hands: sample.hands,
                    shoulders: sample.shoulders,
                    pelvis: sample.pelvis,
                    ankles: sample.ankles,
                    head: sample.head,
                    shoulderWidth: sample.shoulderWidth,
                    bodyScale: stableScale,
                    relativeHandY: (sample.hands.y - sample.shoulders.y) / stableScale,
                    handSpeed: speed
                )
            )
        }

        // A short centered mean suppresses one-frame Vision velocity spikes.
        guard result.count >= 3 else { return result }
        let rawSpeeds = result.map(\.handSpeed)
        for index in result.indices {
            let first = max(0, index - 1)
            let last = min(result.count - 1, index + 1)
            result[index].handSpeed = rawSpeeds[first...last].reduce(0, +) / Double(last - first + 1)
        }
        return result
    }
}

public enum SwingEventDetector {
    public static func detect(
        in track: PoseTrack,
        minimumConfidence: Double = 0.30
    ) throws -> SwingEventTimestamps {
        let samples = BodyTrajectory.samples(
            from: track.frames,
            minimumConfidence: minimumConfidence
        )
        guard samples.count >= 12,
              let firstTime = samples.first?.timestamp,
              let lastTime = samples.last?.timestamp,
              lastTime - firstTime >= 1.2
        else {
            throw SwingAnalysisError.insufficientMotionEvidence
        }

        struct TopCandidate {
            var index: Int
            var rise: Double
            var postSpeed: Double
            var score: Double
        }

        var candidates: [TopCandidate] = []
        for index in samples.indices {
            let sample = samples[index]
            let before = samples.filter {
                $0.timestamp >= sample.timestamp - 3.0 &&
                    $0.timestamp <= sample.timestamp - 0.20
            }
            let nearby = samples.filter { abs($0.timestamp - sample.timestamp) <= 0.25 }
            let after = samples.filter {
                $0.timestamp >= sample.timestamp + 0.12 &&
                    $0.timestamp <= sample.timestamp + 1.25
            }
            guard before.count >= 3, after.count >= 3,
                  sample.relativeHandY <= 0.30,
                  sample.relativeHandY <= (nearby.map(\.relativeHandY).min() ?? .infinity) + 0.025,
                  let baseline = Statistics.percentile(before.map(\.relativeHandY), 0.85)
            else {
                continue
            }
            let rise = baseline - sample.relativeHandY
            let postSpeed = after.map(\.handSpeed).max() ?? 0
            guard rise >= 0.30, postSpeed >= 0.32 else { continue }
            let poseConfidence = track.frames[sample.frameIndex].overallConfidence
            candidates.append(
                TopCandidate(
                    index: index,
                    rise: rise,
                    postSpeed: postSpeed,
                    score: rise + min(postSpeed, 2.5) * 0.22 + poseConfidence * 0.10
                )
            )
        }

        guard let topCandidate = candidates.max(by: { $0.score < $1.score }) else {
            throw SwingAnalysisError.insufficientMotionEvidence
        }
        let topIndex = topCandidate.index
        let top = samples[topIndex]

        let addressCandidates = samples.enumerated().filter { _, sample in
            sample.timestamp >= top.timestamp - 3.0 && sample.timestamp <= top.timestamp - 0.20
        }
        guard let baseline = Statistics.percentile(
            addressCandidates.map { $0.element.relativeHandY },
            0.85
        ) else {
            throw SwingAnalysisError.invalidEventOrder
        }
        let stableAddress = addressCandidates.filter { _, sample in
            sample.relativeHandY >= baseline - 0.08 && sample.handSpeed < 0.55
        }
        let addressPair = stableAddress.last ?? addressCandidates.max {
            $0.element.relativeHandY < $1.element.relativeHandY
        }
        guard let addressPair else { throw SwingAnalysisError.invalidEventOrder }
        let address = addressPair.element

        guard setupLooksCredible(track.frames[address.frameIndex], minimumConfidence: minimumConfidence),
              headTrackingLooksCredible(address: address, top: top)
        else {
            throw SwingAnalysisError.insufficientMotionEvidence
        }

        let impactCandidates = samples.enumerated().filter { _, sample in
            sample.timestamp >= top.timestamp + 0.15 && sample.timestamp <= top.timestamp + 1.55
        }
        guard impactCandidates.count >= 2 else { throw SwingAnalysisError.invalidEventOrder }
        let crossing = impactCandidates.first { _, sample in
            sample.relativeHandY >= baseline - 0.10 && sample.handSpeed >= 0.28
        }
        let impactPair = crossing ?? impactCandidates.min {
            abs($0.element.relativeHandY - baseline) < abs($1.element.relativeHandY - baseline)
        }
        guard let impactPair else { throw SwingAnalysisError.invalidEventOrder }
        let impact = impactPair.element

        let finishCandidates = samples.enumerated().filter { _, sample in
            sample.timestamp >= impact.timestamp + 0.35 && sample.timestamp <= impact.timestamp + 1.65
        }
        let credibleFinish = finishCandidates.filter { _, sample in
            sample.relativeHandY < 0.30
        }
        let finishPair = credibleFinish.min { first, second in
            finishScore(first.element) < finishScore(second.element)
        } ?? finishCandidates.min { first, second in
            abs(first.element.timestamp - (impact.timestamp + 1.0)) <
                abs(second.element.timestamp - (impact.timestamp + 1.0))
        }
        guard let finishPair else { throw SwingAnalysisError.invalidEventOrder }
        let finish = finishPair.element

        guard address.timestamp < top.timestamp,
              top.timestamp < impact.timestamp,
              impact.timestamp < finish.timestamp
        else {
            throw SwingAnalysisError.invalidEventOrder
        }

        let evidenceFrames = [address, top, impact, finish].map { track.frames[$0.frameIndex] }
        let poseConfidence = evidenceFrames.map(\.overallConfidence).reduce(0, +) / 4
        let confidence = min(
            0.98,
            0.34 + min(topCandidate.rise, 0.9) * 0.28 +
                min(topCandidate.postSpeed / 2, 1) * 0.16 + poseConfidence * 0.24
        )
        guard confidence >= 0.48 else { throw SwingAnalysisError.lowPoseConfidence }

        return SwingEventTimestamps(
            addressSeconds: address.timestamp,
            topSeconds: top.timestamp,
            impactSeconds: impact.timestamp,
            finishSeconds: finish.timestamp,
            confidence: confidence,
            impactBasis: "pose hand-height crossing; confirm against the visible strike frame"
        )
    }

    private static func finishScore(_ sample: BodyTrajectorySample) -> Double {
        sample.handSpeed + max(sample.relativeHandY, 0) * 1.5
    }

    private static func setupLooksCredible(
        _ frame: PoseFrame,
        minimumConfidence: Double
    ) -> Bool {
        guard let leftShoulder = frame[.leftShoulder],
              let rightShoulder = frame[.rightShoulder],
              let leftAnkle = frame[.leftAnkle],
              let rightAnkle = frame[.rightAnkle],
              [leftShoulder, rightShoulder, leftAnkle, rightAnkle]
                .allSatisfy({ $0.confidence >= minimumConfidence })
        else {
            return false
        }
        let shoulderWidth = PoseGeometry.distance(leftShoulder, rightShoulder)
        let stanceWidth = PoseGeometry.distance(leftAnkle, rightAnkle)
        guard let ratio = PoseGeometry.safeRatio(stanceWidth, shoulderWidth) else { return false }
        return ratio >= 0.45 && ratio <= 2.4
    }

    private static func headTrackingLooksCredible(
        address: BodyTrajectorySample,
        top: BodyTrajectorySample
    ) -> Bool {
        guard let addressHead = address.head, let topHead = top.head else { return true }
        return PoseGeometry.distance(addressHead, topHead) / address.shoulderWidth <= 1.2
    }
}

enum Statistics {
    static func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        guard sorted.count > 1 else { return sorted[0] }
        let position = max(0, min(percentile, 1)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}
