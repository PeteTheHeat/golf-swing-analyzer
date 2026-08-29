import Foundation

public enum SwingPhase: String, Codable, CaseIterable, Sendable {
    case address
    case top
    case impact
    case finish
}

public enum SwingFindingSeverity: String, Codable, CaseIterable, Sendable {
    case good
    case info
    case watch
    case priority
}

public struct SwingAnalysisContext: Codable, Hashable, Sendable {
    public var cameraView: SwingCameraView
    public var handedness: GolferHandedness
    public var sampleRate: Double
    public var minimumJointConfidence: Double
    public var orientationOverride: PoseVideoOrientation?

    public init(
        cameraView: SwingCameraView = .unknown,
        handedness: GolferHandedness = .right,
        sampleRate: Double = 15,
        minimumJointConfidence: Double = 0.30,
        orientationOverride: PoseVideoOrientation? = nil
    ) {
        self.cameraView = cameraView
        self.handedness = handedness
        self.sampleRate = max(5, min(sampleRate, 30))
        self.minimumJointConfidence = max(0.1, min(minimumJointConfidence, 0.9))
        self.orientationOverride = orientationOverride
    }
}

public struct SwingEventTimestamps: Codable, Hashable, Sendable {
    public var addressSeconds: Double
    public var topSeconds: Double
    public var impactSeconds: Double
    public var finishSeconds: Double
    public var confidence: Double
    public var impactBasis: String

    public init(
        addressSeconds: Double,
        topSeconds: Double,
        impactSeconds: Double,
        finishSeconds: Double,
        confidence: Double,
        impactBasis: String = "pose hand-height crossing"
    ) {
        self.addressSeconds = addressSeconds
        self.topSeconds = topSeconds
        self.impactSeconds = impactSeconds
        self.finishSeconds = finishSeconds
        self.confidence = confidence
        self.impactBasis = impactBasis
    }

    public subscript(_ phase: SwingPhase) -> Double {
        switch phase {
        case .address: addressSeconds
        case .top: topSeconds
        case .impact: impactSeconds
        case .finish: finishSeconds
        }
    }
}

public struct SwingTimingMetrics: Codable, Hashable, Sendable {
    public var backswingSeconds: Double
    public var downswingSeconds: Double
    public var tempoRatio: Double?
}

public struct SwingEventMetrics: Codable, Hashable, Sendable {
    public var timestampSeconds: Double
    public var leftKneeDegrees: Double?
    public var rightKneeDegrees: Double?
    public var leftElbowDegrees: Double?
    public var rightElbowDegrees: Double?
    public var torsoInclinationDegrees: Double?
    public var shoulderLineDegrees: Double?
    public var hipLineDegrees: Double?
    public var stanceToShoulders: Double?
    public var headShiftShoulders: Double?
    public var pelvisShiftShoulders: Double?
    public var poseConfidence: Double

    public init(
        timestampSeconds: Double,
        leftKneeDegrees: Double? = nil,
        rightKneeDegrees: Double? = nil,
        leftElbowDegrees: Double? = nil,
        rightElbowDegrees: Double? = nil,
        torsoInclinationDegrees: Double? = nil,
        shoulderLineDegrees: Double? = nil,
        hipLineDegrees: Double? = nil,
        stanceToShoulders: Double? = nil,
        headShiftShoulders: Double? = nil,
        pelvisShiftShoulders: Double? = nil,
        poseConfidence: Double
    ) {
        self.timestampSeconds = timestampSeconds
        self.leftKneeDegrees = leftKneeDegrees
        self.rightKneeDegrees = rightKneeDegrees
        self.leftElbowDegrees = leftElbowDegrees
        self.rightElbowDegrees = rightElbowDegrees
        self.torsoInclinationDegrees = torsoInclinationDegrees
        self.shoulderLineDegrees = shoulderLineDegrees
        self.hipLineDegrees = hipLineDegrees
        self.stanceToShoulders = stanceToShoulders
        self.headShiftShoulders = headShiftShoulders
        self.pelvisShiftShoulders = pelvisShiftShoulders
        self.poseConfidence = poseConfidence
    }
}

