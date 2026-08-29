import Foundation

enum SwingSessionOrigin: String, Codable, CaseIterable, Sendable {
    case personal
    case reference
    case unknown
}

enum ReferenceAllowedUse: String, Codable, CaseIterable, Sendable {
    case privateAnalysisOnly
    case distributionAllowed
    case unknown
}

enum ReferenceRightsStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case verified
    case unknown
}

/// User-entered labels for a locally imported comparison swing. These labels
/// do not confer distribution rights. Local imports remain private and
/// unverified even when the user supplies a golfer name.
public struct PrivateReferenceInput: Equatable, Sendable {
    public var displayName: String
    public var golferName: String

    public init(displayName: String = "", golferName: String = "") {
        self.displayName = displayName
        self.golferName = golferName
    }
}

/// Controls how an analyzed clip is classified in the local library.
public enum AnalysisSaveTarget: Equatable, Sendable {
    case personalSwing
    case privateReference(PrivateReferenceInput)

    var isValidForAnalysis: Bool {
        switch self {
        case .personalSwing:
            true
        case let .privateReference(input):
            !input.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }
}

/// Durable metadata for reference footage. Distribution readiness is derived
/// from explicit, verified rights fields and fails closed for missing or
/// malformed metadata.
struct ReferenceSwingDescriptor: Codable, Hashable, Identifiable, Sendable {
    enum SourceKind: String, Codable, CaseIterable, Sendable {
        case licensedProfessional
        case instructor
        case bestSelf
        case userImported
        case unknown
    }

    let id: String
    var displayName: String
    var golferName: String?
    var sourceKind: SourceKind
    var videoRelativePath: String
    var cameraView: SwingCameraView
    var handedness: GolferHandedness
    var club: SwingClub
    var licenseName: String?
    var attribution: String?
    var sourceURL: URL?
    var licenseURL: URL?
    var allowedUse: ReferenceAllowedUse
    var rightsStatus: ReferenceRightsStatus
    var analysisJSON: String

    var displayLabel: String {
        Self.nonblank(displayName) ?? "Untitled private reference"
    }

    var golferLabel: String? {
        Self.nonblank(golferName)
    }

    var isPrivateOnly: Bool {
        allowedUse == .privateAnalysisOnly
            || sourceKind == .bestSelf
            || sourceKind == .userImported
    }

    var isDistributionReady: Bool {
        guard allowedUse == .distributionAllowed,
              rightsStatus == .verified,
              sourceKind == .licensedProfessional || sourceKind == .instructor,
              Self.nonblank(displayName) != nil,
              Self.nonblank(licenseName) != nil,
              Self.nonblank(attribution) != nil,
              Self.isValidWebURL(sourceURL),
              Self.isValidWebURL(licenseURL) else {
            return false
        }
        return true
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isValidWebURL(_ url: URL?) -> Bool {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http",
              components.host?.isEmpty == false else {
            return false
        }
        return true
    }
}

struct ReferenceSwing: Identifiable {
    let descriptor: ReferenceSwingDescriptor
    let video: ImportedVideo
    let analysis: SwingAnalysisResult

    var id: String { descriptor.id }
}

/// One rights-audited reference shipped as an app resource. Unlike a local
/// import, this record can only load when every distribution field is present
/// and both the analyzed video and analysis JSON are inside the app bundle.
struct BundledReferenceManifestEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var golferName: String?
    var sourceKind: ReferenceSwingDescriptor.SourceKind
    var videoRelativePath: String
    var analysisRelativePath: String
    var cameraView: SwingCameraView
    var handedness: GolferHandedness
    var club: SwingClub
    var licenseName: String
    var attribution: String
    var sourceURL: URL
    var licenseURL: URL
    var allowedUse: ReferenceAllowedUse
    var rightsStatus: ReferenceRightsStatus

    var descriptor: ReferenceSwingDescriptor {
        ReferenceSwingDescriptor(
            id: id,
            displayName: displayName,
            golferName: golferName,
            sourceKind: sourceKind,
            videoRelativePath: videoRelativePath,
            cameraView: cameraView,
            handedness: handedness,
            club: club,
            licenseName: licenseName,
            attribution: attribution,
            sourceURL: sourceURL,
            licenseURL: licenseURL,
            allowedUse: allowedUse,
            rightsStatus: rightsStatus,
            analysisJSON: ""
        )
    }
}

struct BundledReferenceManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var references: [BundledReferenceManifestEntry]
}

enum BundledReferenceCatalogError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case duplicateID(String)
    case invalidRights(String)
    case unsafeResourcePath(String)
    case missingResource(String)
    case invalidAnalysis(String)
    case metadataMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "The bundled reference catalog uses unsupported schema version \(version)."
        case let .duplicateID(id):
            "The bundled reference catalog contains duplicate ID \(id)."
        case let .invalidRights(id):
            "Reference \(id) is missing verified distribution rights."
        case let .unsafeResourcePath(path):
            "Reference resource path \(path) is not a safe bundle-relative path."
        case let .missingResource(path):
            "Reference resource \(path) is missing from this build."
        case let .invalidAnalysis(id):
            "Reference \(id) does not contain a readable swing analysis."
        case let .metadataMismatch(id):
            "Reference \(id) analysis does not match its catalog camera or golfer metadata."
        }
    }
}

