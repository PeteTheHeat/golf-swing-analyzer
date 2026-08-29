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
    var continuitySegment: Int
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

        var result: [BodyTrajectorySample] = []
        result.reserveCapacity(raw.count)
        var segmentStart = 0
        var continuitySegment = 0
        while segmentStart < raw.count {
            var segmentEnd = segmentStart + 1
            while segmentEnd < raw.count {
                let previous = raw[segmentEnd - 1]
                let current = raw[segmentEnd]
                let deltaTime = current.timestamp - previous.timestamp
                let scaleRatio = max(previous.bodyScale, current.bodyScale) /
                    max(0.000_001, min(previous.bodyScale, current.bodyScale))
                guard deltaTime > 0, deltaTime < 0.5, scaleRatio < 1.55 else {
                    break
                }
                segmentEnd += 1
            }

            let segment = raw[segmentStart..<segmentEnd]
            let stableScale = Statistics.median(segment.map(\.bodyScale)) ?? 0
            if stableScale > 0.08 {
                for index in segment.indices {
                    let sample = raw[index]
                    let speed: Double
                    if index == segmentStart {
                        speed = 0
                    } else {
                        let previous = raw[index - 1]
                        let deltaTime = sample.timestamp - previous.timestamp
                        speed = PoseGeometry.distance(sample.hands, previous.hands) /
                            deltaTime / stableScale
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
                            handSpeed: speed,
                            continuitySegment: continuitySegment
                        )
                    )
                }
            }
            segmentStart = segmentEnd
            continuitySegment += 1
        }

        guard !result.isEmpty else { return [] }

        // A short centered mean suppresses one-frame Vision velocity spikes,
        // but never smooths across a person/scene gap.
        guard result.count >= 3 else { return result }
        let rawSpeeds = result.map(\.handSpeed)
        for index in result.indices {
            let first = max(0, index - 1)
            let last = min(result.count - 1, index + 1)
            var speedSum = 0.0
            var sampleCount = 0
            for neighbor in first...last
            where result[neighbor].continuitySegment == result[index].continuitySegment {
                speedSum += rawSpeeds[neighbor]
                sampleCount += 1
            }
            if sampleCount > 0 {
                result[index].handSpeed = speedSum / Double(sampleCount)
            }
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

    fileprivate static func setupLooksCredible(
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

    fileprivate static func headTrackingLooksCredible(
        address: BodyTrajectorySample,
        top: BodyTrajectorySample
    ) -> Bool {
        guard let addressHead = address.head, let topHead = top.head else { return true }
        return PoseGeometry.distance(addressHead, topHead) / address.shoulderWidth <= 1.2
    }
}

/// One low-frequency observation used to find golf swings in a longer video.
/// `handHeight` is measured in body lengths above the shoulder center. A larger
/// value means the hands are higher in the frame. `handSpeed` is body lengths
/// per second, so detection is independent of video resolution and golfer size.
public struct SwingMotionSample: Codable, Hashable, Sendable {
    public var timestampSeconds: Double
    public var handHeight: Double
    public var handSpeed: Double
    public var poseConfidence: Double
    public var continuitySegment: Int

    public init(
        timestampSeconds: Double,
        handHeight: Double,
        handSpeed: Double,
        poseConfidence: Double,
        continuitySegment: Int = 0
    ) {
        self.timestampSeconds = timestampSeconds
        self.handHeight = handHeight
        self.handSpeed = handSpeed
        self.poseConfidence = poseConfidence
        self.continuitySegment = continuitySegment
    }
}

/// A detected swing and the source-video range that contains it.
public struct DetectedSwingClip: Codable, Hashable, Sendable, Identifiable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var events: SwingEventTimestamps
    public var confidence: Double

    public init(
        startSeconds: Double,
        endSeconds: Double,
        events: SwingEventTimestamps,
        confidence: Double
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.events = events
        self.confidence = confidence
    }

    /// Top-of-backswing timestamps are unique after non-maximum suppression.
    public var id: Double { events.topSeconds }
    public var durationSeconds: Double { max(0, endSeconds - startSeconds) }
}

