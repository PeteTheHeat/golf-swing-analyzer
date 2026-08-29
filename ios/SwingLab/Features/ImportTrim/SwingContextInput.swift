import Foundation

public enum SwingCameraAngle: String, CaseIterable, Identifiable, Sendable {
    case downTheLine
    case faceOn

    public var id: Self { self }

    public var title: String {
        switch self {
        case .downTheLine: "Down the line"
        case .faceOn: "Face on"
        }
    }

    public var shortTitle: String {
        switch self {
        case .downTheLine: "Down line"
        case .faceOn: "Face on"
        }
    }

    public var guidance: String {
        switch self {
        case .downTheLine:
            "Camera behind your hands, aimed toward the target"
        case .faceOn:
            "Camera in front of your chest, square to the target line"
        }
    }
}

public enum SwingHandedness: String, CaseIterable, Identifiable, Sendable {
    case right
    case left

    public var id: Self { self }

    public var title: String {
        switch self {
        case .right: "Right-handed"
        case .left: "Left-handed"
        }
    }
}

public enum SwingClubInput: String, CaseIterable, Identifiable, Sendable {
    case driver
    case fairwayWood
    case hybrid
    case longIron
    case midIron
    case shortIron
    case wedge
    case putter
    case other

    public var id: Self { self }

    public var title: String {
        switch self {
        case .driver: "Driver"
        case .fairwayWood: "Fairway wood"
        case .hybrid: "Hybrid"
        case .longIron: "Long iron"
        case .midIron: "Mid iron"
        case .shortIron: "Short iron"
        case .wedge: "Wedge"
        case .putter: "Putter"
        case .other: "Other"
        }
    }
}

/// User-provided facts that change how a swing should be interpreted.
public struct SwingContextInput: Equatable, Sendable {
    public var cameraAngle: SwingCameraAngle
    public var handedness: SwingHandedness
    public var club: SwingClubInput

    public init(
        cameraAngle: SwingCameraAngle = .downTheLine,
        handedness: SwingHandedness = .right,
        club: SwingClubInput = .driver
    ) {
        self.cameraAngle = cameraAngle
        self.handedness = handedness
        self.club = club
    }
}
