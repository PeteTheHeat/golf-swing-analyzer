import Foundation
import SwiftData
import SwiftUI
struct AnalysisReviewPayload {
    let sessionID: UUID
    let video: ImportedVideo
    let analysis: SwingAnalysisResult
    let clubName: String
    let subject: AnalysisReviewSubject
}

/// Keeps the reviewed video's provenance attached to every screen that can
/// present or compare it. In particular, a user-imported reference must never
/// be relabeled as the golfer's own swing.
enum AnalysisReviewSubject: Equatable, Sendable {
    case personal
    case privateReference(String)
    case reference(String)
    case unknown(String)

    init(session: SwingSession) {
        let label = Self.nonblank(session.referenceDisplayName)
            ?? Self.nonblank(session.title)
            ?? "Untitled reference"

        switch session.sessionOrigin {
        case .personal:
            self = .personal
        case .reference where session.isPrivateReference:
            self = .privateReference(label)
        case .reference:
            if ReferenceSwingDescriptorFactory.make(from: session)?.isDistributionReady == true {
                self = .reference(label)
            } else {
                self = .unknown(label)
            }
        case .unknown:
            self = .unknown(label)
        }
    }

    var reviewLabel: String {
        switch self {
        case .personal:
            "Your swing"
        case .privateReference:
            "Private reference"
        case .reference:
            "Reference"
        case .unknown:
            "Unverified reference"
        }
    }

    var comparisonPaneTitle: String {
        reviewLabel.uppercased()
    }

    var displayName: String? {
        switch self {
        case .personal:
            nil
        case let .privateReference(name),
             let .reference(name),
             let .unknown(name):
            name
        }
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AnalysisFlowFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AnalysisFlowModel: ObservableObject {
    @Published private(set) var isAnalyzing = false
    @Published private(set) var progressSnapshot = SwingAnalysisProgressSnapshot(
        phase: .preparing,
        fractionCompleted: 0,
        processedFrameCount: 0,
        message: "Preparing video"
    )
    @Published private(set) var reviewPayload: AnalysisReviewPayload?
    @Published private(set) var activeSubject: AnalysisReviewSubject = .personal
    @Published var isShowingReview = false
    @Published var failure: AnalysisFlowFailure?

    private let pipeline = SwingAnalysisPipeline()
    private var analysisTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var activeProgress: SwingAnalysisProgress?

    func start(
        video: ImportedVideo,
        selection: TrimSelection,
        input: SwingContextInput,
        modelContext: ModelContext
    ) {
        guard analysisTask == nil else { return }
        guard selection.isValid else {
            failure = AnalysisFlowFailure(
                title: "Adjust the trim",
                message: "Keep the full swing between the trim handles before starting analysis."
            )
            return
        }
        guard input.saveTarget.isValidForAnalysis else {
            failure = AnalysisFlowFailure(
                title: "Add a reference name",
                message: "Give this private reference a name before starting analysis."
            )
            return
        }

        let relativePath = video.fileURL.lastPathComponent
        guard isSafeRelativeFilename(relativePath) else {
            failure = AnalysisFlowFailure(
                title: "Video could not be saved",
                message: "SwingLab could not create a safe local reference for this video. Choose it again."
            )
            return
        }

        let repository = SwingSessionRepository(context: modelContext)
        let session: SwingSession
        do {
            session = try repository.create(
                title: sessionTitle(
                    video: video,
                    club: input.club,
                    saveTarget: input.saveTarget
                ),
                videoRelativePath: relativePath,
                cameraView: SwingCameraView(input.cameraAngle),
                handedness: GolferHandedness(input.handedness),
                club: SwingClub(input.club),
                rangeStart: selection.start,
                rangeEnd: selection.end,
                status: .analyzing,
                saveTarget: input.saveTarget
            )
        } catch {
            failure = AnalysisFlowFailure(
                title: "Analysis could not start",
                message: "SwingLab could not create a local session: \(error.localizedDescription)"
            )
            return
        }

        ImportedMediaOwnership.retainForSession(video.fileURL)
        activeSubject = AnalysisReviewSubject(session: session)

        let analysisContext = SwingAnalysisContext(
            cameraView: SwingCameraView(input.cameraAngle),
            handedness: GolferHandedness(input.handedness)
        )
        let progress = SwingAnalysisProgress()

        failure = nil
        reviewPayload = nil
        isShowingReview = false
        isAnalyzing = true
        progressSnapshot = SwingAnalysisProgressSnapshot(
            phase: .preparing,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Preparing video"
        )
        activeProgress = progress
        startProgressPolling(progress)

        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await pipeline.analyze(
                    videoURL: video.fileURL,
                    range: selection.timeRange,
                    context: analysisContext,
                    progress: progress
                )

                try session.setAnalysis(result)
                session.score = Double(result.score.value)
                session.analysisStatus = .complete
                try modelContext.save()

                progressSnapshot = await progress.currentSnapshot()
                reviewPayload = AnalysisReviewPayload(
                    sessionID: session.id,
                    video: video,
                    analysis: result,
                    clubName: input.club.title,
                    subject: activeSubject
                )
                finishAnalysis()
                isShowingReview = true
            } catch is CancellationError {
                try? await repository.delete(session)
                finishAnalysis()
            } catch {
                session.analysisStatus = .failed
                try? modelContext.save()
                finishAnalysis()
                failure = AnalysisFlowFailure(
                    title: "We could not analyze this swing",
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelAnalysis() {
        guard isAnalyzing else { return }
        analysisTask?.cancel()
        progressSnapshot = SwingAnalysisProgressSnapshot(
            phase: .cancelled,
            fractionCompleted: progressSnapshot.fractionCompleted,
            processedFrameCount: progressSnapshot.processedFrameCount,
            message: "Cancelling analysis",
            isCancelled: true
        )

        let progress = activeProgress
        Task {
            await progress?.cancel()
            await pipeline.cancelCurrentAnalysis()
        }
    }

    func reviewDidClose() {
        guard !isShowingReview else { return }
        reviewPayload = nil
    }

    private func startProgressPolling(_ progress: SwingAnalysisProgress) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await progress.currentSnapshot()
                guard let self else { return }
                progressSnapshot = snapshot
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func finishAnalysis() {
        progressTask?.cancel()
        progressTask = nil
        activeProgress = nil
        analysisTask = nil
        isAnalyzing = false
    }

    private func sessionTitle(
        video: ImportedVideo,
        club: SwingClubInput,
        saveTarget: AnalysisSaveTarget
    ) -> String {
        if case let .privateReference(metadata) = saveTarget {
            let referenceTitle = metadata.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !referenceTitle.isEmpty {
                return referenceTitle
            }
        }

        let filename = video.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return title.isEmpty ? "\(club.title) swing" : title
    }

    private func isSafeRelativeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.contains("/")
            && !filename.contains("\\")
    }
}

private extension SwingCameraView {
    init(_ input: SwingCameraAngle) {
        switch input {
        case .faceOn: self = .faceOn
        case .downTheLine: self = .downTheLine
        }
    }
}

private extension GolferHandedness {
    init(_ input: SwingHandedness) {
        switch input {
        case .right: self = .right
        case .left: self = .left
        }
    }
}

private extension SwingClub {
    init(_ input: SwingClubInput) {
        switch input {
        case .driver: self = .driver
        case .fairwayWood: self = .fairwayWood
        case .hybrid: self = .hybrid
        case .longIron: self = .longIron
        case .midIron: self = .midIron
        case .shortIron: self = .shortIron
        case .wedge: self = .wedge
        case .putter: self = .putter
        case .other: self = .unknown
        }
    }
}
