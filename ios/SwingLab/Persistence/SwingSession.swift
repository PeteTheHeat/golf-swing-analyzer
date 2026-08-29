import Foundation
import SwiftData

public enum SwingCameraView: String, Codable, CaseIterable, Sendable {
    case faceOn
    case downTheLine
    case unknown

    var displayName: String {
        switch self {
        case .faceOn: "Face on"
        case .downTheLine: "Down the line"
        case .unknown: "Unknown view"
        }
    }
}

public enum GolferHandedness: String, Codable, CaseIterable, Sendable {
    case right
    case left

    var displayName: String {
        switch self {
        case .right: "Right-handed"
        case .left: "Left-handed"
        }
    }
}

enum SwingClub: String, Codable, CaseIterable, Sendable {
    case driver
    case fairwayWood
    case hybrid
    case longIron
    case midIron
    case shortIron
    case wedge
    case putter
    case unknown

    var displayName: String {
        switch self {
        case .driver: "Driver"
        case .fairwayWood: "Fairway wood"
        case .hybrid: "Hybrid"
        case .longIron: "Long iron"
        case .midIron: "Mid iron"
        case .shortIron: "Short iron"
        case .wedge: "Wedge"
        case .putter: "Putter"
        case .unknown: "Club not set"
        }
    }
}

enum SwingAnalysisStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case queued
    case analyzing
    case complete
    case failed

    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .queued: "Waiting"
        case .analyzing: "Analyzing"
        case .complete: "Complete"
        case .failed: "Needs retry"
        }
    }
}

@Model
final class SwingSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var videoRelativePath: String
    var view: String
    var handedness: String
    var club: String
    var rangeStart: TimeInterval
    var rangeEnd: TimeInterval
    var score: Double?
    var status: String
    var analysisJSON: String?
    var referenceID: String?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = .now,
        videoRelativePath: String,
        cameraView: SwingCameraView = .unknown,
        handedness: GolferHandedness = .right,
        club: SwingClub = .unknown,
        rangeStart: TimeInterval = 0,
        rangeEnd: TimeInterval = 0,
        score: Double? = nil,
        status: SwingAnalysisStatus = .draft,
        analysisJSON: String? = nil,
        referenceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.videoRelativePath = videoRelativePath
        self.view = cameraView.rawValue
        self.handedness = handedness.rawValue
        self.club = club.rawValue
        self.rangeStart = max(0, rangeStart)
        self.rangeEnd = max(max(0, rangeStart), rangeEnd)
        self.score = score
        self.status = status.rawValue
        self.analysisJSON = analysisJSON
        self.referenceID = referenceID
    }

    var cameraView: SwingCameraView {
        get { SwingCameraView(rawValue: view) ?? .unknown }
        set { view = newValue.rawValue }
    }

    var golferHandedness: GolferHandedness {
        get { GolferHandedness(rawValue: handedness) ?? .right }
        set { handedness = newValue.rawValue }
    }

    var selectedClub: SwingClub {
        get { SwingClub(rawValue: club) ?? .unknown }
        set { club = newValue.rawValue }
    }

    var analysisStatus: SwingAnalysisStatus {
        get { SwingAnalysisStatus(rawValue: status) ?? .draft }
        set { status = newValue.rawValue }
    }

    var rangeDuration: TimeInterval {
        max(0, rangeEnd - rangeStart)
    }

    func updateRange(start: TimeInterval, end: TimeInterval) {
        rangeStart = max(0, start)
        rangeEnd = max(rangeStart, end)
    }

    func setAnalysis<Value: Encodable>(
        _ value: Value,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SwingSessionCodingError.invalidUTF8
        }
        analysisJSON = string
    }

    func analysis<Value: Decodable>(
        as type: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value? {
        guard let analysisJSON else { return nil }
        guard let data = analysisJSON.data(using: .utf8) else {
            throw SwingSessionCodingError.invalidUTF8
        }
        return try decoder.decode(type, from: data)
    }
}

enum SwingSessionCodingError: Error {
    case invalidUTF8
}
