import AVFoundation
import XCTest
@testable import SwingLab

final class GeometryAndAnalysisTests: XCTestCase {
    func testGeometryMatchesImagePlaneOracle() throws {
        let origin = PosePoint(x: 0, y: 0, confidence: 1)
        let right = PosePoint(x: 1, y: 0, confidence: 1)
        let down = PosePoint(x: 0, y: 1, confidence: 1)
        let upRight = PosePoint(x: 1, y: -1, confidence: 1)

        XCTAssertEqual(
            try XCTUnwrap(PoseGeometry.jointAngle(first: right, vertex: origin, third: down)),
            90,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(PoseGeometry.lineAngle(first: down, second: right)),
            45,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(PoseGeometry.lineAngle(first: right, second: origin)),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(PoseGeometry.inclinationFromVertical(lower: down, upper: origin)),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(PoseGeometry.inclinationFromVertical(lower: origin, upper: upRight)),
            45,
            accuracy: 0.000_001
        )
    }

    func testTemporalSmoothingReducesSingleFrameJitterWithoutMovingTimestamps() throws {
        var frames: [PoseFrame] = []
        for index in 0..<5 {
            let x = index == 2 ? 0.70 : 0.50
            frames.append(
                PoseFrame(
                    timestampSeconds: Double(index) / 10,
                    joints: [.nose: PosePoint(x: x, y: 0.2, confidence: 1)]
                )
            )
        }
        let track = PoseTrack(
            selectedRangeStartSeconds: 0,
            selectedRangeDurationSeconds: 0.4,
            nominalSampleRate: 10,
            orientation: .up,
            frames: frames
        )

        let smoothed = PoseSmoother.smooth(track, radius: 1)
        XCTAssertEqual(smoothed.frames.map(\.timestampSeconds), frames.map(\.timestampSeconds))
        let centerX = try XCTUnwrap(smoothed.frames[2][.nose]?.x)
        XCTAssertGreaterThan(centerX, 0.50)
        XCTAssertLessThan(centerX, 0.70)
    }