public struct SwingHandPathMetrics: Codable, Hashable, Sendable {
    /// Positive means the hands moved toward the projected torso center in the takeaway.
    public var takeawayInwardMovementShoulders: Double?
    /// Positive means early-downswing hands were farther from the torso center than on the backswing.
    public var transitionOutwardLoopShoulders: Double?
    /// Exact valid pose sample used for the early-takeaway metric.
    public var takeawaySampleSeconds: Double? = nil
    /// Timestamp of the backswing pose matched to early downswing hand height.
    public var matchedBackswingSeconds: Double? = nil
    /// Exact valid pose sample used for the early-downswing metric.
    public var transitionDownswingSeconds: Double? = nil
    public var measurementConfidence: Double
    public var scope: String
}

public struct SwingMovementMetrics: Codable, Hashable, Sendable {
    public var maximumHeadMovementShoulders: Double?
    public var maximumHeadMovementTimestampSeconds: Double? = nil
    public var maximumPelvisMovementShoulders: Double?
    public var addressToImpactTorsoChangeDegrees: Double?
    public var handPath: SwingHandPathMetrics
}

public struct SwingMetrics: Codable, Hashable, Sendable {
    public var timing: SwingTimingMetrics
    public var address: SwingEventMetrics
    public var top: SwingEventMetrics
    public var impact: SwingEventMetrics
    public var finish: SwingEventMetrics
    public var movement: SwingMovementMetrics
    public var measurementScope: String

    public subscript(_ phase: SwingPhase) -> SwingEventMetrics {
        switch phase {
        case .address: address
        case .top: top
        case .impact: impact
        case .finish: finish
        }
    }
}

public struct SwingEvidence: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var phase: SwingPhase
    public var timestampSeconds: Double
    public var joints: [PoseJoint: PosePoint]
    public var measurements: [String: Double]

    public init(
        id: String,
        label: String? = nil,
        phase: SwingPhase,
        timestampSeconds: Double,
        joints: [PoseJoint: PosePoint],
        measurements: [String: Double] = [:]
    ) {
        self.id = id
        self.label = label ?? phase.rawValue.capitalized
        self.phase = phase
        self.timestampSeconds = timestampSeconds
        self.joints = joints
        self.measurements = measurements
    }
}

/// Describes the evidence geometry that should be emphasized for one coaching
/// finding. The numeric screen boundaries are deliberately stored with the
/// finding so a saved review can explain why the check appeared.
public struct SwingFindingOverlay: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case tempo
        case headMovement
        case kneeGeometry
        case torsoPosture
        case takeawayHandPath
        case transitionHandPath
    }

    public enum Unit: String, Codable, CaseIterable, Sendable {
        case ratio
        case degrees
        case shoulderWidths
    }

    public var kind: Kind
    public var baselineEvidenceID: String?
    public var primaryEvidenceID: String?
    public var highlightedJoints: [PoseJoint]
    public var measurementLabel: String
    public var observedValue: Double?
    public var warningBelow: Double?
    public var warningAbove: Double?
    public var unit: Unit

    public init(
        kind: Kind,
        baselineEvidenceID: String? = nil,
        primaryEvidenceID: String? = nil,
        highlightedJoints: [PoseJoint],
        measurementLabel: String,
        observedValue: Double? = nil,
        warningBelow: Double? = nil,
        warningAbove: Double? = nil,
        unit: Unit
    ) {
        self.kind = kind
        self.baselineEvidenceID = baselineEvidenceID
        self.primaryEvidenceID = primaryEvidenceID
        self.highlightedJoints = highlightedJoints
        self.measurementLabel = measurementLabel
        self.observedValue = observedValue
        self.warningBelow = warningBelow
        self.warningAbove = warningAbove
        self.unit = unit
    }

    var measurementSummary: String? {
        guard let observedValue, observedValue.isFinite else { return nil }
        let observed = formatted(observedValue)
        let screen: String?
        if let warningBelow, warningBelow.isFinite,
           let warningAbove, warningAbove.isFinite {
            screen = "screen band \(formatted(warningBelow))–\(formatted(warningAbove))"
        } else if let warningAbove, warningAbove.isFinite {
            screen = "screen flag ≥ \(formatted(warningAbove))"
        } else if let warningBelow, warningBelow.isFinite {
            screen = "screen flag ≤ \(formatted(warningBelow))"
        } else {
            screen = nil
        }
        return ["\(measurementLabel) \(observed)", screen]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func formatted(_ value: Double) -> String {
        switch unit {
        case .ratio:
            String(format: "%.2f:1", value)
        case .degrees:
            String(format: "%.0f°", value)
        case .shoulderWidths:
            String(format: "%.2f shoulder widths", value)
        }
    }
}