enum BundledReferenceCatalog {
    private static let supportedSchemaVersion = 1

    static func entries(in bundle: Bundle = .main) throws -> [BundledReferenceManifestEntry] {
        guard let manifestURL = bundle.url(
            forResource: "ReferenceCatalog",
            withExtension: "json"
        ) else {
            return []
        }
        return try validatedEntries(from: Data(contentsOf: manifestURL))
    }

    static func validatedEntries(from data: Data) throws -> [BundledReferenceManifestEntry] {
        let manifest = try JSONDecoder().decode(BundledReferenceManifest.self, from: data)
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw BundledReferenceCatalogError.unsupportedSchema(manifest.schemaVersion)
        }

        var ids: Set<String> = []
        for entry in manifest.references {
            let trimmedID = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, trimmedID == entry.id else {
                throw BundledReferenceCatalogError.invalidRights(entry.id)
            }
            guard ids.insert(trimmedID).inserted else {
                throw BundledReferenceCatalogError.duplicateID(entry.id)
            }
            guard entry.descriptor.isDistributionReady else {
                throw BundledReferenceCatalogError.invalidRights(entry.id)
            }
            for path in [entry.videoRelativePath, entry.analysisRelativePath]
            where !isSafeRelativeResourcePath(path) {
                throw BundledReferenceCatalogError.unsafeResourcePath(path)
            }
        }
        return manifest.references
    }

    @MainActor
    static func load(
        _ entry: BundledReferenceManifestEntry,
        from bundle: Bundle = .main
    ) async throws -> ReferenceSwing {
        guard entry.descriptor.isDistributionReady else {
            throw BundledReferenceCatalogError.invalidRights(entry.id)
        }
        let videoURL = try resourceURL(
            for: entry.videoRelativePath,
            in: bundle
        )
        let analysisURL = try resourceURL(
            for: entry.analysisRelativePath,
            in: bundle
        )
        let analysisData = try Data(contentsOf: analysisURL)
        guard let analysis = try? JSONDecoder().decode(
            SwingAnalysisResult.self,
            from: analysisData
        ) else {
            throw BundledReferenceCatalogError.invalidAnalysis(entry.id)
        }
        guard analysis.context.cameraView == entry.cameraView,
              analysis.context.handedness == entry.handedness else {
            throw BundledReferenceCatalogError.metadataMismatch(entry.id)
        }

        let video = try await ImportedVideoValidator.validate(
            storedFileURL: videoURL,
            displayName: entry.displayName
        )
        guard analysisTimelineIsValid(
            track: analysis.poseTrack,
            events: analysis.events,
            videoDuration: video.durationSeconds,
            tolerance: video.frameDurationSeconds
        ) else {
            throw BundledReferenceCatalogError.invalidAnalysis(entry.id)
        }

        var descriptor = entry.descriptor
        descriptor.analysisJSON = String(decoding: analysisData, as: UTF8.self)
        return ReferenceSwing(
            descriptor: descriptor,
            video: video,
            analysis: analysis
        )
    }

    static func analysisTimelineIsValid(
        track: PoseTrack,
        events: SwingEventTimestamps,
        videoDuration: Double,
        tolerance: Double
    ) -> Bool {
        let start = track.selectedRangeStartSeconds
        let duration = track.selectedRangeDurationSeconds
        let end = start + duration
        let slack = max(0, tolerance)
        let eventTimes = [
            events.addressSeconds,
            events.topSeconds,
            events.impactSeconds,
            events.finishSeconds,
        ]
        let frameTimes = track.frames.map(\.timestampSeconds)
        guard start.isFinite,
              duration.isFinite,
              end.isFinite,
              videoDuration.isFinite,
              videoDuration > 0,
              duration > 0,
              start >= 0,
              end <= videoDuration + slack,
              !frameTimes.isEmpty,
              frameTimes.allSatisfy(\.isFinite),
              zip(frameTimes, frameTimes.dropFirst()).allSatisfy({ pair in
                  pair.0 <= pair.1
              }),
              frameTimes.allSatisfy({ $0 >= start - slack && $0 <= end + slack }),
              eventTimes.allSatisfy(\.isFinite),
              events.addressSeconds < events.topSeconds,
              events.topSeconds < events.impactSeconds,
              events.impactSeconds < events.finishSeconds
        else {
            return false
        }
        return frameTimes[0] <= events.addressSeconds + slack
            && frameTimes[frameTimes.count - 1] >= events.finishSeconds - slack
            && eventTimes.allSatisfy { time in
            time >= start - slack && time <= end + slack
        }
    }

    static func isSafeRelativeResourcePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            return false
        }
        let components = NSString(string: path).pathComponents
        return !components.contains(".") && !components.contains("..")
    }

    private static func resourceURL(
        for relativePath: String,
        in bundle: Bundle
    ) throws -> URL {
        guard isSafeRelativeResourcePath(relativePath) else {
            throw BundledReferenceCatalogError.unsafeResourcePath(relativePath)
        }
        guard let resourceRoot = bundle.resourceURL?.standardizedFileURL else {
            throw BundledReferenceCatalogError.missingResource(relativePath)
        }
        let url = resourceRoot
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        let rootPath = resourceRoot.path.hasSuffix("/")
            ? resourceRoot.path
            : resourceRoot.path + "/"
        guard url.path.hasPrefix(rootPath),
              FileManager.default.fileExists(atPath: url.path) else {
            throw BundledReferenceCatalogError.missingResource(relativePath)
        }
        return url
    }
}

