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
    public var measurementConfidence: Double
    public var scope: String
}

public struct SwingMovementMetrics: Codable, Hashable, Sendable {
    public var maximumHeadMovementShoulders: Double?
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

    public init(
        id: String,
        title: String,
        observation: String,
        coachingTip: String,
        phase: SwingPhase,
        severity: SwingFindingSeverity,
        confidence: Double,
        evidenceIDs: [String],
        caveat: String? = nil
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
