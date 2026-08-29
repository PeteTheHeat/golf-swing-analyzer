import Foundation
/// Durable metadata for footage that SwingLab is allowed to distribute or that
/// the golfer imports as their own reference.
struct ReferenceSwingDescriptor: Codable, Hashable, Identifiable, Sendable {
    enum SourceKind: String, Codable, Sendable {
        case licensedProfessional
        case instructor
        case bestSelf
        case userImported
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
    var analysisJSON: String

    var isDistributionReady: Bool {
        switch sourceKind {
        case .licensedProfessional, .instructor:
            return licenseName?.isEmpty == false && attribution?.isEmpty == false
        case .bestSelf, .userImported:
            return true
        }
    }
}

struct ReferenceSwing: Identifiable {
    let descriptor: ReferenceSwingDescriptor
    let video: ImportedVideo
    let analysis: SwingAnalysisResult

    var id: String { descriptor.id }
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
