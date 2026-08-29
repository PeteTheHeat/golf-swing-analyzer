import AVFoundation
import CoreVideo
import Foundation
import Vision

/// Reads and evaluates only the range selected in the trim UI.
actor VideoPoseExtractor {
    private static let visionJoints: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose),
        (.neck, .neck),
        (.root, .root),
        (.leftEye, .leftEye),
        (.rightEye, .rightEye),
        (.leftEar, .leftEar),
        (.rightEar, .rightEar),
        (.leftShoulder, .leftShoulder),
        (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow),
        (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist),
        (.leftHip, .leftHip),
        (.rightHip, .rightHip),
        (.leftKnee, .leftKnee),
        (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle),
        (.rightAnkle, .rightAnkle),
    ]

    /// All AVFoundation and Vision objects are call-local. Keeping this method
    /// nonisolated avoids sending older-SDK `AVAssetTrack` values across this
    /// actor boundary while preserving actor checking for any future state.
    nonisolated func extract(
        videoURL: URL,
        selectedRange: CMTimeRange,
        sampleRate: Double,
        minimumJointConfidence: Double,
        orientationOverride: PoseVideoOrientation?,
        progress: SwingAnalysisProgress?
    ) async throws -> PoseTrack {
        let asset = AVURLAsset(url: videoURL)
        let assetDuration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw PoseExtractionError.noVideoTrack
        }

        let validRange = try Self.clampedRange(selectedRange, assetDuration: assetDuration)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientation = orientationOverride ?? Self.orientation(for: preferredTransform)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw PoseExtractionError.cannotCreateReader(error.localizedDescription)
        }
        reader.timeRange = validRange

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PoseExtractionError.cannotCreateReader("The video track cannot provide pixel buffers.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw PoseExtractionError.cannotStartReader(
                reader.error?.localizedDescription ?? "Unknown media-reader error"
            )
        }

        let request = VNDetectHumanBodyPoseRequest()
        let sequenceHandler = VNSequenceRequestHandler()
        let interval = 1 / max(1, min(sampleRate, 60))
        let startSeconds = validRange.start.seconds
        let durationSeconds = validRange.duration.seconds
        let endSeconds = startSeconds + durationSeconds
        var nextSampleSeconds = startSeconds
        var frames: [PoseFrame] = []
        var processedFrameCount = 0
        var personSelector = TemporalPosePersonSelector()

        await progress?.update(
            phase: .extractingPose,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Finding body points in the selected swing"
        )

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if let progress {
                try await progress.checkCancellation()
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite, timestamp >= startSeconds - 0.01, timestamp <= endSeconds + 0.01 else {
                continue
            }
            guard timestamp + 0.000_5 >= nextSampleSeconds else { continue }
            nextSampleSeconds = timestamp + interval
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            do {
                try sequenceHandler.perform(
                    [request],
                    on: pixelBuffer,
                    orientation: orientation.cgImagePropertyOrientation
                )
            } catch {
                if Self.isUnrecoverableVisionError(error) {
                    throw PoseExtractionError.visionUnavailable(
                        error.localizedDescription
                    )
                }
                // A bad frame must not discard otherwise usable pose evidence.
                continue
            }

            processedFrameCount += 1
            let candidateFrames = (request.results ?? []).map { observation in
                Self.poseFrame(
                    observation: observation,
                    timestampSeconds: timestamp,
                    orientation: orientation,
                    minimumJointConfidence: minimumJointConfidence
                )
            }.filter { !$0.joints.isEmpty }
            if let frame = personSelector.select(
                from: candidateFrames,
                timestampSeconds: timestamp
            ) {
                frames.append(frame)
            }

            let fraction = max(0, min(0.78, ((timestamp - startSeconds) / durationSeconds) * 0.78))
            await progress?.update(
                phase: .extractingPose,
                fractionCompleted: fraction,
                processedFrameCount: processedFrameCount,
                message: "Finding body points in the selected swing"
            )
        }

        if reader.status == .failed {
            throw PoseExtractionError.readerFailed(
                reader.error?.localizedDescription ?? "Unknown media-reader error"
            )
        }

        let minimumFrames = max(8, Int(min(2, durationSeconds) * min(sampleRate, 10) * 0.5))
        guard frames.count >= minimumFrames else {
            throw PoseExtractionError.insufficientPoseFrames(found: frames.count)
        }

        return PoseTrack(
            selectedRangeStartSeconds: startSeconds,
            selectedRangeDurationSeconds: durationSeconds,
            nominalSampleRate: sampleRate,
            orientation: orientation,
            frames: frames
        )
    }

    private static func poseFrame(
        observation: VNHumanBodyPoseObservation,
        timestampSeconds: Double,
        orientation: PoseVideoOrientation,
        minimumJointConfidence: Double
    ) -> PoseFrame {
        var joints: [PoseJoint: PosePoint] = [:]
        for (joint, visionName) in visionJoints {
            guard let point = try? observation.recognizedPoint(visionName) else { continue }
            let confidence = Double(point.confidence)
            guard confidence >= minimumJointConfidence else { continue }
            joints[joint] = PosePoint(
                x: Double(point.location.x),
                y: 1 - Double(point.location.y),
                confidence: confidence
            )
        }
        return PoseFrame(
            timestampSeconds: timestampSeconds,
            orientation: orientation,
            joints: joints
        )
    }

    private static func clampedRange(
        _ requestedRange: CMTimeRange,
        assetDuration: CMTime
    ) throws -> CMTimeRange {
        let assetSeconds = assetDuration.seconds
        let requestedStart = requestedRange.start.seconds
        let requestedDuration = requestedRange.duration.seconds
        guard assetSeconds.isFinite, assetSeconds > 0,
              requestedStart.isFinite, requestedDuration.isFinite,
              requestedDuration > 0
        else {
            throw PoseExtractionError.invalidRange
        }

        let start = max(0, min(requestedStart, assetSeconds))
        let end = max(start, min(requestedStart + requestedDuration, assetSeconds))
        guard end - start >= 1 else {
            throw PoseExtractionError.invalidRange
        }
        let timescale: CMTimeScale = 600
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            duration: CMTime(seconds: end - start, preferredTimescale: timescale)
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> PoseVideoOrientation {
        let tolerance = 0.01
        func near(_ first: CGFloat, _ second: CGFloat) -> Bool {
            abs(first - second) < tolerance
        }

        switch (transform.a, transform.b, transform.c, transform.d) {
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, -1) && near(d, 0):
            return .right
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, 1) && near(d, 0):
            return .left
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, -1):
            return .down
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, 1):
            return .upMirrored
        case let (a, b, c, d) where near(a, 1) && near(b, 0) && near(c, 0) && near(d, -1):
            return .downMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, 1) && near(d, 0):
            return .rightMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, -1) && near(d, 0):
            return .leftMirrored
        default:
            return .up
        }
    }

    private static func isUnrecoverableVisionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == VNErrorDomain,
              let code = VNErrorCode(rawValue: nsError.code)
        else {
            return false
        }

        switch code {
        case .internalError,
             .invalidModel,
             .dataUnavailable,
             .notImplemented,
             .unsupportedRequest,
             .unsupportedComputeDevice,
             .unsupportedComputeStage:
            return true
        default:
            return false
        }
    }
}

