import SwiftUI

struct SavedSwingReviewView: View {
    let session: SwingSession

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                statusView(
                    icon: "figure.golf",
                    title: "Opening your swing",
                    detail: "Loading the saved video and analysis…",
                    showsRetry: false
                )

            case let .loaded(payload):
                ReviewWithComparisonView(payload: payload)

            case let .failed(message):
                statusView(
                    icon: "exclamationmark.triangle.fill",
                    title: "This review could not open",
                    detail: message,
                    showsRetry: true
                )
            }
        }
        .task(id: session.id) {
            await loadSession()
        }
    }

    private func statusView(
        icon: String,
        title: String,
        detail: String,
        showsRetry: Bool
    ) -> some View {
        ZStack {
            SwingTheme.deepCanvas.ignoresSafeArea()

            VStack(spacing: SwingTheme.Spacing.large) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(SwingTheme.coral)

                Text(title)
                    .font(SwingTheme.Typography.title)
                    .foregroundStyle(SwingTheme.cream)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(SwingTheme.Typography.body)
                    .foregroundStyle(SwingTheme.mutedText)
                    .multilineTextAlignment(.center)

                if showsRetry {
                    Button {
                        Task { await loadSession() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SwingPrimaryButtonStyle())

                    Button("Back to Library") {
                        dismiss()
                    }
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.mutedText)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(SwingTheme.coral)
                }
            }
            .padding(SwingTheme.Spacing.large)
            .frame(maxWidth: 420)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @MainActor
    private func loadSession() async {
        state = .loading

        do {
            state = .loaded(try await SavedSwingPayloadLoader.load(session: session))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private extension SavedSwingReviewView {
    enum LoadState {
        case loading
        case loaded(AnalysisReviewPayload)
        case failed(String)
    }
}

enum SavedSwingPayloadLoader {
    @MainActor
    static func load(session: SwingSession) async throws -> AnalysisReviewPayload {
        guard session.analysisStatus == .complete else {
            throw SavedReviewError.analysisUnavailable
        }
        guard let analysis = try session.analysis(as: SwingAnalysisResult.self) else {
            throw SavedReviewError.analysisUnavailable
        }
        let videoURL = try await SessionVideoLocator.url(
            forRelativePath: session.videoRelativePath
        )
        let video = try await ImportedVideoValidator.validate(
            storedFileURL: videoURL,
            displayName: session.title
        )
        return AnalysisReviewPayload(
            sessionID: session.id,
            video: video,
            analysis: analysis,
            clubName: session.selectedClub.displayName
        )
    }
}

private enum SessionVideoLocator {
    static func url(forRelativePath relativePath: String) async throws -> URL {
        guard isSafeFilename(relativePath) else {
            throw SavedReviewError.invalidVideoPath
        }
        let directory = try await MediaStorage.shared.importedVideosDirectory()
        return directory.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.contains("/")
            && !filename.contains("\\")
    }
}

enum SavedReviewError: LocalizedError {
    case analysisUnavailable
    case invalidVideoPath

    var errorDescription: String? {
        switch self {
        case .analysisUnavailable:
            "This session does not contain a completed analysis yet."
        case .invalidVideoPath:
            "The saved video reference is invalid. Import the video again to create a new review."
        }
    }
}