public struct SwingFinding: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var observation: String
    public var coachingTip: String
    public var phase: SwingPhase
    public var severity: SwingFindingSeverity
    /// A 0...1 confidence in the 2D pattern, not in a ball-flight diagnosis.
    public var confidence: Double
    public var evidenceIDs: [String]
    public var caveat: String?
    public var overlay: SwingFindingOverlay?

    public init(
        id: String,
        title: String,
        observation: String,
        coachingTip: String,
        phase: SwingPhase,
        severity: SwingFindingSeverity,
        confidence: Double,
        evidenceIDs: [String],
        caveat: String? = nil,
        overlay: SwingFindingOverlay? = nil
    ) {
        self.id = id
        self.title = title
        self.observation = observation
        self.coachingTip = coachingTip
        self.phase = phase
        self.severity = severity
        self.confidence = max(0, min(confidence, 1))
        self.evidenceIDs = evidenceIDs
        self.caveat = caveat
        self.overlay = overlay
    }
}

extension SwingFinding {
    /// Keeps older saved analyses visually useful after overlay metadata was
    /// introduced. New analyses persist their measured values and boundaries.
    var resolvedOverlay: SwingFindingOverlay? {
        overlay ?? Self.legacyOverlay(for: id)
    }

    private static func legacyOverlay(for id: String) -> SwingFindingOverlay? {
        switch id {
        case "tempo":
            SwingFindingOverlay(
                kind: .tempo,
                baselineEvidenceID: "event-address",
                primaryEvidenceID: "event-top",
                highlightedJoints: [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist],
                measurementLabel: "Tempo ratio",
                unit: .ratio
            )
        case "head-movement", "head-contained":
            SwingFindingOverlay(
                kind: .headMovement,
                baselineEvidenceID: "event-address",
                primaryEvidenceID: "head-peak",
                highlightedJoints: [
                    .nose, .leftEye, .rightEye, .leftEar, .rightEar,
                    .leftShoulder, .rightShoulder,
                ],
                measurementLabel: "Head travel",
                unit: .shoulderWidths
            )
        case "setup-knees":
            SwingFindingOverlay(
                kind: .kneeGeometry,
                primaryEvidenceID: "event-address",
                highlightedJoints: [
                    .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
                ],
                measurementLabel: "Knee-angle difference",
                unit: .degrees
            )
        case "posture-loss-hypothesis":
            SwingFindingOverlay(
                kind: .torsoPosture,
                baselineEvidenceID: "event-address",
                primaryEvidenceID: "event-impact",
                highlightedJoints: [
                    .nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip,
                ],
                measurementLabel: "Torso change",
                unit: .degrees
            )
        case "hands-inside-pattern":
            SwingFindingOverlay(
                kind: .takeawayHandPath,
                baselineEvidenceID: "event-address",
                primaryEvidenceID: "hand-takeaway",
                highlightedJoints: [
                    .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                    .leftWrist, .rightWrist, .leftHip, .rightHip,
                ],
                measurementLabel: "Inward hand travel",
                unit: .shoulderWidths
            )
        case "projected-transition-loop":
            SwingFindingOverlay(
                kind: .transitionHandPath,
                baselineEvidenceID: "hand-transition-backswing",
                primaryEvidenceID: "hand-transition",
                highlightedJoints: [
                    .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                    .leftWrist, .rightWrist, .leftHip, .rightHip,
                ],
                measurementLabel: "Outward hand loop",
                unit: .shoulderWidths
            )
        default:
            nil
        }
    }
}