    func testSyntheticSwingFindsOrderedEventsAndBodyMetrics() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                sampleRate: 10,
                minimumJointConfidence: 0.30
            )
        )

        XCTAssertLessThan(result.events.addressSeconds, result.events.topSeconds)
        XCTAssertLessThan(result.events.topSeconds, result.events.impactSeconds)
        XCTAssertLessThan(result.events.impactSeconds, result.events.finishSeconds)
        XCTAssertEqual(result.events.topSeconds, 2.5, accuracy: 0.20)
        XCTAssertEqual(result.events.impactSeconds, 3.1, accuracy: 0.25)
        XCTAssertGreaterThan(result.events.confidence, 0.60)

        XCTAssertNotNil(result.metrics.address.leftKneeDegrees)
        XCTAssertNotNil(result.metrics.top.leftElbowDegrees)
        XCTAssertNotNil(result.metrics.address.stanceToShoulders)
        XCTAssertNotNil(result.metrics.impact.shoulderLineDegrees)
        XCTAssertNotNil(result.metrics.impact.hipLineDegrees)
        XCTAssertNotNil(result.metrics.movement.maximumHeadMovementShoulders)
        XCTAssertNotNil(result.metrics.movement.maximumPelvisMovementShoulders)
        XCTAssertNotNil(result.metrics.movement.handPath.takeawayInwardMovementShoulders)
        XCTAssertNotNil(result.metrics.movement.handPath.transitionOutwardLoopShoulders)

        XCTAssertTrue(result.evidence.contains { $0.id == "event-impact" && !$0.joints.isEmpty })
        XCTAssertTrue(result.evidence.contains { $0.id == "hand-takeaway" })
        XCTAssertTrue(result.evidence.contains { $0.id == "hand-transition" })
        XCTAssertTrue(result.findings.contains { $0.id == "hands-inside-pattern" })
        XCTAssertTrue(result.findings.contains { $0.id == "projected-transition-loop" })
        XCTAssertTrue(result.findings.contains { $0.id == "posture-loss-hypothesis" })
        XCTAssertTrue(result.limitations.joined().contains("does not measure the clubface"))
    }

    func testKeyPoseConfidenceUsesOnlyJointsBehindReportedMetrics() throws {
        let metricConfidence = 0.35
        let point: (Double, Double, Double) -> PosePoint = {
            PosePoint(x: $0, y: $1, confidence: $2)
        }
        let metricJoints: [PoseJoint: PosePoint] = [
            .root: point(0.50, 0.60, 0.99),
            .neck: point(0.50, 0.30, 0.99),
            .leftShoulder: point(0.40, 0.36, metricConfidence),
            .rightShoulder: point(0.60, 0.36, metricConfidence),
            .leftElbow: point(0.36, 0.48, metricConfidence),
            .rightElbow: point(0.64, 0.48, metricConfidence),
            .leftWrist: point(0.34, 0.60, metricConfidence),
            .rightWrist: point(0.66, 0.60, metricConfidence),
            .leftHip: point(0.43, 0.58, metricConfidence),
            .rightHip: point(0.57, 0.58, metricConfidence),
            .leftKnee: point(0.42, 0.75, metricConfidence),
            .rightKnee: point(0.58, 0.75, metricConfidence),
            .leftAnkle: point(0.40, 0.92, metricConfidence),
            .rightAnkle: point(0.60, 0.92, metricConfidence),
        ]
        let frames = [0.0, 1.0, 2.0, 3.0].map {
            PoseFrame(
                timestampSeconds: $0,
                joints: metricJoints,
                overallConfidence: 0.99
            )
        }
        let track = PoseTrack(
            selectedRangeStartSeconds: 0,
            selectedRangeDurationSeconds: 3,
            nominalSampleRate: 10,
            orientation: .up,
            frames: frames
        )
        let events = SwingEventTimestamps(
            addressSeconds: 0,
            topSeconds: 1,
            impactSeconds: 2,
            finishSeconds: 3,
            confidence: 0.9
        )

        let output = try SwingMetricsCalculator.calculate(
            track: track,
            events: events,
            context: SwingAnalysisContext(
                cameraView: .downTheLine,
                minimumJointConfidence: 0.30
            )
        )

        XCTAssertEqual(frames[0].overallConfidence, 0.99)
        for keyPose in [
            output.metrics.address,
            output.metrics.top,
            output.metrics.impact,
            output.metrics.finish,
        ] {
            XCTAssertEqual(keyPose.poseConfidence, metricConfidence, accuracy: 0.001)
        }
    }

    func testDirectionalFindingsAreDisabledWithoutDownTheLineEvidence() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(
                cameraView: .faceOn,
                handedness: .right,
                sampleRate: 10,
                minimumJointConfidence: 0.30
            )
        )

        XCTAssertFalse(result.findings.contains { $0.id == "hands-inside-pattern" })
        XCTAssertFalse(result.findings.contains { $0.id == "projected-transition-loop" })
        XCTAssertFalse(result.findings.contains { $0.id == "posture-loss-hypothesis" })
        XCTAssertFalse(result.score.components.contains { $0.id == "projected-hand-path" })
        XCTAssertFalse(result.score.components.contains { $0.id == "posture" })
    }

    func testScoreIsTransparentAndCodable() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )
        let earned = result.score.components.map(\.earnedPoints).reduce(0, +)
        let available = result.score.components.map(\.availablePoints).reduce(0, +)
        XCTAssertEqual(
            result.score.value,
            Int((earned / available * 100).rounded())
        )
        XCTAssertTrue(result.score.explanation.contains("normalized to 100"))

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SwingAnalysisResult.self, from: encoded)
        XCTAssertEqual(decoded, result)
    }

    func testPrimaryEvidencePrefersTheFindingsNamedPhaseOverItsBaseline() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )

        let posture = try XCTUnwrap(
            result.findings.first { $0.id == "posture-loss-hypothesis" }
        )
        let takeaway = try XCTUnwrap(
            result.findings.first { $0.id == "hands-inside-pattern" }
        )
        let transition = try XCTUnwrap(
            result.findings.first { $0.id == "projected-transition-loop" }
        )

        XCTAssertEqual(result.primaryEvidence(for: posture)?.id, "event-impact")
        XCTAssertEqual(result.primaryEvidence(for: takeaway)?.id, "hand-takeaway")
        XCTAssertEqual(result.primaryEvidence(for: transition)?.id, "hand-transition")
    }

    func testManualReviewNavigationSelectsOnlyANearbyFinding() {
        let findings = [
            SwingFinding(
                id: "address-check",
                title: "Address",
                observation: "",
                coachingTip: "",
                phase: .address,
                severity: .info,
                confidence: 1,
                evidenceIDs: []
            ),
            SwingFinding(
                id: "impact-check",
                title: "Impact",
                observation: "",
                coachingTip: "",
                phase: .impact,
                severity: .watch,
                confidence: 1,
                evidenceIDs: []
            ),
        ]
        let evidenceTime: (SwingFinding) -> Double = {
            $0.id == "address-check" ? 1 : 2
        }

        XCTAssertEqual(
            ReviewFindingSelection.findingID(
                nearestTo: 2.03,
                findings: findings,
                evidenceTime: evidenceTime,
                tolerance: 0.05
            ),
            "impact-check"
        )
        XCTAssertNil(
            ReviewFindingSelection.findingID(
                nearestTo: 1.5,
                findings: findings,
                evidenceTime: evidenceTime,
                tolerance: 0.05
            )
        )
    }

    func testProgressActorCooperativelyCancels() async {
        let progress = SwingAnalysisProgress()
        await progress.cancel()
        let snapshot = await progress.currentSnapshot()
        XCTAssertTrue(snapshot.isCancelled)
        do {
            try await progress.checkCancellation()
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected cooperative cancellation path.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSimulatorFixtureProducesReviewableAnalysis() throws {
        let track = SimulatorPoseFixture.make(
            selectedRange: CMTimeRange(
                start: CMTime(seconds: 20, preferredTimescale: 600),
                duration: CMTime(seconds: 12, preferredTimescale: 600)
            ),
            sampleRate: 15
        )
        let rawResult = try SwingAnalysisEngine.analyze(
            poseTrack: track,
            context: SwingAnalysisContext(cameraView: .downTheLine)
        )
        let result = SwingAnalysisPipeline.disclosingSimulatorFixture(in: rawResult)

        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertGreaterThan(result.score.value, 0)
        XCTAssertGreaterThan(result.events.addressSeconds, 20)
        XCTAssertLessThan(result.events.finishSeconds, 32.01)
        XCTAssertLessThanOrEqual(result.analysisConfidence, 0.5)
        XCTAssertLessThanOrEqual(result.events.confidence, 0.5)
        XCTAssertTrue(result.findings.allSatisfy { $0.confidence <= 0.5 })
        XCTAssertTrue(result.findings.allSatisfy {
            $0.caveat?.contains("SIMULATOR FIXTURE ONLY") == true
        })
        XCTAssertTrue(result.evidence.flatMap(\.joints.values).allSatisfy {
            $0.confidence <= 0.5
        })
        XCTAssertTrue(result.poseTrack.frames.allSatisfy { frame in
            frame.overallConfidence <= 0.5
                && frame.joints.values.allSatisfy { $0.confidence <= 0.5 }
        })
        XCTAssertTrue(result.limitations.first?.contains("SIMULATOR FIXTURE ONLY") == true)
    }
    #endif

    private func syntheticSwingTrack() -> PoseTrack {
        let sampleRate = 10.0
        let times = stride(from: 0.0, through: 5.0, by: 1 / sampleRate).map { $0 }
        let frames = times.map { time -> PoseFrame in
            let hands = handPosition(at: time)
            let shoulderCenterX: Double
            if time <= 2.5 {
                shoulderCenterX = 0.55
            } else if time <= 3.1 {
                shoulderCenterX = 0.55 - (time - 2.5) / 0.6 * 0.06
            } else {
                shoulderCenterX = 0.49
            }
            let confidence = 0.95
            let point: (Double, Double) -> PosePoint = {
                PosePoint(x: $0, y: $1, confidence: confidence)
            }
            let leftShoulderX = shoulderCenterX - 0.10
            let rightShoulderX = shoulderCenterX + 0.10
            var joints: [PoseJoint: PosePoint] = [
                .nose: point(shoulderCenterX + 0.03, 0.22),
                .leftEye: point(shoulderCenterX + 0.01, 0.21),
                .rightEye: point(shoulderCenterX + 0.05, 0.21),
                .leftEar: point(shoulderCenterX - 0.01, 0.23),
                .rightEar: point(shoulderCenterX + 0.07, 0.23),
                .neck: point(shoulderCenterX, 0.34),
                .root: point(0.47, 0.62),
                .leftShoulder: point(leftShoulderX, 0.40),
                .rightShoulder: point(rightShoulderX, 0.40),
                .leftElbow: point((leftShoulderX + hands.x - 0.01) / 2, (0.40 + hands.y) / 2),
                .rightElbow: point((rightShoulderX + hands.x + 0.01) / 2, (0.40 + hands.y) / 2),
                .leftWrist: point(hands.x - 0.01, hands.y),
                .rightWrist: point(hands.x + 0.01, hands.y),
                .leftHip: point(0.40, 0.62),
                .rightHip: point(0.54, 0.62),
                .leftKnee: point(0.38, 0.76),
                .rightKnee: point(0.56, 0.76),
                .leftAnkle: point(0.39, 0.91),
                .rightAnkle: point(0.55, 0.91),
            ]
            // Keep a stable setup but make the hand trajectory the dominant phase signal.
            joints[.root] = point(0.47, 0.62)
            return PoseFrame(timestampSeconds: time, joints: joints)
        }
        return PoseTrack(
            selectedRangeStartSeconds: 0,
            selectedRangeDurationSeconds: 5,
            nominalSampleRate: sampleRate,
            orientation: .up,
            frames: frames
        )
    }

    private func handPosition(at time: Double) -> (x: Double, y: Double) {
        if time < 1.5 {
            return (0.67, 0.67)
        }
        if time <= 2.5 {
            let progress = (time - 1.5) / 1.0
            let earlyInwardProgress = min(1, progress * 2)
            return (0.67 - earlyInwardProgress * 0.14, 0.67 - progress * 0.40)
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