enum ReferenceSwingDescriptorFactory {
    static func make(from session: SwingSession) -> ReferenceSwingDescriptor? {
        guard session.analysisStatus == .complete,
              let analysisJSON = nonblank(session.analysisJSON) else {
            return nil
        }

        switch session.sessionOrigin {
        case .personal:
            return ReferenceSwingDescriptor(
                id: session.id.uuidString,
                displayName: session.title,
                golferName: "You",
                sourceKind: .bestSelf,
                videoRelativePath: session.videoRelativePath,
                cameraView: session.cameraView,
                handedness: session.golferHandedness,
                club: session.selectedClub,
                licenseName: nil,
                attribution: "Your saved swing",
                sourceURL: nil,
                licenseURL: nil,
                allowedUse: .privateAnalysisOnly,
                rightsStatus: .unverified,
                analysisJSON: analysisJSON
            )

        case .reference:
            return ReferenceSwingDescriptor(
                id: session.id.uuidString,
                displayName: nonblank(session.referenceDisplayName) ?? "",
                golferName: nonblank(session.referenceGolferName),
                sourceKind: strictEnum(
                    session.referenceSourceKind,
                    as: ReferenceSwingDescriptor.SourceKind.self
                ) ?? .unknown,
                videoRelativePath: session.videoRelativePath,
                cameraView: session.cameraView,
                handedness: session.golferHandedness,
                club: session.selectedClub,
                licenseName: nonblank(session.referenceLicenseName),
                attribution: nonblank(session.referenceAttribution),
                sourceURL: validWebURL(session.referenceSourceURL),
                licenseURL: validWebURL(session.referenceLicenseURL),
                allowedUse: strictEnum(
                    session.referenceAllowedUse,
                    as: ReferenceAllowedUse.self
                ) ?? .unknown,
                rightsStatus: strictEnum(
                    session.referenceRightsStatus,
                    as: ReferenceRightsStatus.self
                ) ?? .unknown,
                analysisJSON: analysisJSON
            )

        case .unknown:
            return nil
        }
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stored enum values must match exactly. Trimming an invalid value into a
    /// valid one could accidentally elevate malformed provenance.
    private static func strictEnum<Value: RawRepresentable>(
        _ rawValue: String?,
        as type: Value.Type
    ) -> Value? where Value.RawValue == String {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return Value(rawValue: rawValue)
    }

    private static func validWebURL(_ rawValue: String?) -> URL? {
        guard let rawValue,
              rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http",
              components.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

enum ReferenceMatcher {
    static func compatibilityScore(
        reference: ReferenceSwingDescriptor,
        view: SwingCameraView,
        handedness: GolferHandedness,
        club: SwingClub
    ) -> Int {
        var score = 0
        if reference.cameraView == view { score += 5 }
        if reference.handedness == handedness { score += 3 }
        if reference.club == club { score += 2 }
        return score
    }

    /// Returns a timestamp at the same normalized interval between named events.
    static func alignedTime(
        userTime: Double,
        userEvents: SwingEventTimestamps,
        referenceEvents: SwingEventTimestamps
    ) -> Double {
        let ordered = SwingPhase.allCases
        guard let interval = ordered.adjacentPairs.first(where: { first, second in
            userTime >= userEvents[first] && userTime <= userEvents[second]
        }) else {
            let nearest = ordered.min {
                abs(userEvents[$0] - userTime) < abs(userEvents[$1] - userTime)
            } ?? .impact
            return referenceEvents[nearest]
        }

        let userStart = userEvents[interval.0]
        let userEnd = userEvents[interval.1]
        let fraction = userEnd > userStart
            ? min(1, max(0, (userTime - userStart) / (userEnd - userStart)))
            : 0
        let referenceStart = referenceEvents[interval.0]
        let referenceEnd = referenceEvents[interval.1]
        return referenceStart + (referenceEnd - referenceStart) * fraction
    }
}

private extension Array {
    var adjacentPairs: [(Element, Element)] {
        guard count > 1 else { return [] }
        return zip(self, dropFirst()).map { ($0.0, $0.1) }
    }
}