/// Keeps pose extraction locked to one person when Vision reports multiple bodies.
///
/// A candidate must stay near the tracked pelvis and remain a similar apparent
/// size. A transient missing detection does not make the selector jump to a
/// bystander. After a real time gap or several incompatible frames, the old
/// track is discarded and selection starts again from the most prominent body.
struct TemporalPosePersonSelector {
    struct Configuration: Equatable, Sendable {
        var maximumCenterDistanceInBodyScales: Double = 0.90
        var maximumScaleRatio: Double = 2.0
        /// The default does not reset from a frame count because the extractor
        /// runs at different sample rates. Reacquisition instead waits for the
        /// time-gap boundary below, which also creates a safe break in the pose
        /// timeline. Tests and specialized callers can still set a finite cap.
        var maximumConsecutiveMisses: Int = .max
        var maximumGapSeconds: Double = 0.80
    }

    private struct Anchor {
        var center: SIMD2<Double>
        var scale: Double
    }

    private struct Candidate {
        var frame: PoseFrame
        var center: SIMD2<Double>
        var scale: Double
        var quality: Double

        var initialSelectionScore: Double {
            let horizontalDistance = (center.x - 0.5) / 0.55
            let verticalDistance = (center.y - 0.55) / 0.75
            let centrality = 1 - min(1, hypot(horizontalDistance, verticalDistance))
            let visibleSize = min(1, scale / 0.24)
            // Phone swing videos are normally framed around the golfer. Prefer
            // that stable central ROI over a larger person crossing an edge.
            return centrality * 0.55 + quality * 0.30 + visibleSize * 0.15
        }
    }