public struct SwingClipDetectionConfiguration: Hashable, Sendable {
    public var minimumRise: Double
    public var minimumPostTopSpeed: Double
    public var minimumPoseConfidence: Double
    public var minimumCandidateConfidence: Double
    public var minimumTopSpacingSeconds: Double
    public var overlapThreshold: Double
    public var maximumSampleGapSeconds: Double
    public var preRollSeconds: Double
    public var postRollSeconds: Double
    public var minimumClipDurationSeconds: Double
    public var maximumClipDurationSeconds: Double

    public init(
        minimumRise: Double = 0.28,
        minimumPostTopSpeed: Double = 0.28,
        minimumPoseConfidence: Double = 0.25,
        minimumCandidateConfidence: Double = 0.52,
        minimumTopSpacingSeconds: Double = 1.50,
        overlapThreshold: Double = 0.45,
        maximumSampleGapSeconds: Double = 0.75,
        preRollSeconds: Double = 0.55,
        postRollSeconds: Double = 0.55,
        minimumClipDurationSeconds: Double = 2.20,
        maximumClipDurationSeconds: Double = 6.50
    ) {
        self.minimumRise = max(0.05, minimumRise)
        self.minimumPostTopSpeed = max(0.05, minimumPostTopSpeed)
        self.minimumPoseConfidence = min(max(0, minimumPoseConfidence), 1)
        self.minimumCandidateConfidence = min(max(0, minimumCandidateConfidence), 1)
        self.minimumTopSpacingSeconds = max(0.25, minimumTopSpacingSeconds)
        self.overlapThreshold = min(max(0.05, overlapThreshold), 1)
        self.maximumSampleGapSeconds = max(0.20, maximumSampleGapSeconds)
        self.preRollSeconds = max(0, preRollSeconds)
        self.postRollSeconds = max(0, postRollSeconds)
        self.minimumClipDurationSeconds = max(1.0, minimumClipDurationSeconds)
        self.maximumClipDurationSeconds = max(
            self.minimumClipDurationSeconds,
            maximumClipDurationSeconds
        )
    }
}

/// A synchronous cooperative-cancellation hook for long-video detection.
/// Pass `Task.checkCancellation` from an async caller.
public typealias SwingClipCancellationCheck = () throws -> Void

