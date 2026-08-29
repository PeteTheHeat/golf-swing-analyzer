import AVFoundation
import Foundation

public enum SwingAnalysisEngine {
    /// Pure analysis entry point for saved pose tracks and deterministic tests.
    public static func analyze(
        poseTrack: PoseTrack,
        context: SwingAnalysisContext
    ) throws -> SwingAnalysisResult {
        let smoothed = PoseSmoother.smooth(poseTrack)
        let events = try SwingEventDetector.detect(
            in: smoothed,
            minimumConfidence: context.minimumJointConfidence
        )
        let measurement = try SwingMetricsCalculator.calculate(
            track: smoothed,
            events: events,
            context: context
        )
        return assemble(
            poseTrack: smoothed,
            context: context,
            events: events,
            measurement: measurement
        )
    }

    static func assemble(
        poseTrack: PoseTrack,
        context: SwingAnalysisContext,
        events: SwingEventTimestamps,
        measurement: SwingMeasurementOutput
    ) -> SwingAnalysisResult {
        let findings = SwingFindingEngine.findings(
            metrics: measurement.metrics,
            events: events,
            context: context
        )
        let score = SwingFindingEngine.score(metrics: measurement.metrics, context: context)
        let keyPoseConfidence = [
            measurement.metrics.address.poseConfidence,
            measurement.metrics.top.poseConfidence,
            measurement.metrics.impact.poseConfidence,
            measurement.metrics.finish.poseConfidence,
        ].reduce(0, +) / 4
        return SwingAnalysisResult(
            context: context,
            events: events,
            metrics: measurement.metrics,
            findings: findings,
            score: score,
            evidence: measurement.evidence,
            poseTrack: poseTrack,
            analysisConfidence: min(events.confidence, keyPoseConfidence),
            limitations: [
                "Body joints are 2D image-plane estimates from one camera, not true 3D motion or pressure shift.",
                "Impact is inferred from body motion and must be checked against the visible strike frame.",
                "The analysis does not measure the clubface, club path, attack angle, clubhead speed, ball contact, or ball flight.",
                "Inside, posture, and transition notes are confidence-gated hypotheses to test, not diagnoses.",
            ]
        )
    }
}

