import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case library
    case analyze
    case settings
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection: AppTab = .library
    @State private var didPerformLaunchMaintenance = false

    var body: some View {
        TabView(selection: $selection) {
            LibraryShellView(onAnalyze: { selection = .analyze })
                .tabItem {
                    Label("Library", systemImage: "rectangle.stack.fill")
                }
                .tag(AppTab.library)

            AnalyzeShellView()
                .tabItem {
                    Label("Analyze", systemImage: "figure.golf")
                }
                .tag(AppTab.analyze)

            SettingsShellView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(AppTab.settings)
        }
        .tint(SwingTheme.coral)
        .toolbarBackground(SwingTheme.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            guard !didPerformLaunchMaintenance else { return }
            didPerformLaunchMaintenance = true

            let repository = SwingSessionRepository(context: modelContext)
            _ = try? repository.recoverInterruptedSessions()
            _ = try? await repository.removeOrphanedImportedVideos()
        }
    }
}

struct LibraryShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwingSession.date, order: .reverse)
    private var sessions: [SwingSession]

    @State private var pendingDeletionID: UUID?
    @State private var isConfirmingDeletion = false
    @State private var deletionFailure: String?

    let onAnalyze: () -> Void

    private var personalSessions: [SwingSession] {
        sessions.filter(\.isPersonalSwing)
    }

    /// Includes malformed explicit origins so they never leak into the user's
    /// personal-session count. Unknown provenance stays visible for deletion.
    private var referenceSessions: [SwingSession] {
        sessions.filter { !$0.isPersonalSwing }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: SwingTheme.Spacing.large) {
                    libraryHeader

                    if personalSessions.isEmpty {
                        EmptyLibraryCard(onAnalyze: onAnalyze)
                    } else {
                        SectionHeading(
                            eyebrow: "Your sessions",
                            title: "Recent swings",
                            trailingText: "\(personalSessions.count) total"
                        )

                        ForEach(personalSessions) { session in
                            sessionRow(session, allowsReview: true)
                        }
                    }

                    if !referenceSessions.isEmpty {
                        SectionHeading(
                            eyebrow: "Reference golfers",
                            title: "Private reference footage",
                            trailingText: "\(referenceSessions.count) total"
                        )

                        ForEach(referenceSessions) { session in
                            sessionRow(
                                session,
                                allowsReview: session.sessionOrigin == .reference
                            )
                        }
                    }
                }
                .padding(.horizontal, SwingTheme.Spacing.screen)
                .padding(.top, SwingTheme.Spacing.medium)
                .padding(.bottom, SwingTheme.Spacing.xLarge)
            }
            .swingScreenBackground()
            .navigationBarHidden(true)
        }
        .confirmationDialog(
            "Delete this swing?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletionID
        ) { sessionID in
            Button("Delete Swing", role: .destructive) {
                deleteSession(withID: sessionID)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes the saved analysis and its local video unless another session uses the same video.")
        }
        .alert(
            "Couldn’t delete swing",
            isPresented: Binding(
                get: { deletionFailure != nil },
                set: { if !$0 { deletionFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionFailure ?? "The swing could not be deleted.")
        }
    }

    private func sessionRow(
        _ session: SwingSession,
        allowsReview: Bool
    ) -> some View {
        HStack(spacing: SwingTheme.Spacing.small) {
            Group {
                if allowsReview,
                   session.analysisStatus == .complete,
                   session.analysisJSON != nil {
                    NavigationLink {
                        SavedSwingReviewView(session: session)
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        SwingSessionCard(session: session, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    SwingSessionCard(session: session, showsDisclosure: false)
                }
            }

            Button(role: .destructive) {
                pendingDeletionID = session.id
                isConfirmingDeletion = true
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SwingTheme.coral)
                    .frame(width: 44, height: 44)
                    .background(SwingTheme.surface, in: Circle())
                    .overlay {
                        Circle().stroke(SwingTheme.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(session.title)")
        }
    }

    private func deleteSession(withID sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            pendingDeletionID = nil
            return
        }

        pendingDeletionID = nil
        Task { @MainActor in
            do {
                try await SwingSessionRepository(context: modelContext).delete(session)
            } catch {
                deletionFailure = error.localizedDescription
            }
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: SwingTheme.Spacing.small) {
            Text("REPLAY CADDIE")
                .font(SwingTheme.Typography.eyebrow)
                .tracking(2.2)
                .foregroundStyle(SwingTheme.coral)

            Text("Build a swing\nyou can repeat.")
                .font(SwingTheme.Typography.hero)
                .foregroundStyle(SwingTheme.cream)
                .fixedSize(horizontal: false, vertical: true)

            Text("Private, frame-by-frame feedback from the videos already on your phone.")
                .font(SwingTheme.Typography.body)
                .foregroundStyle(SwingTheme.mutedText)
                .padding(.top, SwingTheme.Spacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SwingTheme.Spacing.medium)
    }
}

private struct EmptyLibraryCard: View {
    let onAnalyze: () -> Void

    var body: some View {
        SwingCard {
            VStack(alignment: .leading, spacing: SwingTheme.Spacing.large) {
                ZStack {
                    RoundedRectangle(cornerRadius: SwingTheme.Radius.medium, style: .continuous)
                        .fill(SwingTheme.coral.opacity(0.14))
                        .frame(width: 54, height: 54)

                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(SwingTheme.coral)
                }

                VStack(alignment: .leading, spacing: SwingTheme.Spacing.small) {
                    Text("Start with one swing")
                        .font(SwingTheme.Typography.title)
                        .foregroundStyle(SwingTheme.cream)

                    Text("Choose a video, trim it to the swing, then let Replay Caddie find the moments worth reviewing.")
                        .font(SwingTheme.Typography.body)
                        .foregroundStyle(SwingTheme.mutedText)
                }

                Button(action: onAnalyze) {
                    Label("Choose a swing video", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SwingPrimaryButtonStyle())
            }
        }
    }
}

private struct SwingSessionCard: View {
    let session: SwingSession
    let showsDisclosure: Bool

    var body: some View {
        SwingCard {
            HStack(spacing: SwingTheme.Spacing.medium) {
                SessionScoreBadge(score: session.score)

                VStack(alignment: .leading, spacing: SwingTheme.Spacing.xSmall) {
                    Text(session.title)
                        .font(SwingTheme.Typography.headline)
                        .foregroundStyle(SwingTheme.cream)
                        .lineLimit(1)

                    Text(session.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(SwingTheme.Typography.caption)
                        .foregroundStyle(SwingTheme.mutedText)

                    HStack(spacing: SwingTheme.Spacing.small) {
                        if !session.isPersonalSwing {
                            SwingPill(text: provenanceLabel)
                        }
                        SwingPill(text: session.cameraView.displayName)
                        SwingPill(text: session.selectedClub.displayName)
                        if session.analysisStatus != .complete {
                            SwingPill(
                                text: session.analysisStatus.displayName,
                                tint: session.analysisStatus == .failed
                                    ? SwingTheme.coral.opacity(0.24)
                                    : SwingTheme.elevated
                            )
                        }
                    }

                    if session.analysisStatus == .failed {
                        Text("Analysis did not finish. Delete this session, then try the video again.")
                            .font(SwingTheme.Typography.caption)
                            .foregroundStyle(SwingTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SwingTheme.subtleText)
                }
            }
        }
    }

    private var provenanceLabel: String {
        switch session.sessionOrigin {
        case .personal:
            "Your swing"
        case .reference where session.isPrivateReference:
            "Private reference"
        case .reference:
            ReferenceSwingDescriptorFactory.make(from: session)?.isDistributionReady == true
                ? "Reference"
                : "Unverified reference"
        case .unknown:
            "Origin unknown"
        }
    }
}

struct AnalyzeShellView: View {
    var body: some View {
        AnalysisFlowView()
    }
}

private struct SessionScoreBadge: View {
    let score: Double?

    private var normalizedScore: Double {
        min(max((score ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SwingTheme.elevated, lineWidth: 5)
            Circle()
                .trim(from: 0, to: score == nil ? 0 : normalizedScore)
                .stroke(
                    SwingTheme.coral,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if let score {
                Text(score.formatted(.number.precision(.fractionLength(0))))
                    .font(SwingTheme.Typography.score)
                    .foregroundStyle(SwingTheme.cream)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SwingTheme.subtleText)
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel(
            score.map { "Swing score \($0.formatted()) out of 100" }
                ?? "Swing not analyzed"
        )
    }
}

struct AppReleaseIdentity: Equatable {
    let displayName: String
    let version: String?
    let build: String?

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        displayName = Self.nonblankString(
            infoDictionary["CFBundleDisplayName"]
        ) ?? Self.nonblankString(
            infoDictionary["CFBundleName"]
        ) ?? "Replay Caddie"
        version = Self.nonblankString(infoDictionary["CFBundleShortVersionString"])
        build = Self.nonblankString(infoDictionary["CFBundleVersion"])
    }

    var footerText: String {
        switch (version, build) {
        case let (.some(version), .some(build)):
            "\(displayName) \(version) (\(build))"
        case let (.some(version), .none):
            "\(displayName) \(version)"
        case let (.none, .some(build)):
            "\(displayName) build \(build)"
        case (.none, .none):
            displayName
        }
    }

    private static func nonblankString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SettingsShellView: View {
    private let releaseIdentity = AppReleaseIdentity()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SwingTheme.Spacing.large) {
                    SectionHeading(
                        eyebrow: releaseIdentity.displayName,
                        title: "Settings"
                    )

                    SwingCard {
                        VStack(spacing: 0) {
                            SettingsRow(
                                icon: "lock.shield.fill",
                                title: "Local by default",
                                detail: "Videos and analysis stay on this iPhone"
                            )
                            Divider().overlay(SwingTheme.hairline)
                            SettingsRow(
                                icon: "icloud.slash.fill",
                                title: "No cloud sync",
                                detail: "SwiftData is configured without CloudKit"
                            )
                            Divider().overlay(SwingTheme.hairline)
                            SettingsRow(
                                icon: "figure.golf",
                                title: "Analysis guidance",
                                detail: "Use feedback as practice input, not instruction from a coach"
                            )
                        }
                    }

                    Text(releaseIdentity.footerText)
                        .font(SwingTheme.Typography.caption)
                        .foregroundStyle(SwingTheme.subtleText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, SwingTheme.Spacing.screen)
                .padding(.top, SwingTheme.Spacing.large)
                .padding(.bottom, SwingTheme.Spacing.xLarge)
            }
            .swingScreenBackground()
            .navigationBarHidden(true)
        }
    }
}

private struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: SwingTheme.Spacing.medium) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(SwingTheme.success)

            VStack(alignment: .leading, spacing: SwingTheme.Spacing.xSmall) {
                Text("Your swing stays yours")
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.cream)
                Text("No account or full photo-library permission is required for local analysis.")
                    .font(SwingTheme.Typography.caption)
                    .foregroundStyle(SwingTheme.mutedText)
            }
        }
        .padding(.horizontal, SwingTheme.Spacing.small)
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: SwingTheme.Spacing.medium) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(SwingTheme.coral)

            VStack(alignment: .leading, spacing: SwingTheme.Spacing.xSmall) {
                Text(title)
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.cream)
                Text(detail)
                    .font(SwingTheme.Typography.caption)
                    .foregroundStyle(SwingTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, SwingTheme.Spacing.medium)
    }
}

#Preview("Empty library") {
    RootTabView()
        .modelContainer(SwingPersistence.previewContainer)
}