/// Finds multiple swing-shaped motion sequences in a long video.
///
/// This layer is deterministic and has no dependency on Vision or AVFoundation.
/// Callers can run pose extraction at a low sample rate, pass those observations
/// here, then offer the returned source ranges for review or export.
public enum SwingClipDetector {
    public static func detect(
        in track: PoseTrack,
        assetDuration: TimeInterval? = nil,
        minimumConfidence: Double = 0.30,
        configuration: SwingClipDetectionConfiguration = .init(),
        cancellationCheck: SwingClipCancellationCheck = {}
    ) throws -> [DetectedSwingClip] {
        try cancellationCheck()
        let trajectory = BodyTrajectory.samples(
            from: track.frames,
            minimumConfidence: minimumConfidence
        )
        try cancellationCheck()
        var samples: [SwingMotionSample] = []
        samples.reserveCapacity(trajectory.count)
        for (index, sample) in trajectory.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            samples.append(SwingMotionSample(
                timestampSeconds: sample.timestamp,
                handHeight: -sample.relativeHandY,
                handSpeed: sample.handSpeed,
                poseConfidence: track.frames[sample.frameIndex].overallConfidence,
                continuitySegment: sample.continuitySegment
            ))
        }
        let detected = try detect(
            samples: samples,
            configuration: configuration,
            cancellationCheck: cancellationCheck
        )
        var clips: [DetectedSwingClip] = []
        clips.reserveCapacity(detected.count)
        for (index, clip) in detected.enumerated() {
            if index.isMultiple(of: 16) { try cancellationCheck() }
            guard let address = nearestSample(
                in: trajectory,
                to: clip.events.addressSeconds
            ),
                let top = nearestSample(
                    in: trajectory,
                    to: clip.events.topSeconds
                )
            else {
                continue
            }
            guard SwingEventDetector.setupLooksCredible(
                track.frames[address.frameIndex],
                minimumConfidence: minimumConfidence
            ) && SwingEventDetector.headTrackingLooksCredible(
                address: address,
                top: top
            ) else {
                continue
            }
            clips.append(clip)
        }
        guard let assetDuration,
              assetDuration.isFinite,
              assetDuration > 0
        else {
            return clips
        }
        return clips.compactMap { clip in
            var bounded = clip
            bounded.startSeconds = min(max(0, bounded.startSeconds), assetDuration)
            bounded.endSeconds = min(max(0, bounded.endSeconds), assetDuration)
            return bounded.endSeconds > bounded.startSeconds && containsAllEvents(bounded)
                ? bounded
                : nil
        }
    }

    /// Convenience API for synchronous callers that do not need cancellation.
    public static func detect(
        samples: [SwingMotionSample],
        configuration: SwingClipDetectionConfiguration = .init()
    ) -> [DetectedSwingClip] {
        // The no-op cancellation closure cannot throw.
        (try? detect(
            samples: samples,
            configuration: configuration,
            cancellationCheck: {}
        )) ?? []
    }

    /// Cancellation-aware API for async import pipelines. Detection stays
    /// synchronous, but regularly invokes `cancellationCheck` and propagates
    /// its error immediately.
    public static func detect(
        samples: [SwingMotionSample],
        configuration: SwingClipDetectionConfiguration = .init(),
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [DetectedSwingClip] {
        try cancellationCheck()
        let normalized = try normalizedSamples(
            samples,
            configuration: configuration,
            cancellationCheck: cancellationCheck
        )
        let segments = try contiguousSegments(
            normalized,
            maximumGap: configuration.maximumSampleGapSeconds,
            cancellationCheck: cancellationCheck
        )
        var hypotheses: [Candidate] = []
        for segment in segments {
            try cancellationCheck()
            let smoothed = try smooth(segment, cancellationCheck: cancellationCheck)
            hypotheses.append(contentsOf: try candidates(
                in: smoothed,
                configuration: configuration,
                cancellationCheck: cancellationCheck
            ))
        }
        return try suppressOverlappingCandidates(
            hypotheses,
            configuration: configuration,
            cancellationCheck: cancellationCheck
        )
    }

    private struct Candidate {
        var clip: DetectedSwingClip
        var rise: Double
        var postTopSpeed: Double
    }

    private static func nearestSample(
        in samples: [BodyTrajectorySample],
        to timestamp: Double
    ) -> BodyTrajectorySample? {
        guard !samples.isEmpty else { return nil }
        let insertion = lowerBound(in: samples, timestamp: timestamp)
        if insertion == 0 { return samples[0] }
        if insertion == samples.count { return samples[samples.count - 1] }
        let before = samples[insertion - 1]
        let after = samples[insertion]
        return abs(before.timestamp - timestamp) <= abs(after.timestamp - timestamp)
            ? before
            : after
    }

    private static func normalizedSamples(
        _ samples: [SwingMotionSample],
        configuration: SwingClipDetectionConfiguration,
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [SwingMotionSample] {
        var valid: [SwingMotionSample] = []
        valid.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            guard sample.timestampSeconds.isFinite,
                  sample.handHeight.isFinite,
                  sample.handSpeed.isFinite,
                  sample.poseConfidence.isFinite,
                  sample.poseConfidence >= configuration.minimumPoseConfidence
            else {
                continue
            }
            valid.append(sample)
        }
        try cancellationCheck()
        valid.sort {
            if $0.timestampSeconds == $1.timestampSeconds {
                return $0.poseConfidence > $1.poseConfidence
            }
            return $0.timestampSeconds < $1.timestampSeconds
        }
        try cancellationCheck()

        var result: [SwingMotionSample] = []
        result.reserveCapacity(valid.count)
        for (index, original) in valid.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            var sample = original
            sample.handSpeed = max(0, sample.handSpeed)
            sample.poseConfidence = min(max(0, sample.poseConfidence), 1)
            if let previous = result.last,
               abs(previous.timestampSeconds - sample.timestampSeconds) < 0.000_001 {
                // Sorting puts the highest-confidence observation first.
                continue
            }
            result.append(sample)
        }
        return result
    }

    private static func contiguousSegments(
        _ samples: [SwingMotionSample],
        maximumGap: Double,
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [[SwingMotionSample]] {
        var segments: [[SwingMotionSample]] = []
        var current: [SwingMotionSample] = []
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            if let previous = current.last,
               sample.continuitySegment != previous.continuitySegment ||
               sample.timestampSeconds - previous.timestampSeconds > maximumGap {
                if !current.isEmpty { segments.append(current) }
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// A centered time-domain mean removes isolated pose jitter without changing
    /// timestamps or smearing observations across gaps in pose tracking.
    private static func smooth(
        _ samples: [SwingMotionSample],
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [SwingMotionSample] {
        guard samples.count >= 3 else { return samples }
        var result: [SwingMotionSample] = []
        result.reserveCapacity(samples.count)
        var lowerIndex = 0
        var upperIndex = 0
        var heightSum = 0.0
        var speedSum = 0.0
        var confidenceSum = 0.0

        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 64) { try cancellationCheck() }
            let lowerTime = sample.timestampSeconds - 0.22
            let upperTime = sample.timestampSeconds + 0.22
            while upperIndex < samples.count,
                  samples[upperIndex].timestampSeconds <= upperTime {
                heightSum += samples[upperIndex].handHeight
                speedSum += samples[upperIndex].handSpeed
                confidenceSum += samples[upperIndex].poseConfidence
                upperIndex += 1
            }
            while lowerIndex < upperIndex,
                  samples[lowerIndex].timestampSeconds < lowerTime {
                heightSum -= samples[lowerIndex].handHeight
                speedSum -= samples[lowerIndex].handSpeed
                confidenceSum -= samples[lowerIndex].poseConfidence
                lowerIndex += 1
            }
            let count = Double(upperIndex - lowerIndex)
            guard count > 0 else {
                result.append(sample)
                continue
            }
            result.append(SwingMotionSample(
                timestampSeconds: sample.timestampSeconds,
                handHeight: heightSum / count,
                handSpeed: speedSum / count,
                poseConfidence: confidenceSum / count
            ))
        }
        return result
    }

    private static func candidates(
        in samples: [SwingMotionSample],
        configuration: SwingClipDetectionConfiguration,
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [Candidate] {
        guard samples.count >= 12,
              let segmentStart = samples.first?.timestampSeconds,
              let segmentEnd = samples.last?.timestampSeconds,
              segmentEnd - segmentStart >= 1.8
        else {
            return []
        }

        var result: [Candidate] = []
        var nearbyWindow = ForwardTimeWindow()
        var beforeWindow = ForwardTimeWindow()
        var afterWindow = ForwardTimeWindow()
        for top in samples {
            try cancellationCheck()
            let nearbyRange = nearbyWindow.range(
                in: samples,
                from: top.timestampSeconds - 0.28,
                through: top.timestampSeconds + 0.28
            )
            var localMaximum = -Double.infinity
            for index in nearbyRange {
                localMaximum = max(localMaximum, samples[index].handHeight)
            }
            guard localMaximum.isFinite,
                  top.handHeight >= localMaximum - 0.025
            else {
                continue
            }

            let beforeRange = beforeWindow.range(
                in: samples,
                from: top.timestampSeconds - 3.2,
                through: top.timestampSeconds - 0.22
            )
            let afterRange = afterWindow.range(
                in: samples,
                from: top.timestampSeconds + 0.12,
                through: top.timestampSeconds + 1.55
            )
            guard beforeRange.count >= 3,
                  afterRange.count >= 3,
                  let baseline = Statistics.percentile(
                    beforeRange.map { samples[$0].handHeight },
                    0.20
                  )
            else {
                continue
            }

            let rise = top.handHeight - baseline
            var postTopSpeed = 0.0
            for index in afterRange {
                postTopSpeed = max(postTopSpeed, samples[index].handSpeed)
            }
            guard rise >= configuration.minimumRise,
                  postTopSpeed >= configuration.minimumPostTopSpeed
            else {
                continue
            }

            var address: SwingMotionSample?
            for index in beforeRange.reversed() {
                let sample = samples[index]
                if sample.handHeight <= baseline + 0.08, sample.handSpeed <= 0.48 {
                    address = sample
                    break
                }
            }
            guard let address else { continue }

            var credibleImpact: SwingMotionSample?
            var fallbackImpact: SwingMotionSample?
            for index in afterRange {
                let sample = samples[index]
                guard sample.timestampSeconds <= top.timestampSeconds + 1.45 else { break }
                if credibleImpact == nil,
                   sample.handHeight <= baseline + 0.14,
                   sample.handSpeed >= configuration.minimumPostTopSpeed {
                    credibleImpact = sample
                }
                if sample.handSpeed >= configuration.minimumPostTopSpeed,
                   fallbackImpact == nil ||
                    abs(sample.handHeight - baseline) <
                    abs(fallbackImpact!.handHeight - baseline) {
                    fallbackImpact = sample
                }
            }
            guard let impact = credibleImpact ?? fallbackImpact,
                  abs(impact.handHeight - baseline) <= max(0.22, rise * 0.35)
            else {
                continue
            }

            let finishRise = max(0.16, configuration.minimumRise * 0.60)
            let finishRange = indexedRange(
                in: samples,
                from: impact.timestampSeconds + 0.30,
                through: impact.timestampSeconds + 2.0
            )
            var finish: SwingMotionSample?
            for index in finishRange {
                let sample = samples[index]
                guard sample.handHeight >= baseline + finishRise,
                      sample.handSpeed <= 0.65
                else {
                    continue
                }
                if finish == nil ||
                    finishScore(sample, baseline: baseline, impactTime: impact.timestampSeconds) >
                    finishScore(finish!, baseline: baseline, impactTime: impact.timestampSeconds) {
                    finish = sample
                }
            }
            guard let finish else { continue }

            guard address.timestampSeconds < top.timestampSeconds,
                  top.timestampSeconds < impact.timestampSeconds,
                  impact.timestampSeconds < finish.timestampSeconds,
                  finish.timestampSeconds - address.timestampSeconds <=
                    configuration.maximumClipDurationSeconds + 0.000_001
            else {
                continue
            }

            let poseConfidence = [address, top, impact, finish]
                .map(\.poseConfidence)
                .reduce(0, +) / 4
            let riseQuality = unit(rise / 0.75)
            let speedQuality = unit(postTopSpeed / 1.50)
            let finishQuality = unit((finish.handHeight - baseline) / 0.55)
            let confidence = min(
                0.98,
                0.23 + riseQuality * 0.24 + speedQuality * 0.20 +
                    poseConfidence * 0.20 + finishQuality * 0.11
            )
            guard confidence >= configuration.minimumCandidateConfidence else { continue }

            var clipStart = max(segmentStart, address.timestampSeconds - configuration.preRollSeconds)
            var clipEnd = min(segmentEnd, finish.timestampSeconds + configuration.postRollSeconds)
            expandShortRange(
                start: &clipStart,
                end: &clipEnd,
                minimumDuration: configuration.minimumClipDurationSeconds,
                lowerBound: segmentStart,
                upperBound: segmentEnd
            )
            trimLongRange(
                start: &clipStart,
                end: &clipEnd,
                maximumDuration: configuration.maximumClipDurationSeconds,
                address: address.timestampSeconds,
                finish: finish.timestampSeconds,
                lowerBound: segmentStart,
                upperBound: segmentEnd
            )

            let events = SwingEventTimestamps(
                addressSeconds: address.timestampSeconds,
                topSeconds: top.timestampSeconds,
                impactSeconds: impact.timestampSeconds,
                finishSeconds: finish.timestampSeconds,
                confidence: confidence,
                impactBasis: "automatic pose-motion hand-height crossing; confirm the strike frame"
            )
            guard containsAllEvents(
                startSeconds: clipStart,
                endSeconds: clipEnd,
                events: events
            ) else {
                continue
            }
            result.append(
                Candidate(
                    clip: DetectedSwingClip(
                        startSeconds: clipStart,
                        endSeconds: clipEnd,
                        events: events,
                        confidence: confidence
                    ),
                    rise: rise,
                    postTopSpeed: postTopSpeed
                )
            )
        }
        return result
    }

    private static func suppressOverlappingCandidates(
        _ candidates: [Candidate],
        configuration: SwingClipDetectionConfiguration,
        cancellationCheck: SwingClipCancellationCheck
    ) throws -> [DetectedSwingClip] {
        let ranked = candidates.sorted { first, second in
            if first.clip.confidence != second.clip.confidence {
                return first.clip.confidence > second.clip.confidence
            }
            if first.rise != second.rise { return first.rise > second.rise }
            if first.postTopSpeed != second.postTopSpeed {
                return first.postTopSpeed > second.postTopSpeed
            }
            return first.clip.events.topSeconds < second.clip.events.topSeconds
        }

        var selected: [Candidate] = []
        var selectedByTimeBucket: [Int: [Int]] = [:]
        let bucketWidth = max(1, configuration.maximumClipDurationSeconds)
        let comparisonRadius = max(
            configuration.minimumTopSpacingSeconds,
            configuration.maximumClipDurationSeconds * 2
        )
        for (rankedIndex, candidate) in ranked.enumerated() {
            if rankedIndex.isMultiple(of: 32) { try cancellationCheck() }
            let firstBucket = timeBucket(
                candidate.clip.events.topSeconds - comparisonRadius,
                width: bucketWidth
            )
            let lastBucket = timeBucket(
                candidate.clip.events.topSeconds + comparisonRadius,
                width: bucketWidth
            )
            var isDuplicate = false
            for bucket in firstBucket...lastBucket {
                for selectedIndex in selectedByTimeBucket[bucket, default: []] {
                    let existing = selected[selectedIndex]
                    if abs(existing.clip.events.topSeconds - candidate.clip.events.topSeconds) <
                        configuration.minimumTopSpacingSeconds ||
                        intersectionOverUnion(existing.clip, candidate.clip) >=
                        configuration.overlapThreshold {
                        isDuplicate = true
                        break
                    }
                }
                if isDuplicate { break }
            }
            if !isDuplicate {
                let selectedIndex = selected.count
                selected.append(candidate)
                let bucket = timeBucket(candidate.clip.events.topSeconds, width: bucketWidth)
                selectedByTimeBucket[bucket, default: []].append(selectedIndex)
            }
        }

        var clips = selected.map(\.clip).sorted {
            $0.events.topSeconds < $1.events.topSeconds
        }
        // Padding can overlap even when the event sequences are distinct. Split
        // that padding between swings, while never cutting an event itself.
        guard clips.count > 1 else { return clips.filter(containsAllEvents) }
        for index in 0..<(clips.count - 1) where clips[index].endSeconds > clips[index + 1].startSeconds {
            let earlier = clips[index]
            let later = clips[index + 1]
            guard earlier.events.finishSeconds < later.events.addressSeconds else { continue }
            let boundary = (earlier.events.finishSeconds + later.events.addressSeconds) / 2
            clips[index].endSeconds = min(earlier.endSeconds, boundary)
            clips[index + 1].startSeconds = max(later.startSeconds, boundary)
        }
        return clips.filter(containsAllEvents)
    }

    private struct ForwardTimeWindow {
        private var lowerIndex = 0
        private var upperIndex = 0

        mutating func range(
            in samples: [SwingMotionSample],
            from lowerTime: Double,
            through upperTime: Double
        ) -> Range<Int> {
            while lowerIndex < samples.count,
                  samples[lowerIndex].timestampSeconds < lowerTime {
                lowerIndex += 1
            }
            upperIndex = max(upperIndex, lowerIndex)
            while upperIndex < samples.count,
                  samples[upperIndex].timestampSeconds <= upperTime {
                upperIndex += 1
            }
            return lowerIndex..<upperIndex
        }
    }

    private static func indexedRange(
        in samples: [SwingMotionSample],
        from lowerTime: Double,
        through upperTime: Double
    ) -> Range<Int> {
        lowerBound(in: samples, timestamp: lowerTime)..<upperBound(
            in: samples,
            timestamp: upperTime
        )
    }

    private static func lowerBound(
        in samples: [SwingMotionSample],
        timestamp: Double
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].timestampSeconds < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func upperBound(
        in samples: [SwingMotionSample],
        timestamp: Double
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].timestampSeconds <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func lowerBound(
        in samples: [BodyTrajectorySample],
        timestamp: Double
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func timeBucket(_ timestamp: Double, width: Double) -> Int {
        Int(floor(timestamp / width))
    }

    private static func containsAllEvents(_ clip: DetectedSwingClip) -> Bool {
        containsAllEvents(
            startSeconds: clip.startSeconds,
            endSeconds: clip.endSeconds,
            events: clip.events
        )
    }

    private static func containsAllEvents(
        startSeconds: Double,
        endSeconds: Double,
        events: SwingEventTimestamps
    ) -> Bool {
        [
            events.addressSeconds,
            events.topSeconds,
            events.impactSeconds,
            events.finishSeconds,
        ].allSatisfy { startSeconds <= $0 && $0 <= endSeconds }
    }

    private static func intersectionOverUnion(
        _ first: DetectedSwingClip,
        _ second: DetectedSwingClip
    ) -> Double {
        let intersection = max(
            0,
            min(first.endSeconds, second.endSeconds) -
                max(first.startSeconds, second.startSeconds)
        )
        let union = max(first.endSeconds, second.endSeconds) -
            min(first.startSeconds, second.startSeconds)
        guard union > 0 else { return 0 }
        return intersection / union
    }

    private static func finishScore(
        _ sample: SwingMotionSample,
        baseline: Double,
        impactTime: Double
    ) -> Double {
        (sample.handHeight - baseline) - sample.handSpeed * 0.18 +
            min(sample.timestampSeconds - impactTime, 1.6) * 0.025
    }

    private static func expandShortRange(
        start: inout Double,
        end: inout Double,
        minimumDuration: Double,
        lowerBound: Double,
        upperBound: Double
    ) {
        let missing = minimumDuration - (end - start)
        guard missing > 0 else { return }
        let before = min(missing / 2, start - lowerBound)
        start -= before
        end = min(upperBound, end + missing - before)
        let stillMissing = minimumDuration - (end - start)
        if stillMissing > 0 { start = max(lowerBound, start - stillMissing) }
    }

    private static func trimLongRange(
        start: inout Double,
        end: inout Double,
        maximumDuration: Double,
        address: Double,
        finish: Double,
        lowerBound: Double,
        upperBound: Double
    ) {
        guard end - start > maximumDuration else { return }
        let eventMidpoint = (address + finish) / 2
        start = max(lowerBound, eventMidpoint - maximumDuration / 2)
        end = min(upperBound, start + maximumDuration)
        if end - start < maximumDuration {
            start = max(lowerBound, end - maximumDuration)
        }
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