    private let configuration: Configuration
    private var anchor: Anchor?
    private var lastSelectedTimestamp: Double?
    private var consecutiveMisses = 0

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func select(
        from frames: [PoseFrame],
        timestampSeconds: Double
    ) -> PoseFrame? {
        guard timestampSeconds.isFinite else { return nil }

        if let lastSelectedTimestamp,
           timestampSeconds < lastSelectedTimestamp ||
           timestampSeconds - lastSelectedTimestamp > configuration.maximumGapSeconds {
            reset()
        }

        let candidates = frames.compactMap(Self.candidate(from:))
        guard let anchor else {
            guard let candidate = Self.bestInitialCandidate(from: candidates) else {
                // Preserve the old single-person behavior for a rare partial
                // observation that does not contain enough joints to track.
                if frames.count == 1 {
                    lastSelectedTimestamp = timestampSeconds
                    consecutiveMisses = 0
                    return frames[0]
                }
                registerMiss()
                return nil
            }
            accept(candidate, timestampSeconds: timestampSeconds)
            return candidate.frame
        }

        let matchingCandidates = candidates.filter {
            Self.isPlausibleMatch($0, for: anchor, configuration: configuration)
        }
        guard let candidate = Self.bestContinuityMatch(
            from: matchingCandidates,
            anchor: anchor
        ) else {
            registerMiss()
            return nil
        }

        accept(candidate, timestampSeconds: timestampSeconds)
        return candidate.frame
    }

    private mutating func accept(_ candidate: Candidate, timestampSeconds: Double) {
        anchor = Anchor(center: candidate.center, scale: candidate.scale)
        lastSelectedTimestamp = timestampSeconds
        consecutiveMisses = 0
    }

    private mutating func registerMiss() {
        consecutiveMisses += 1
        if consecutiveMisses >= max(1, configuration.maximumConsecutiveMisses) {
            reset()
        }
    }

    private mutating func reset() {
        anchor = nil
        lastSelectedTimestamp = nil
        consecutiveMisses = 0
    }

    private static func candidate(from frame: PoseFrame) -> Candidate? {
        guard let center = bodyCenter(in: frame),
              let scale = bodyScale(in: frame),
              center.x.isFinite, center.y.isFinite,
              scale.isFinite, scale >= 0.015
        else {
            return nil
        }

        let coverage = min(1, Double(frame.joints.count) / Double(PoseJoint.allCases.count))
        let confidence = min(1, max(0, frame.overallConfidence))
        return Candidate(
            frame: frame,
            center: center,
            scale: scale,
            quality: 0.55 * confidence + 0.45 * coverage
        )
    }

    private static func bodyCenter(in frame: PoseFrame) -> SIMD2<Double>? {
        if let root = frame[.root], root.isFinite {
            return SIMD2(root.x, root.y)
        }
        if let hips = midpoint(frame[.leftHip], frame[.rightHip]) {
            return hips
        }
        if let shoulders = midpoint(frame[.leftShoulder], frame[.rightShoulder]) {
            return shoulders
        }

        let stableJoints: [PoseJoint] = [
            .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip,
        ]
        let points = stableJoints.compactMap { joint -> SIMD2<Double>? in
            guard let point = frame[joint], point.isFinite else { return nil }
            return SIMD2(point.x, point.y)
        }
        guard !points.isEmpty else { return nil }
        return SIMD2(
            median(points.map(\.x)),
            median(points.map(\.y))
        )
    }

