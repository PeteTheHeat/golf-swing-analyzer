import SwiftData
import SwiftUI

/// Adds a rights-aware reference picker around the core review screen.
struct ReviewWithComparisonView: View {
    let payload: AnalysisReviewPayload

    @Query(sort: \SwingSession.date, order: .reverse)
    private var sessions: [SwingSession]

    @State private var isShowingReferencePicker = false
    @State private var isLoadingReference = false
    @State private var reference: ReferenceSwing?
    @State private var failure: ComparisonLoadFailure?
    @State private var comparisonFindingID: String?
    @State private var bundledReferences: [BundledReferenceManifestEntry] = []
    @State private var catalogFailureMessage: String?
    @State private var didLoadCatalog = false

    private var privateReferenceCandidates: [ComparisonCandidate] {
        sortedCandidates(
            sessions.filter { $0.isPrivateReference }
        )
    }

    private var bestSwingCandidates: [ComparisonCandidate] {
        sortedCandidates(
            sessions.filter { $0.isPersonalSwing }
        )
    }

    private var verifiedSessionCandidates: [ComparisonCandidate] {
        sortedCandidates(
            sessions.filter {
                $0.sessionOrigin == .reference && !$0.isPrivateReference
            }
        )
        .filter(\.descriptor.isDistributionReady)
    }

    private var bundledReferenceCandidates: [BundledReferenceManifestEntry] {
        bundledReferences.sorted { first, second in
            let firstScore = compatibilityScore(for: first.descriptor)
            let secondScore = compatibilityScore(for: second.descriptor)
            return firstScore == secondScore
                ? first.displayName < second.displayName
                : firstScore > secondScore
        }
    }

    var body: some View {
        SwingReviewView(
            video: payload.video,
            analysis: payload.analysis,
            clubName: payload.clubName,
            subjectLabel: payload.subject.reviewLabel,
            onCompare: { findingID in
                comparisonFindingID = findingID
                isShowingReferencePicker = true
            }
        )
        .sheet(isPresented: $isShowingReferencePicker) {
            referencePicker
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $reference) { reference in
            SwingComparisonView(
                userVideo: payload.video,
                userAnalysis: payload.analysis,
                reference: reference,
                initialFindingID: comparisonFindingID,
                primaryPaneTitle: payload.subject.comparisonPaneTitle
            )
        }
        .overlay {
            if isLoadingReference {
                ZStack {
                    Color.black.opacity(0.58).ignoresSafeArea()
                    VStack(spacing: SwingTheme.Spacing.medium) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(SwingTheme.coral)
                        Text("Preparing phase match")
                            .font(SwingTheme.Typography.headline)
                            .foregroundStyle(SwingTheme.cream)
                    }
                    .padding(SwingTheme.Spacing.large)
                    .background(SwingTheme.canvas, in: RoundedRectangle(
                        cornerRadius: SwingTheme.Radius.large,
                        style: .continuous
                    ))
                }
            }
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text("Comparison could not open"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            loadBundledCatalogIfNeeded()
        }
    }

