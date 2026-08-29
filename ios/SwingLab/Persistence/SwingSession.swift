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

public enum SwingClub: String, Codable, CaseIterable, Sendable {
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
    /// Optional so existing stores migrate without rewriting legacy sessions.
    /// A nil origin is the only legacy value treated as a personal swing.
    var origin: String?
    var referenceSourceKind: String?
    var referenceDisplayName: String?
    var referenceGolferName: String?
    var referenceAttribution: String?
    var referenceLicenseName: String?
    var referenceSourceURL: String?
    var referenceLicenseURL: String?
    var referenceAllowedUse: String?
    var referenceRightsStatus: String?

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
        self.origin = nil
        self.referenceSourceKind = nil
        self.referenceDisplayName = nil
        self.referenceGolferName = nil
        self.referenceAttribution = nil
        self.referenceLicenseName = nil
        self.referenceSourceURL = nil
        self.referenceLicenseURL = nil
        self.referenceAllowedUse = nil
        self.referenceRightsStatus = nil
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

    var sessionOrigin: SwingSessionOrigin {
        guard let origin else { return .personal }
        return SwingSessionOrigin(rawValue: origin) ?? .unknown
    }

    var isPersonalSwing: Bool {
        sessionOrigin == .personal
    }

    var isPrivateReference: Bool {
        guard sessionOrigin == .reference else { return false }
        return referenceAllowedUse == ReferenceAllowedUse.privateAnalysisOnly.rawValue
    }

    var rangeDuration: TimeInterval {
        max(0, rangeEnd - rangeStart)
    }

    func updateRange(start: TimeInterval, end: TimeInterval) {
        rangeStart = max(0, start)
        rangeEnd = max(rangeStart, end)
    }

    func apply(saveTarget: AnalysisSaveTarget) {
        switch saveTarget {
        case .personalSwing:
            origin = SwingSessionOrigin.personal.rawValue
            clearReferenceProvenance()

        case let .privateReference(input):
            origin = SwingSessionOrigin.reference.rawValue
            referenceSourceKind = ReferenceSwingDescriptor.SourceKind.userImported.rawValue
            referenceDisplayName = Self.nonblank(input.displayName)
                ?? Self.nonblank(title)
                ?? "Private reference"
            referenceGolferName = Self.nonblank(input.golferName)
            referenceAttribution = "Imported by you for private analysis"
            referenceLicenseName = nil
            referenceSourceURL = nil
            referenceLicenseURL = nil
            referenceAllowedUse = ReferenceAllowedUse.privateAnalysisOnly.rawValue
            referenceRightsStatus = ReferenceRightsStatus.unverified.rawValue
        }
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

    private func clearReferenceProvenance() {
        referenceSourceKind = nil
        referenceDisplayName = nil
        referenceGolferName = nil
        referenceAttribution = nil
        referenceLicenseName = nil
        referenceSourceURL = nil
        referenceLicenseURL = nil
        referenceAllowedUse = nil
        referenceRightsStatus = nil
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SwingSessionCodingError: Error {
    case invalidUTF8
}