/// On-device analysis pipeline. One pipeline serializes its own analyses; use one per active session.
public actor SwingAnalysisPipeline {
    private let extractor = VideoPoseExtractor()
    private var activeProgress: SwingAnalysisProgress?

    public init() {}

    public func analyze(
        videoURL: URL,
        range: CMTimeRange,
        context: SwingAnalysisContext,
        progress: SwingAnalysisProgress? = nil
    ) async throws -> SwingAnalysisResult {
        let control = progress ?? SwingAnalysisProgress()
        activeProgress = control
        defer { activeProgress = nil }
        await control.reset()

        do {
            try Task.checkCancellation()
            try await control.checkCancellation()
            let rawTrack: PoseTrack
            var usedSimulatorFixture = false
            do {
                rawTrack = try await extractor.extract(
                    videoURL: videoURL,
                    selectedRange: range,
                    sampleRate: context.sampleRate,
                    minimumJointConfidence: context.minimumJointConfidence,
                    orientationOverride: context.orientationOverride,
                    progress: control
                )
            } catch let error as PoseExtractionError {
                #if DEBUG && targetEnvironment(simulator)
                if case .visionUnavailable = error,
                   SimulatorPoseFixture.isEnabled {
                    usedSimulatorFixture = true
                    await control.update(
                        phase: .extractingPose,
                        fractionCompleted: 0.78,
                        message: "Using simulator pose fixture for UI QA"
                    )
                    rawTrack = SimulatorPoseFixture.make(
                        selectedRange: range,
                        sampleRate: context.sampleRate
                    )
                } else {
                    throw error
                }
                #else
                throw error
                #endif
            }

            try Task.checkCancellation()
            try await control.checkCancellation()
            await control.update(
                phase: .smoothing,
                fractionCompleted: 0.80,
                message: "Stabilizing body points"
            )
            let smoothedTrack = PoseSmoother.smooth(rawTrack)

            try Task.checkCancellation()
            try await control.checkCancellation()
            await control.update(
                phase: .detectingEvents,
                fractionCompleted: 0.84,
                message: "Finding address, top, impact, and finish"
            )
            let events = try SwingEventDetector.detect(
                in: smoothedTrack,
                minimumConfidence: context.minimumJointConfidence
            )

            try Task.checkCancellation()
            try await control.checkCancellation()
            await control.update(
                phase: .measuring,
                fractionCompleted: 0.90,
                message: "Measuring body movement"
            )
            let measurement = try SwingMetricsCalculator.calculate(
                track: smoothedTrack,
                events: events,
                context: context
            )

            try Task.checkCancellation()
            try await control.checkCancellation()
            await control.update(
                phase: .generatingFindings,
                fractionCompleted: 0.96,
                message: "Linking coaching notes to evidence"
            )
            var result = SwingAnalysisEngine.assemble(
                poseTrack: smoothedTrack,
                context: context,
                events: events,
                measurement: measurement
            )
            #if DEBUG && targetEnvironment(simulator)
            if usedSimulatorFixture {
                result = Self.disclosingSimulatorFixture(in: result)
            }
            #endif
            await control.update(
                phase: .complete,
                fractionCompleted: 1,
                message: "Analysis complete"
            )
            return result
        } catch is CancellationError {
            await control.cancel()
            throw CancellationError()
        }
    }

    public func cancelCurrentAnalysis() async {
        await activeProgress?.cancel()
    }

    #if DEBUG && targetEnvironment(simulator)
    static func disclosingSimulatorFixture(
        in analysis: SwingAnalysisResult
    ) -> SwingAnalysisResult {
        let confidenceCeiling = 0.5
        let disclosure = "SIMULATOR FIXTURE ONLY: Pose evidence is synthetic and is not analysis of the selected video."
        var result = analysis

        result.analysisConfidence = min(result.analysisConfidence, confidenceCeiling)
        result.events.confidence = min(result.events.confidence, confidenceCeiling)
        result.metrics.address.poseConfidence = min(
            result.metrics.address.poseConfidence,
            confidenceCeiling
        )
        result.metrics.top.poseConfidence = min(
            result.metrics.top.poseConfidence,
            confidenceCeiling
        )
        result.metrics.impact.poseConfidence = min(
            result.metrics.impact.poseConfidence,
            confidenceCeiling
        )
        result.metrics.finish.poseConfidence = min(
            result.metrics.finish.poseConfidence,
            confidenceCeiling
        )
        result.metrics.movement.handPath.measurementConfidence = min(
            result.metrics.movement.handPath.measurementConfidence,
            confidenceCeiling
        )

        result.findings = result.findings.map { finding in
            var finding = finding
            finding.confidence = min(finding.confidence, confidenceCeiling)
            if finding.caveat?.contains(disclosure) != true {
                finding.caveat = [disclosure, finding.caveat]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            return finding
        }
        result.evidence = result.evidence.map { evidence in
            var evidence = evidence
            evidence.joints = cappedConfidence(
                in: evidence.joints,
                ceiling: confidenceCeiling
            )
            return evidence
        }
        result.poseTrack.frames = result.poseTrack.frames.map { frame in
            var frame = frame
            frame.overallConfidence = min(frame.overallConfidence, confidenceCeiling)
            frame.joints = cappedConfidence(in: frame.joints, ceiling: confidenceCeiling)
            return frame
        }
        if !result.limitations.contains(disclosure) {
            result.limitations.insert(disclosure, at: 0)
        }
        return result
    }

    private static func cappedConfidence(
        in joints: [PoseJoint: PosePoint],
        ceiling: Double
    ) -> [PoseJoint: PosePoint] {
        joints.mapValues { point in
            var point = point
            point.confidence = min(point.confidence, ceiling)
            return point
        }
    }
    #endif
}