    private static func bodyScale(in frame: PoseFrame) -> Double? {
        var segmentLengths: [Double] = []
        appendDistance(from: frame[.neck], to: frame[.root], into: &segmentLengths)
        appendDistance(
            from: midpoint(frame[.leftShoulder], frame[.rightShoulder]),
            to: midpoint(frame[.leftHip], frame[.rightHip]),
            into: &segmentLengths
        )
        appendDistance(
            from: point(frame[.leftShoulder]),
            to: point(frame[.rightShoulder]),
            into: &segmentLengths
        )
        appendDistance(
            from: point(frame[.leftHip]),
            to: point(frame[.rightHip]),
            into: &segmentLengths
        )
        let validSegments = segmentLengths.filter { $0.isFinite && $0 >= 0.015 }
        if !validSegments.isEmpty {
            return median(validSegments)
        }

        let stableJoints: [PoseJoint] = [
            .nose, .neck, .root, .leftShoulder, .rightShoulder,
            .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
        ]
        let points = stableJoints.compactMap { point(frame[$0]) }
        guard points.count >= 2,
              let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max()
        else {
            return nil
        }
        return hypot(maximumX - minimumX, maximumY - minimumY)
    }

    private static func bestInitialCandidate(from candidates: [Candidate]) -> Candidate? {
        candidates.sorted(by: initialCandidatePrecedes).first
    }

    private static func initialCandidatePrecedes(_ first: Candidate, _ second: Candidate) -> Bool {
        if different(first.initialSelectionScore, second.initialSelectionScore) {
            return first.initialSelectionScore > second.initialSelectionScore
        }
        if different(first.scale, second.scale) { return first.scale > second.scale }
        if different(first.quality, second.quality) { return first.quality > second.quality }
        let firstCenterDistance = abs(first.center.x - 0.5) + abs(first.center.y - 0.5)
        let secondCenterDistance = abs(second.center.x - 0.5) + abs(second.center.y - 0.5)
        if different(firstCenterDistance, secondCenterDistance) {
            return firstCenterDistance < secondCenterDistance
        }
        if different(first.center.x, second.center.x) { return first.center.x < second.center.x }
        return first.center.y < second.center.y
    }

    private static func bestContinuityMatch(
        from candidates: [Candidate],
        anchor: Anchor
    ) -> Candidate? {
        candidates.sorted { first, second in
            let firstScore = continuityScore(first, anchor: anchor)
            let secondScore = continuityScore(second, anchor: anchor)
            if different(firstScore, secondScore) { return firstScore < secondScore }
            return initialCandidatePrecedes(first, second)
        }.first
    }

    private static func isPlausibleMatch(
        _ candidate: Candidate,
        for anchor: Anchor,
        configuration: Configuration
    ) -> Bool {
        let referenceScale = max(0.015, max(anchor.scale, candidate.scale))
        let normalizedCenterDistance = distance(candidate.center, anchor.center) / referenceScale
        let scaleRatio = max(anchor.scale, candidate.scale) / max(0.015, min(anchor.scale, candidate.scale))
        return normalizedCenterDistance <= configuration.maximumCenterDistanceInBodyScales &&
            scaleRatio <= configuration.maximumScaleRatio
    }

    private static func continuityScore(_ candidate: Candidate, anchor: Anchor) -> Double {
        let referenceScale = max(0.015, max(anchor.scale, candidate.scale))
        let normalizedCenterDistance = distance(candidate.center, anchor.center) / referenceScale
        let scaleChange = abs(log(candidate.scale / anchor.scale))
        return normalizedCenterDistance + 0.65 * scaleChange + 0.15 * (1 - candidate.quality)
    }

    private static func midpoint(_ first: PosePoint?, _ second: PosePoint?) -> SIMD2<Double>? {
        guard let first = point(first), let second = point(second) else { return nil }
        return (first + second) / 2
    }

    private static func point(_ point: PosePoint?) -> SIMD2<Double>? {
        guard let point, point.isFinite else { return nil }
        return SIMD2(point.x, point.y)
    }

    private static func appendDistance(
        from first: PosePoint?,
        to second: PosePoint?,
        into values: inout [Double]
    ) {
        appendDistance(from: point(first), to: point(second), into: &values)
    }

    private static func appendDistance(
        from first: SIMD2<Double>?,
        to second: SIMD2<Double>?,
        into values: inout [Double]
    ) {
        guard let first, let second else { return }
        values.append(distance(first, second))
    }

    private static func distance(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func different(_ first: Double, _ second: Double) -> Bool {
        abs(first - second) > 0.000_000_1
    }
}
