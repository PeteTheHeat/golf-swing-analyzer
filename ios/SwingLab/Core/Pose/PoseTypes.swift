import Foundation
import ImageIO

/// The orientation applied before Vision evaluates a video frame.
public enum PoseVideoOrientation: String, Codable, CaseIterable, Sendable {
    case up
    case upMirrored
    case down
    case downMirrored
    case left
    case leftMirrored
    case right
    case rightMirrored

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        }
    }
}

/// Body joints that are stable across Apple's 2D human-pose revisions.
public enum PoseJoint: String, Codable, CaseIterable, Sendable {
    case nose
    case neck
    case root
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

/// A normalized point in display coordinates: origin at the top-left, x right, y down.
public struct PosePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && confidence.isFinite
    }
}

/// One timestamped pose observation. Missing or low-confidence joints are omitted.
public struct PoseFrame: Codable, Hashable, Sendable, Identifiable {
    public var timestampSeconds: Double
    public var orientation: PoseVideoOrientation
    public var joints: [PoseJoint: PosePoint]
    public var overallConfidence: Double

    public init(
        timestampSeconds: Double,
        orientation: PoseVideoOrientation = .up,
        joints: [PoseJoint: PosePoint],
        overallConfidence: Double? = nil
    ) {
        self.timestampSeconds = timestampSeconds
        self.orientation = orientation
        self.joints = joints
        self.overallConfidence = overallConfidence ?? Self.medianConfidence(in: joints)
    }

    public var id: Double { timestampSeconds }

    public subscript(_ joint: PoseJoint) -> PosePoint? {
        joints[joint]
    }

    public func meanConfidence(for requiredJoints: [PoseJoint]) -> Double? {
        let values = requiredJoints.compactMap { joints[$0]?.confidence }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func medianConfidence(in joints: [PoseJoint: PosePoint]) -> Double {
        let values = joints.values.map(\.confidence).sorted()
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

/// Pose data sampled only from the range selected by the golfer.
public struct PoseTrack: Codable, Hashable, Sendable {
    public var selectedRangeStartSeconds: Double
    public var selectedRangeDurationSeconds: Double
    public var nominalSampleRate: Double
    public var orientation: PoseVideoOrientation
    public var frames: [PoseFrame]

    public init(
        selectedRangeStartSeconds: Double,
        selectedRangeDurationSeconds: Double,
        nominalSampleRate: Double,
        orientation: PoseVideoOrientation,
        frames: [PoseFrame]
    ) {
        self.selectedRangeStartSeconds = selectedRangeStartSeconds
        self.selectedRangeDurationSeconds = selectedRangeDurationSeconds
        self.nominalSampleRate = nominalSampleRate
        self.orientation = orientation
        self.frames = frames.sorted { $0.timestampSeconds < $1.timestampSeconds }
    }

    public var averageConfidence: Double {
        guard !frames.isEmpty else { return 0 }
        return frames.map(\.overallConfidence).reduce(0, +) / Double(frames.count)
    }
}

public enum PoseExtractionError: LocalizedError, Sendable, Equatable {
    case noVideoTrack
    case invalidRange
    case visionUnavailable(String)
    case cannotCreateReader(String)
    case cannotStartReader(String)
    case readerFailed(String)
    case insufficientPoseFrames(found: Int)

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            "The selected asset does not contain a video track."
        case .invalidRange:
            "Select at least one second of valid video."
        case let .visionUnavailable(message):
            #if targetEnvironment(simulator)
            "The iOS Simulator does not include the body-pose model required for this analysis. Run Replay Caddie on a physical iPhone. System detail: \(message)"
            #else
            "Apple Vision could not start body-pose analysis. Restart Replay Caddie and try again. System detail: \(message)"
            #endif
        case let .cannotCreateReader(message):
            "The video reader could not be created: \(message)"
        case let .cannotStartReader(message):
            "The selected video range could not be read: \(message)"
        case let .readerFailed(message):
            "Video reading stopped before analysis finished: \(message)"
        case let .insufficientPoseFrames(found):
            "A stable body pose was found in only \(found) frames. Keep the full golfer visible and use a brighter clip."
        }
    }
}