    private var referencePicker: some View {
        NavigationStack {
            Group {
                if bundledReferenceCandidates.isEmpty
                    && verifiedSessionCandidates.isEmpty
                    && privateReferenceCandidates.isEmpty
                    && bestSwingCandidates.isEmpty
                    && catalogFailureMessage == nil {
                    ContentUnavailableView {
                        Label("Analyze one more swing", systemImage: "rectangle.split.2x1")
                    } description: {
                        Text("Use another saved swing or a private reference with a matching camera view for the clearest comparison.")
                    }
                } else {
                    List {
                        if !bundledReferenceCandidates.isEmpty {
                            Section {
                                ForEach(bundledReferenceCandidates) { entry in
                                    bundledCandidateRow(entry)
                                }
                            } header: {
                                Text("Rights-cleared references")
                            } footer: {
                                Text("Catalog entries appear after distribution rights and source metadata validate. The video and analysis are checked before comparison opens.")
                            }
                        }

                        if !verifiedSessionCandidates.isEmpty {
                            Section("Verified references") {
                                ForEach(verifiedSessionCandidates) { candidate in
                                    candidateRow(
                                        candidate,
                                        sourceLabel: "Verified rights"
                                    )
                                }
                            }
                        }

                        if !privateReferenceCandidates.isEmpty {
                            Section {
                                ForEach(privateReferenceCandidates) { candidate in
                                    candidateRow(
                                        candidate,
                                        sourceLabel: "Private · unverified"
                                    )
                                }
                            } header: {
                                Text("Private references")
                            } footer: {
                                Text("Stored only on this iPhone. User imports are unverified and are not cleared for distribution.")
                            }
                        }

                        if !bestSwingCandidates.isEmpty {
                            Section("Your saved swings") {
                                ForEach(bestSwingCandidates) { candidate in
                                    candidateRow(
                                        candidate,
                                        sourceLabel: "Your saved swing"
                                    )
                                }
                            }
                        }

                        if let catalogFailureMessage {
                            Section("Reference catalog unavailable") {
                                Label(catalogFailureMessage, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(SwingTheme.mutedText)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(SwingTheme.deepCanvas)
            .navigationTitle("Choose reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingReferencePicker = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func candidateRow(
        _ candidate: ComparisonCandidate,
        sourceLabel: String
    ) -> some View {
        Button {
            loadReference(candidate)
        } label: {
            HStack(spacing: SwingTheme.Spacing.medium) {
                SessionReferenceScore(score: candidate.session.score)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.descriptor.displayLabel)
                        .font(.headline)
                        .foregroundStyle(SwingTheme.cream)
                    Text(referenceDetail(
                        for: candidate.session,
                        sourceLabel: sourceLabel
                    ))
                    .font(.caption)
                    .foregroundStyle(SwingTheme.mutedText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SwingTheme.subtleText)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(SwingTheme.surface)
    }

    private func bundledCandidateRow(
        _ entry: BundledReferenceManifestEntry
    ) -> some View {
        Button {
            loadBundledReference(entry)
        } label: {
            HStack(spacing: SwingTheme.Spacing.medium) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(SwingTheme.success)
                    .frame(width: 44, height: 44)
                    .background(SwingTheme.elevated, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.descriptor.displayLabel)
                        .font(.headline)
                        .foregroundStyle(SwingTheme.cream)
                    Text(bundledReferenceDetail(entry))
                        .font(.caption)
                        .foregroundStyle(SwingTheme.mutedText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SwingTheme.subtleText)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(SwingTheme.surface)
    }

    private func loadReference(_ candidate: ComparisonCandidate) {
        isShowingReferencePicker = false
        isLoadingReference = true

        Task { @MainActor in
            defer { isLoadingReference = false }
            do {
                let saved = try await SavedSwingPayloadLoader.load(session: candidate.session)
                reference = ReferenceSwing(
                    descriptor: candidate.descriptor,
                    video: saved.video,
                    analysis: saved.analysis
                )
            } catch {
                failure = ComparisonLoadFailure(message: error.localizedDescription)
            }
        }
    }

    private func loadBundledReference(_ entry: BundledReferenceManifestEntry) {
        isShowingReferencePicker = false
        isLoadingReference = true

        Task { @MainActor in
            defer { isLoadingReference = false }
            do {
                reference = try await BundledReferenceCatalog.load(entry)
            } catch {
                failure = ComparisonLoadFailure(message: error.localizedDescription)
            }
        }
    }

    private func loadBundledCatalogIfNeeded() {
        guard !didLoadCatalog else { return }
        didLoadCatalog = true
        do {
            bundledReferences = try BundledReferenceCatalog.entries()
        } catch {
            bundledReferences = []
            catalogFailureMessage = error.localizedDescription
        }
    }

    private func sortedCandidates(_ sessions: [SwingSession]) -> [ComparisonCandidate] {
        sessions
            .filter { $0.id != payload.sessionID }
            .compactMap { session in
                ReferenceSwingDescriptorFactory.make(from: session).map {
                    ComparisonCandidate(session: session, descriptor: $0)
                }
            }
            .sorted { first, second in
                let firstScore = compatibilityScore(for: first.descriptor)
                let secondScore = compatibilityScore(for: second.descriptor)
                return firstScore == secondScore
                    ? first.session.date > second.session.date
                    : firstScore > secondScore
            }
    }

    private func compatibilityScore(for descriptor: ReferenceSwingDescriptor) -> Int {
        ReferenceMatcher.compatibilityScore(
            reference: descriptor,
            view: payload.analysis.context.cameraView,
            handedness: payload.analysis.context.handedness,
            club: durableClub(named: payload.clubName)
        )
    }

    private func durableClub(named displayName: String) -> SwingClub {
        SwingClub.allCases.first { $0.displayName == displayName } ?? .unknown
    }

    private func referenceDetail(
        for session: SwingSession,
        sourceLabel: String
    ) -> String {
        let viewMatch = session.cameraView == payload.analysis.context.cameraView
            ? "same view"
            : "different view"
        return "\(sourceLabel) · \(session.cameraView.displayName) · \(session.selectedClub.displayName) · \(viewMatch)"
    }

    private func bundledReferenceDetail(
        _ entry: BundledReferenceManifestEntry
    ) -> String {
        let golfer = entry.descriptor.golferLabel ?? "Reference golfer"
        let viewMatch = entry.cameraView == payload.analysis.context.cameraView
            ? "same view"
            : "different view"
        return "\(golfer) · \(entry.cameraView.displayName) · \(entry.club.displayName) · \(viewMatch)"
    }
}

private struct ComparisonCandidate: Identifiable {
    let session: SwingSession
    let descriptor: ReferenceSwingDescriptor

    var id: UUID { session.id }
}

private struct SessionReferenceScore: View {
    let score: Double?

    var body: some View {
        Text(score?.formatted(.number.precision(.fractionLength(0))) ?? "—")
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(SwingTheme.cream)
            .frame(width: 44, height: 44)
            .background(SwingTheme.elevated, in: Circle())
            .accessibilityLabel(score.map { "Score \($0.formatted()) out of 100" } ?? "No score")
    }
}

private struct ComparisonLoadFailure: Identifiable {
    let id = UUID()
    let message: String
}
