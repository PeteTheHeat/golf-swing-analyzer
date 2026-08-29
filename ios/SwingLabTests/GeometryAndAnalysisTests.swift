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
        XCTAssertTrue(result.evidence.contains { $0.id == "head-peak" })
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
            context: SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                club: .driver
            )
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
        XCTAssertEqual(decoded.context.club, .driver)
    }

    func testLegacyAnalysisContextWithoutClubDecodesAsUnknown() throws {
        let context = SwingAnalysisContext(
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver
        )
        let encoded = try JSONEncoder().encode(context)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "club")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SwingAnalysisContext.self, from: legacyData)

        XCTAssertEqual(decoded.club, .unknown)
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

    func testDirectionalFindingsPersistSpecificVisualEvidenceAndThresholds() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )
        let takeaway = try XCTUnwrap(
            result.findings.first { $0.id == "hands-inside-pattern" }
        )
        let posture = try XCTUnwrap(
            result.findings.first { $0.id == "posture-loss-hypothesis" }
        )
        let transition = try XCTUnwrap(
            result.findings.first { $0.id == "projected-transition-loop" }
        )

        XCTAssertEqual(takeaway.overlay?.kind, .takeawayHandPath)
        XCTAssertEqual(takeaway.overlay?.baselineEvidenceID, "event-address")
        XCTAssertEqual(takeaway.overlay?.primaryEvidenceID, "hand-takeaway")
        XCTAssertEqual(takeaway.overlay?.warningAbove, 0.28)
        XCTAssertEqual(
            Set(takeaway.overlay?.highlightedJoints ?? []),
            Set([
                .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                .leftWrist, .rightWrist, .leftHip, .rightHip,
            ])
        )

        XCTAssertEqual(posture.overlay?.kind, .torsoPosture)
        XCTAssertEqual(posture.overlay?.baselineEvidenceID, "event-address")
        XCTAssertEqual(posture.overlay?.primaryEvidenceID, "event-impact")
        XCTAssertEqual(posture.overlay?.warningAbove, 10)

        XCTAssertEqual(transition.overlay?.kind, .transitionHandPath)
        XCTAssertEqual(
            transition.overlay?.baselineEvidenceID,
            "hand-transition-backswing"
        )
        XCTAssertEqual(transition.overlay?.primaryEvidenceID, "hand-transition")
        XCTAssertEqual(transition.overlay?.warningAbove, 0.22)
        XCTAssertNotNil(result.metrics.movement.handPath.matchedBackswingSeconds)
        XCTAssertTrue(result.evidence.contains { $0.id == "hand-transition-backswing" })

        let head = try XCTUnwrap(
            result.findings.first { $0.id == "head-movement" || $0.id == "head-contained" }
        )
        XCTAssertEqual(head.overlay?.primaryEvidenceID, "head-peak")
        XCTAssertEqual(
            result.evidence.first { $0.id == "head-peak" }?.timestampSeconds,
            result.metrics.movement.maximumHeadMovementTimestampSeconds
        )
    }

    func testLegacyFindingWithoutOverlayDecodesAndGetsSafeVisualFallback() throws {
        let finding = SwingFinding(
            id: "posture-loss-hypothesis",
            title: "Legacy posture check",
            observation: "Legacy observation",
            coachingTip: "Legacy tip",
            phase: .impact,
            severity: .watch,
            confidence: 0.8,
            evidenceIDs: ["event-address", "event-impact"]
        )
        let encoded = try JSONEncoder().encode(finding)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "overlay")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SwingFinding.self, from: legacyData)
        XCTAssertNil(decoded.overlay)
        XCTAssertEqual(decoded.resolvedOverlay?.kind, .torsoPosture)
        XCTAssertEqual(
            Set(decoded.resolvedOverlay?.highlightedJoints ?? []),
            Set([.nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip])
        )
    }

    func testLegacyAnalysisWithoutNewVisualizationFieldsStillDecodes() throws {
        let result = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                club: .driver
            )
        )
        let encoded = try JSONEncoder().encode(result)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        var context = try XCTUnwrap(object["context"] as? [String: Any])
        context.removeValue(forKey: "club")
        object["context"] = context

        var metrics = try XCTUnwrap(object["metrics"] as? [String: Any])
        var movement = try XCTUnwrap(metrics["movement"] as? [String: Any])
        var handPath = try XCTUnwrap(movement["handPath"] as? [String: Any])
        handPath.removeValue(forKey: "matchedBackswingSeconds")
        handPath.removeValue(forKey: "takeawaySampleSeconds")
        handPath.removeValue(forKey: "transitionDownswingSeconds")
        movement["handPath"] = handPath
        movement.removeValue(forKey: "maximumHeadMovementTimestampSeconds")
        metrics["movement"] = movement
        object["metrics"] = metrics

        var findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        for index in findings.indices {
            findings[index].removeValue(forKey: "overlay")
            if findings[index]["id"] as? String == "projected-transition-loop" {
                findings[index]["evidenceIDs"] = ["event-top", "hand-transition"]
            }
        }
        object["findings"] = findings
        var evidence = try XCTUnwrap(object["evidence"] as? [[String: Any]])
        evidence.removeAll {
            ($0["id"] as? String) == "hand-transition-backswing"
        }
        object["evidence"] = evidence

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SwingAnalysisResult.self, from: legacyData)
        XCTAssertEqual(decoded.context.club, .unknown)
        XCTAssertNil(decoded.metrics.movement.handPath.matchedBackswingSeconds)
        XCTAssertNil(decoded.metrics.movement.handPath.takeawaySampleSeconds)
        XCTAssertNil(decoded.metrics.movement.handPath.transitionDownswingSeconds)
        XCTAssertNil(decoded.metrics.movement.maximumHeadMovementTimestampSeconds)
        XCTAssertTrue(decoded.findings.allSatisfy { $0.overlay == nil })
        let posture = try XCTUnwrap(
            decoded.findings.first { $0.id == "posture-loss-hypothesis" }
        )
        XCTAssertEqual(decoded.resolvedOverlay(for: posture)?.kind, .torsoPosture)
        let transition = try XCTUnwrap(
            decoded.findings.first { $0.id == "projected-transition-loop" }
        )
        XCTAssertEqual(
            transition.resolvedOverlay?.baselineEvidenceID,
            "hand-transition-backswing"
        )
        XCTAssertFalse(
            decoded.evidence.contains { $0.id == "hand-transition-backswing" }
        )
    }

    func testComparisonOverlayUsesEachAnalysisOwnMeasurement() throws {
        let user = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )
        let finding = try XCTUnwrap(
            user.findings.first { $0.id == "hands-inside-pattern" }
        )
        var reference = user
        reference.metrics.movement.handPath.takeawayInwardMovementShoulders = 0.07

        let userValue = try XCTUnwrap(user.resolvedOverlay(for: finding)?.observedValue)
        let referenceValue = try XCTUnwrap(
            reference.resolvedOverlay(for: finding)?.observedValue
        )
        XCTAssertEqual(
            userValue,
            try XCTUnwrap(user.metrics.movement.handPath.takeawayInwardMovementShoulders)
        )
        XCTAssertEqual(referenceValue, 0.07)
        XCTAssertNotEqual(userValue, referenceValue)
    }

    func testDownTheLineFindingIsNotResolvedAgainstFaceOnReference() throws {
        let user = try SwingAnalysisEngine.analyze(
            poseTrack: syntheticSwingTrack(),
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )
        let finding = try XCTUnwrap(
            user.findings.first { $0.id == "hands-inside-pattern" }
        )
        var faceOnReference = user
        faceOnReference.context.cameraView = .faceOn

        XCTAssertFalse(faceOnReference.supportsOverlay(.takeawayHandPath))
        XCTAssertNil(faceOnReference.resolvedOverlay(for: finding))
    }

    func testHandPathEvidenceUsesTheExactValidMetricSamples() throws {
        var track = syntheticSwingTrack()
        let invalidTimes = [1.8, 1.9, 2.7, 2.8]
        for index in track.frames.indices where invalidTimes.contains(where: {
            abs(track.frames[index].timestampSeconds - $0) < 0.001
        }) {
            track.frames[index].joints.removeValue(forKey: .leftWrist)
            track.frames[index].joints.removeValue(forKey: .rightWrist)
        }

        let result = try SwingAnalysisEngine.analyze(
            poseTrack: track,
            context: SwingAnalysisContext(cameraView: .downTheLine, handedness: .right)
        )
        let handPath = result.metrics.movement.handPath
        let takeaway = try XCTUnwrap(
            result.evidence.first { $0.id == "hand-takeaway" }
        )
        let transition = try XCTUnwrap(
            result.evidence.first { $0.id == "hand-transition" }
        )

        XCTAssertEqual(
            takeaway.timestampSeconds,
            try XCTUnwrap(handPath.takeawaySampleSeconds),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transition.timestampSeconds,
            try XCTUnwrap(handPath.transitionDownswingSeconds),
            accuracy: 0.000_001
        )
        XCTAssertNotNil(takeaway.joints[.leftWrist])
        XCTAssertNotNil(takeaway.joints[.rightWrist])
        XCTAssertNotNil(transition.joints[.leftWrist])
        XCTAssertNotNil(transition.joints[.rightWrist])
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

    func testFindingCardEvidenceRevealRespectsReduceMotionAndNamesTheFrame() {
        XCTAssertTrue(
            ReviewEvidenceRevealPolicy.shouldAnimate(
                accessibilityReduceMotion: false
            )
        )
        XCTAssertFalse(
            ReviewEvidenceRevealPolicy.shouldAnimate(
                accessibilityReduceMotion: true
            )
        )
        XCTAssertEqual(
            ReviewEvidenceRevealPolicy.accessibilityAnnouncement(
                findingTitle: "Hands move sharply inward"
            ),
            "Showing Hands move sharply inward evidence frame."
        )
    }

    func testComparisonFrameStepperUsesNativeFrameDurationAndClampsBounds() {
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: 10,
                frameDuration: 1.0 / 30,
                offset: 3,
                rangeStart: 9,
                rangeEnd: 11
            ),
            10.1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: 20,
                frameDuration: 1.0 / 60,
                offset: 3,
                rangeStart: 19,
                rangeEnd: 21
            ),
            20.05,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: 10,
                frameDuration: 1.0 / 30,
                offset: -100,
                rangeStart: 9.8,
                rangeEnd: 10.2
            ),
            9.8,
            accuracy: 0.000_001
        )
        XCTAssertEqual(ComparisonFrameStepper.clampedOffset(-100), -12)
        XCTAssertEqual(ComparisonFrameStepper.clampedOffset(100), 12)
    }

    func testComparisonFrameStepperAllowsAFrameOnTheSelectionBoundary() {
        XCTAssertTrue(
            ComparisonFrameStepper.canStep(
                base: 1.1,
                frameDuration: 0.1,
                offset: 0,
                direction: -1,
                rangeStart: 1,
                rangeEnd: 2
            )
        )
        XCTAssertFalse(
            ComparisonFrameStepper.canStep(
                base: 1,
                frameDuration: 0.1,
                offset: 0,
                direction: -1,
                rangeStart: 1,
                rangeEnd: 2
            )
        )
        XCTAssertFalse(
            ComparisonFrameStepper.canStep(
                base: 1.5,
                frameDuration: 0.1,
                offset: 12,
                direction: 1,
                rangeStart: 1,
                rangeEnd: 3
            )
        )
    }

    func testComparisonFrameStepperUsesSafeFallbacksForInvalidMediaMetadata() {
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: .nan,
                frameDuration: 1.0 / 30,
                offset: 1,
                rangeStart: 4,
                rangeEnd: 8
            ),
            4
        )
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: 12,
                frameDuration: 0,
                offset: -1,
                rangeStart: 4,
                rangeEnd: 8
            ),
            8
        )
        XCTAssertEqual(
            ComparisonFrameStepper.timestamp(
                base: .infinity,
                frameDuration: 1.0 / 30,
                offset: 1,
                rangeStart: 8,
                rangeEnd: 4
            ),
            0
        )
    }

    func testComparisonFrameStepperLabelsVisualAndSpokenOffsets() {
        XCTAssertEqual(ComparisonFrameStepper.label(for: 0), "MATCHED FRAME")
        XCTAssertEqual(ComparisonFrameStepper.label(for: -1), "1 BEFORE")
        XCTAssertEqual(ComparisonFrameStepper.label(for: 99), "12 AFTER")
        XCTAssertEqual(
            ComparisonFrameStepper.accessibilityValue(for: -1),
            "1 frame before the matched frame"
        )
        XCTAssertEqual(
            ComparisonFrameStepper.accessibilityValue(for: 2),
            "2 frames after the matched frame"
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

    func testAutomaticClipDetectorFindsTwoSwingsInALongVideo() throws {
        let clips = SwingClipDetector.detect(
            samples: syntheticMotionTimeline(duration: 24, swingStarts: [3, 14])
        )

        XCTAssertEqual(clips.count, 2)
        let first = try XCTUnwrap(clips.first)
        let second = try XCTUnwrap(clips.last)
        XCTAssertEqual(first.events.topSeconds, 5.1, accuracy: 0.25)
        XCTAssertEqual(first.events.impactSeconds, 5.4, accuracy: 0.25)
        XCTAssertEqual(second.events.topSeconds, 16.1, accuracy: 0.25)
        XCTAssertEqual(second.events.impactSeconds, 16.4, accuracy: 0.25)
        XCTAssertLessThan(first.startSeconds, first.events.addressSeconds)
        XCTAssertGreaterThan(first.endSeconds, first.events.finishSeconds)
        XCTAssertLessThan(first.endSeconds, second.startSeconds)
        XCTAssertGreaterThan(first.confidence, 0.70)
        XCTAssertTrue(clips.allSatisfy { clip in
            clip.events.addressSeconds < clip.events.topSeconds &&
                clip.events.topSeconds < clip.events.impactSeconds &&
                clip.events.impactSeconds < clip.events.finishSeconds &&
                clip.startSeconds <= clip.events.addressSeconds &&
                clip.startSeconds <= clip.events.topSeconds &&
                clip.startSeconds <= clip.events.impactSeconds &&
                clip.startSeconds <= clip.events.finishSeconds &&
                clip.endSeconds >= clip.events.addressSeconds &&
                clip.endSeconds >= clip.events.topSeconds &&
                clip.endSeconds >= clip.events.impactSeconds &&
                clip.endSeconds >= clip.events.finishSeconds
        })
    }

    func testAutomaticClipDetectorCooperativelyCancelsLongDetection() {
        let samples = syntheticMotionTimeline(duration: 300, swingStarts: [3, 140, 280])
        var cancellationChecks = 0

        XCTAssertThrowsError(
            try SwingClipDetector.detect(
                samples: samples,
                cancellationCheck: {
                    cancellationChecks += 1
                    if cancellationChecks == 4 { throw CancellationError() }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(cancellationChecks, 4)
    }

    func testAutomaticClipDetectorRejectsOverlongSlowSwingWithoutClippingEvents() throws {
        let samples = slowSyntheticMotionTimeline()
        let included = SwingClipDetector.detect(samples: samples)
        let clip = try XCTUnwrap(included.first)
        let eventSpan = clip.events.finishSeconds - clip.events.addressSeconds
        XCTAssertGreaterThan(eventSpan, 2.30)
        XCTAssertLessThanOrEqual(clip.startSeconds, clip.events.addressSeconds)
        XCTAssertGreaterThanOrEqual(clip.endSeconds, clip.events.finishSeconds)

        let rejected = SwingClipDetector.detect(
            samples: samples,
            configuration: SwingClipDetectionConfiguration(
                minimumClipDurationSeconds: 2.20,
                maximumClipDurationSeconds: 2.20
            )
        )
        XCTAssertTrue(rejected.isEmpty)
    }

    func testAutomaticClipDetectorScalesAcrossLongIdleVideo() {
        let samples = stride(from: 0.0, through: 1_800.0, by: 0.2).map { time in
            SwingMotionSample(
                timestampSeconds: time,
                handHeight: 0,
                handSpeed: 0.03,
                poseConfidence: 0.95
            )
        }

        XCTAssertTrue(SwingClipDetector.detect(samples: samples).isEmpty)
    }

    func testAutomaticClipDetectorRejectsIdlePoseNoise() {
        let sampleRate = 10.0
        let samples = stride(from: 0.0, through: 20.0, by: 1 / sampleRate).map { time in
            SwingMotionSample(
                timestampSeconds: time,
                handHeight: sin(time * 2.3) * 0.035,
                handSpeed: Int((time * sampleRate).rounded()).isMultiple(of: 37) ? 0.65 : 0.05,
                poseConfidence: 0.94
            )
        }

        XCTAssertTrue(SwingClipDetector.detect(samples: samples).isEmpty)
    }

    func testAutomaticClipDetectorSuppressesOverlappingTopHypotheses() throws {
        let samples = syntheticMotionTimeline(
            duration: 10,
            swingStarts: [3],
            topRipple: true
        )
        let clips = SwingClipDetector.detect(
            samples: samples,
            configuration: SwingClipDetectionConfiguration(
                minimumTopSpacingSeconds: 1.2,
                overlapThreshold: 0.35
            )
        )

        let clip = try XCTUnwrap(clips.first)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clip.events.topSeconds, 5.1, accuracy: 0.30)
        XCTAssertLessThanOrEqual(clip.durationSeconds, 6.5)
    }

    func testAutomaticClipDetectorConsumesExistingPoseTrack() throws {
        let track = syntheticSwingTrack()
        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: track.selectedRangeDurationSeconds,
            minimumConfidence: 0.30
        )

        let clip = try XCTUnwrap(clips.first)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clip.events.topSeconds, 2.5, accuracy: 0.25)
        XCTAssertEqual(clip.events.impactSeconds, 2.7, accuracy: 0.30)
        XCTAssertGreaterThan(clip.confidence, 0.60)
    }

    func testAutomaticClipDetectorBridgesBriefWristOcclusion() throws {
        var track = syntheticSwingTrack()
        track.frames = track.frames.map { frame in
            var modified = frame
            // One wrist commonly disappears behind the club or torso. Around
            // impact, both can disappear for several low-rate observations.
            let frameNumber = Int((frame.timestampSeconds * 10).rounded())
            if frame.timestampSeconds > 0, !frameNumber.isMultiple(of: 5) {
                modified.joints[.rightWrist] = nil
            }
            if (2.7...3.1).contains(frame.timestampSeconds) {
                modified.joints[.leftWrist] = nil
            }
            return modified
        }

        let strictTrajectory = BodyTrajectory.samples(
            from: track.frames,
            minimumConfidence: 0.30
        )

        let discoveryTrajectory = BodyTrajectory.samples(
            from: track.frames,
            minimumConfidence: 0.30,
            maximumSampleGapSeconds: 0.75,
            allowsSingleWristFallback: true
        )
        XCTAssertFalse(discoveryTrajectory.isEmpty)
        XCTAssertLessThan(strictTrajectory.count, discoveryTrajectory.count)
        XCTAssertEqual(Set(discoveryTrajectory.map(\.continuitySegment)), Set([0]))

        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: track.selectedRangeDurationSeconds,
            minimumConfidence: 0.30
        )
        XCTAssertEqual(clips.count, 1)
    }

    func testAutomaticClipDetectorDoesNotSpikeWhenVisibleWristAlternates() throws {
        var completeTrack = syntheticSwingTrack()
        completeTrack.frames = completeTrack.frames.enumerated().map { index, frame in
            guard var left = frame[.leftWrist], var right = frame[.rightWrist] else {
                return frame
            }
            var modified = frame
            let midpoint = SIMD2<Double>((left.x + right.x) / 2, (left.y + right.y) / 2)
            let block = index / 5
            let offset = block.isMultiple(of: 2)
                ? SIMD2<Double>(0.02, 0)
                : SIMD2<Double>(0.04, 0.02)
            left.x = midpoint.x - offset.x / 2
            left.y = midpoint.y - offset.y / 2
            right.x = midpoint.x + offset.x / 2
            right.y = midpoint.y + offset.y / 2
            modified.joints[.leftWrist] = left
            modified.joints[.rightWrist] = right
            return modified
        }
        var alternatingTrack = completeTrack
        alternatingTrack.frames = completeTrack.frames.enumerated().map { index, frame in
            guard index > 0, !index.isMultiple(of: 5) else { return frame }
            var modified = frame
            if index.isMultiple(of: 2) {
                modified.joints[.leftWrist] = nil
            } else {
                modified.joints[.rightWrist] = nil
            }
            return modified
        }

        let complete = BodyTrajectory.samples(
            from: completeTrack.frames,
            minimumConfidence: 0.30,
            maximumSampleGapSeconds: 0.75,
            allowsSingleWristFallback: true
        )
        let alternating = BodyTrajectory.samples(
            from: alternatingTrack.frames,
            minimumConfidence: 0.30,
            maximumSampleGapSeconds: 0.75,
            allowsSingleWristFallback: true
        )
        XCTAssertEqual(alternating.count, complete.count)
        for (expected, actual) in zip(complete, alternating) {
            XCTAssertEqual(actual.hands.x, expected.hands.x, accuracy: 0.000_001)
            XCTAssertEqual(actual.hands.y, expected.hands.y, accuracy: 0.000_001)
            XCTAssertEqual(actual.handSpeed, expected.handSpeed, accuracy: 0.000_001)
        }

        let clips = try SwingClipDetector.detect(
            in: alternatingTrack,
            assetDuration: alternatingTrack.selectedRangeDurationSeconds,
            minimumConfidence: 0.30
        )
        XCTAssertEqual(clips.count, 1)
    }

    func testAutomaticClipDetectorUsesEarlySpeedWhenImpactHandsStayHigh() throws {
        let samples = occludedImpactMotionTimeline()
        let clip = try XCTUnwrap(SwingClipDetector.detect(samples: samples).first)

        XCTAssertEqual(clip.events.topSeconds, 2.0, accuracy: 0.25)
        XCTAssertGreaterThan(clip.events.impactSeconds, clip.events.topSeconds)
        XCTAssertLessThanOrEqual(
            clip.events.impactSeconds,
            clip.events.topSeconds + 0.95 + 0.000_001
        )
        XCTAssertLessThan(clip.events.impactSeconds, 3.4)
        XCTAssertGreaterThan(clip.events.finishSeconds, clip.events.impactSeconds)
    }

    func testAutomaticClipDetectorRejectsSpeedBurstWithoutPostTopReturn() {
        XCTAssertTrue(SwingClipDetector.detect(
            samples: raisedArmSpeedBurstTimeline()
        ).isEmpty)
    }

    func testAutomaticClipDetectorDropsAssetBoundThatWouldCutAnEvent() throws {
        let track = syntheticSwingTrack()
        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: 3.2,
            minimumConfidence: 0.30
        )

        XCTAssertTrue(clips.isEmpty)
    }

    func testAutomaticClipDetectorNormalizesScalePerScene() throws {
        let firstScene = syntheticSwingTrack()
        let secondSceneFrames = firstScene.frames.map { frame in
            scaledFrame(frame, by: 0.58, timestampOffset: 5.1)
        }
        let track = PoseTrack(
            selectedRangeStartSeconds: 0,
            selectedRangeDurationSeconds: 10.1,
            nominalSampleRate: 10,
            orientation: .up,
            frames: firstScene.frames + secondSceneFrames
        )

        let trajectory = BodyTrajectory.samples(from: track.frames, minimumConfidence: 0.30)
        let firstScale = try XCTUnwrap(
            Statistics.median(trajectory.filter { $0.continuitySegment == 0 }.map(\.bodyScale))
        )
        let secondScale = try XCTUnwrap(
            Statistics.median(trajectory.filter { $0.continuitySegment == 1 }.map(\.bodyScale))
        )
        XCTAssertEqual(secondScale / firstScale, 0.58, accuracy: 0.02)
        XCTAssertEqual(Set(trajectory.map(\.continuitySegment)), Set([0, 1]))

        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: 10.1,
            minimumConfidence: 0.30
        )
        XCTAssertEqual(clips.count, 2)
    }

    func testAutomaticClipDetectorRejectsImplausibleStance() throws {
        var track = syntheticSwingTrack()
        track.frames = track.frames.map { frame in
            var modified = frame
            if var leftAnkle = modified[.leftAnkle],
               var rightAnkle = modified[.rightAnkle] {
                leftAnkle.x = 0.495
                rightAnkle.x = 0.505
                modified.joints[.leftAnkle] = leftAnkle
                modified.joints[.rightAnkle] = rightAnkle
            }
            return modified
        }

        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: track.selectedRangeDurationSeconds
        )
        XCTAssertTrue(clips.isEmpty)
    }

    func testAutomaticClipDetectorRejectsHeadTrackingJump() throws {
        var track = syntheticSwingTrack()
        let headJoints: [PoseJoint] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        ]
        track.frames = track.frames.map { frame in
            var modified = frame
            if (2.2...2.7).contains(frame.timestampSeconds) {
                for joint in headJoints {
                    guard var point = modified[joint] else { continue }
                    point.x += 0.35
                    modified.joints[joint] = point
                }
            }
            return modified
        }

        let clips = try SwingClipDetector.detect(
            in: track,
            assetDuration: track.selectedRangeDurationSeconds
        )
        XCTAssertTrue(clips.isEmpty)
    }

    func testPosePersonSelectorStaysWithGolferWhenVisionResultOrderChanges() throws {
        var selector = TemporalPosePersonSelector()
        let golfer = trackingFrame(centerX: 0.30, centerY: 0.60, scale: 0.24, timestamp: 0)
        let bystander = trackingFrame(centerX: 0.78, centerY: 0.58, scale: 0.10, timestamp: 0)

        let initial = try XCTUnwrap(
            selector.select(from: [bystander, golfer], timestampSeconds: 0)
        )
        XCTAssertEqual(try XCTUnwrap(initial[.root]?.x), 0.30, accuracy: 0.000_001)

        let movedGolfer = trackingFrame(
            centerX: 0.32,
            centerY: 0.59,
            scale: 0.23,
            timestamp: 0.1
        )
        let selected = try XCTUnwrap(
            selector.select(from: [
                trackingFrame(centerX: 0.76, centerY: 0.58, scale: 0.13, timestamp: 0.1),
                movedGolfer,
            ], timestampSeconds: 0.1)
        )
        XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), 0.32, accuracy: 0.000_001)
    }

    func testPosePersonSelectorPrefersCenteredGolferOverLargerEdgeBystander() throws {
        var selector = TemporalPosePersonSelector()
        let golfer = trackingFrame(centerX: 0.46, centerY: 0.58, scale: 0.18, timestamp: 0)
        let largerBystander = trackingFrame(
            centerX: 0.86,
            centerY: 0.58,
            scale: 0.30,
            timestamp: 0
        )

        let selected = try XCTUnwrap(
            selector.select(from: [largerBystander, golfer], timestampSeconds: 0)
        )

        XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), 0.46, accuracy: 0.000_001)
    }

    func testPosePersonSelectorDoesNotUseFrameRateDependentDefaultReset() throws {
        var selector = TemporalPosePersonSelector()
        let golfer = trackingFrame(centerX: 0.30, centerY: 0.60, scale: 0.24, timestamp: 0)
        let bystander = trackingFrame(centerX: 0.72, centerY: 0.58, scale: 0.18, timestamp: 0)
        XCTAssertNotNil(selector.select(from: [golfer], timestampSeconds: 0))

        for frameIndex in 1...7 {
            let timestamp = Double(frameIndex) / 15
            XCTAssertNil(
                selector.select(from: [bystander], timestampSeconds: timestamp)
            )
        }

        let returnedGolfer = trackingFrame(
            centerX: 0.31,
            centerY: 0.60,
            scale: 0.23,
            timestamp: 8.0 / 15
        )
        let selected = try XCTUnwrap(
            selector.select(from: [bystander, returnedGolfer], timestampSeconds: 8.0 / 15)
        )
        XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), 0.31, accuracy: 0.000_001)
    }

    func testPosePersonSelectorDoesNotSwitchDuringTransientGolferLoss() throws {
        var selector = TemporalPosePersonSelector(
            configuration: .init(maximumConsecutiveMisses: 3)
        )
        let golfer = trackingFrame(centerX: 0.30, centerY: 0.60, scale: 0.24, timestamp: 0)
        let bystander = trackingFrame(centerX: 0.78, centerY: 0.58, scale: 0.12, timestamp: 0.1)
        XCTAssertNotNil(selector.select(from: [golfer, bystander], timestampSeconds: 0))

        XCTAssertNil(selector.select(from: [bystander], timestampSeconds: 0.1))
        XCTAssertNil(selector.select(from: [bystander], timestampSeconds: 0.2))

        let returnedGolfer = trackingFrame(
            centerX: 0.31,
            centerY: 0.60,
            scale: 0.23,
            timestamp: 0.3
        )
        let selected = try XCTUnwrap(
            selector.select(from: [bystander, returnedGolfer], timestampSeconds: 0.3)
        )
        XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), 0.31, accuracy: 0.000_001)
    }

    func testPosePersonSelectorResetsOnlyAfterConfiguredIncompatibleFrames() throws {
        var selector = TemporalPosePersonSelector(
            configuration: .init(maximumConsecutiveMisses: 2)
        )
        let firstSceneGolfer = trackingFrame(
            centerX: 0.22,
            centerY: 0.60,
            scale: 0.23,
            timestamp: 0
        )
        let secondSceneGolfer = trackingFrame(
            centerX: 0.76,
            centerY: 0.57,
            scale: 0.18,
            timestamp: 0.1
        )
        XCTAssertNotNil(selector.select(from: [firstSceneGolfer], timestampSeconds: 0))

        XCTAssertNil(selector.select(from: [secondSceneGolfer], timestampSeconds: 0.1))
        XCTAssertNil(selector.select(from: [secondSceneGolfer], timestampSeconds: 0.2))

        let reacquired = try XCTUnwrap(
            selector.select(from: [secondSceneGolfer], timestampSeconds: 0.3)
        )
        XCTAssertEqual(try XCTUnwrap(reacquired[.root]?.x), 0.76, accuracy: 0.000_001)
    }

    func testPosePersonSelectorResetsAcrossLongTimestampGap() throws {
        var selector = TemporalPosePersonSelector(
            configuration: .init(maximumGapSeconds: 0.5)
        )
        XCTAssertNotNil(
            selector.select(
                from: [trackingFrame(centerX: 0.20, centerY: 0.60, scale: 0.23, timestamp: 0)],
                timestampSeconds: 0
            )
        )

        let newScene = trackingFrame(
            centerX: 0.80,
            centerY: 0.60,
            scale: 0.20,
            timestamp: 1
        )
        let selected = try XCTUnwrap(
            selector.select(from: [newScene], timestampSeconds: 1)
        )
        XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), 0.80, accuracy: 0.000_001)
    }

    func testPosePersonSelectorPreservesSinglePersonSequence() throws {
        var selector = TemporalPosePersonSelector()
        for index in 0..<6 {
            let timestamp = Double(index) / 10
            let x = 0.40 + Double(index) * 0.006
            let frame = trackingFrame(
                centerX: x,
                centerY: 0.60,
                scale: 0.22,
                timestamp: timestamp
            )
            let selected = try XCTUnwrap(
                selector.select(from: [frame], timestampSeconds: timestamp)
            )
            XCTAssertEqual(try XCTUnwrap(selected[.root]?.x), x, accuracy: 0.000_001)
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

    private func syntheticMotionTimeline(
        duration: Double,
        swingStarts: [Double],
        topRipple: Bool = false
    ) -> [SwingMotionSample] {
        let sampleRate = 10.0
        return stride(from: 0.0, through: duration, by: 1 / sampleRate).map { time in
            var height = sin(time * 1.7) * 0.008
            var speed = 0.04
            for start in swingStarts {
                let local = time - start
                switch local {
                case 0..<1.0:
                    height = 0
                    speed = 0.04
                case 1.0..<2.0:
                    let progress = local - 1.0
                    height = progress * 0.65
                    speed = 0.72
                case 2.0..<2.2:
                    height = 0.65
                    if topRipple {
                        height += local < 2.1 ? 0.018 : -0.012
                    }
                    speed = 0.16
                case 2.2..<2.7:
                    let progress = (local - 2.2) / 0.5
                    height = 0.65 * (1 - progress)
                    speed = 1.45
                case 2.7..<3.5:
                    let progress = (local - 2.7) / 0.8
                    height = progress * 0.55
                    speed = 0.80
                case 3.5..<4.6:
                    height = 0.55
                    speed = 0.10
                default:
                    continue
                }
            }
            return SwingMotionSample(
                timestampSeconds: time,
                handHeight: height,
                handSpeed: speed,
                poseConfidence: 0.95
            )
        }
    }

    private func slowSyntheticMotionTimeline() -> [SwingMotionSample] {
        let sampleRate = 10.0
        return stride(from: 0.0, through: 9.0, by: 1 / sampleRate).map { time in
            let local = time - 1.0
            let height: Double
            let speed: Double
            switch local {
            case ..<0.6:
                height = 0
                speed = 0.04
            case 0.6..<3.0:
                height = (local - 0.6) / 2.4 * 0.66
                speed = 0.34
            case 3.0..<3.3:
                height = 0.66
                speed = 0.14
            case 3.3..<4.1:
                height = 0.66 * (1 - (local - 3.3) / 0.8)
                speed = 1.25
            case 4.1..<5.6:
                height = (local - 4.1) / 1.5 * 0.56
                speed = 0.58
            default:
                height = 0.56
                speed = 0.09
            }
            return SwingMotionSample(
                timestampSeconds: time,
                handHeight: height,
                handSpeed: speed,
                poseConfidence: 0.95
            )
        }
    }

    private func occludedImpactMotionTimeline() -> [SwingMotionSample] {
        stride(from: 0.0, through: 5.0, by: 0.2).map { time in
            let height: Double
            let speed: Double
            switch time {
            case ..<1.0:
                height = 0
                speed = 0.04
            case 1.0..<1.8:
                height = (time - 1.0) / 0.8 * 0.52
                speed = 0.68
            case 1.8..<2.2:
                height = 0.52
                speed = 0.16
            case 2.2..<2.8:
                // Vision can keep the wrists near shoulder height through the
                // strike even though the speed peak remains visible.
                height = 0.43
                speed = time < 2.6 ? 1.30 : 0.82
            case 2.8..<3.8:
                height = 0.46
                speed = 0.18
            case 3.8..<4.2:
                // A late club-lowering motion must not replace the strike.
                height = 0.04
                speed = 1.45
            default:
                height = 0.02
                speed = 0.04
            }
            return SwingMotionSample(
                timestampSeconds: time,
                handHeight: height,
                handSpeed: speed,
                poseConfidence: 0.92
            )
        }
    }

    private func raisedArmSpeedBurstTimeline() -> [SwingMotionSample] {
        stride(from: 0.0, through: 5.0, by: 0.2).map { time in
            let height: Double
            let speed: Double
            switch time {
            case ..<1.0:
                height = 0
                speed = 0.04
            case 1.0..<1.8:
                height = (time - 1.0) / 0.8 * 0.52
                speed = 0.68
            case 1.8..<2.2:
                height = 0.52
                speed = 0.16
            case 2.2..<2.8:
                height = 0.50
                speed = 1.30
            default:
                height = 0.50
                speed = 0.18
            }
            return SwingMotionSample(
                timestampSeconds: time,
                handHeight: height,
                handSpeed: speed,
                poseConfidence: 0.92
            )
        }
    }

    private func trackingFrame(
        centerX: Double,
        centerY: Double,
        scale: Double,
        timestamp: Double
    ) -> PoseFrame {
        let point: (Double, Double) -> PosePoint = {
            PosePoint(x: $0, y: $1, confidence: 0.95)
        }
        return PoseFrame(
            timestampSeconds: timestamp,
            joints: [
                .nose: point(centerX, centerY - scale * 1.15),
                .neck: point(centerX, centerY - scale),
                .root: point(centerX, centerY),
                .leftShoulder: point(centerX - scale * 0.50, centerY - scale * 0.82),
                .rightShoulder: point(centerX + scale * 0.50, centerY - scale * 0.82),
                .leftHip: point(centerX - scale * 0.40, centerY),
                .rightHip: point(centerX + scale * 0.40, centerY),
                .leftKnee: point(centerX - scale * 0.35, centerY + scale * 0.75),
                .rightKnee: point(centerX + scale * 0.35, centerY + scale * 0.75),
                .leftAnkle: point(centerX - scale * 0.35, centerY + scale * 1.50),
                .rightAnkle: point(centerX + scale * 0.35, centerY + scale * 1.50),
            ]
        )
    }

    private func scaledFrame(
        _ frame: PoseFrame,
        by factor: Double,
        timestampOffset: Double
    ) -> PoseFrame {
        let center = SIMD2<Double>(0.5, 0.55)
        let joints = frame.joints.mapValues { point in
            let original = SIMD2<Double>(point.x, point.y)
            let scaled = center + (original - center) * factor
            return PosePoint(
                x: scaled.x,
                y: scaled.y,
                confidence: point.confidence
            )
        }
        return PoseFrame(
            timestampSeconds: frame.timestampSeconds + timestampOffset,
            joints: joints
        )
    }
}