public struct SwingScoreComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var earnedPoints: Double
    public var availablePoints: Double
    public var explanation: String

    public init(
        id: String,
        title: String,
        earnedPoints: Double,
        availablePoints: Double,
        explanation: String
    ) {
        self.id = id
        self.title = title
        self.earnedPoints = max(0, min(earnedPoints, availablePoints))
        self.availablePoints = max(0, availablePoints)
        self.explanation = explanation
    }
}

public struct SwingScore: Codable, Hashable, Sendable {
    public var value: Int
    public var label: String
    public var components: [SwingScoreComponent]
    public var explanation: String
}

public struct SwingAnalysisResult: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var context: SwingAnalysisContext
    public var events: SwingEventTimestamps
    public var metrics: SwingMetrics
    public var findings: [SwingFinding]
    public var score: SwingScore
    public var evidence: [SwingEvidence]
    public var poseTrack: PoseTrack
    public var analysisConfidence: Double
    public var limitations: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        context: SwingAnalysisContext,
        events: SwingEventTimestamps,
        metrics: SwingMetrics,
        findings: [SwingFinding],
        score: SwingScore,
        evidence: [SwingEvidence],
        poseTrack: PoseTrack,
        analysisConfidence: Double,
        limitations: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.context = context
        self.events = events
        self.metrics = metrics
        self.findings = findings
        self.score = score
        self.evidence = evidence
        self.poseTrack = poseTrack
        self.analysisConfidence = max(0, min(analysisConfidence, 1))
        self.limitations = limitations
    }
}

extension SwingAnalysisResult {
    /// Resolves the evidence frame that best represents the finding's named phase.
    ///
    /// Findings can retain baseline frames for comparison, so the first linked
    /// evidence item is not necessarily the frame the review UI should show.
    func primaryEvidence(for finding: SwingFinding) -> SwingEvidence? {
        let linkedEvidence = finding.evidenceIDs.compactMap { evidenceID in
            evidence.first { $0.id == evidenceID }
        }
        return linkedEvidence.last { $0.phase == finding.phase } ?? linkedEvidence.last
    }

    /// Resolves a visualization against this result's own measurements. This
    /// matters in comparison: the reference pane must never display the user's
    /// metric merely because the user finding selected the overlay kind.
    func resolvedOverlay(for finding: SwingFinding) -> SwingFindingOverlay? {
        guard var overlay = finding.resolvedOverlay else { return nil }
        guard supportsOverlay(overlay.kind) else { return nil }
        overlay.observedValue = measurementValue(for: overlay.kind)
        return overlay
    }

    func supportsOverlay(_ kind: SwingFindingOverlay.Kind) -> Bool {
        switch kind {
        case .torsoPosture, .takeawayHandPath, .transitionHandPath:
            context.cameraView == .downTheLine
        case .tempo, .headMovement, .kneeGeometry:
            true
        }
    }

    private func measurementValue(for kind: SwingFindingOverlay.Kind) -> Double? {
        switch kind {
        case .tempo:
            metrics.timing.tempoRatio
        case .headMovement:
            metrics.movement.maximumHeadMovementShoulders
        case .kneeGeometry:
            if let left = metrics.address.leftKneeDegrees,
               let right = metrics.address.rightKneeDegrees {
                abs(left - right)
            } else {
                nil
            }
        case .torsoPosture:
            metrics.movement.addressToImpactTorsoChangeDegrees
        case .takeawayHandPath:
            metrics.movement.handPath.takeawayInwardMovementShoulders
        case .transitionHandPath:
            metrics.movement.handPath.transitionOutwardLoopShoulders
        }
    }
}

public enum SwingAnalysisError: LocalizedError, Sendable, Equatable {
    case insufficientMotionEvidence
    case invalidEventOrder
    case lowPoseConfidence

    public var errorDescription: String? {
        switch self {
        case .insufficientMotionEvidence:
            "A complete address-to-finish motion was not found in this selection. Adjust the trim so it starts before address and ends after the finish."
        case .invalidEventOrder:
            "The selected motion did not contain a credible address, top, impact, and finish sequence."
        case .lowPoseConfidence:
            "The golfer was not visible clearly enough for a responsible analysis."
        }
    }
}
