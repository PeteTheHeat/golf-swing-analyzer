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
    }

    private var referencePicker: some View {
        NavigationStack {
            Group {
                if privateReferenceCandidates.isEmpty && bestSwingCandidates.isEmpty {
                    ContentUnavailableView {
                        Label("Analyze one more swing", systemImage: "rectangle.split.2x1")
                    } description: {
                        Text("Use another saved swing or a private reference with a matching camera view for the clearest comparison.")
                    }
                } else {
                    List {
                        if !privateReferenceCandidates.isEmpty {
                            Section {
                                ForEach(privateReferenceCandidates) { candidate in
                                    candidateRow(candidate, isPrivateReference: true)
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
                                    candidateRow(candidate, isPrivateReference: false)
                                }
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
        isPrivateReference: Bool
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
                        isPrivateReference: isPrivateReference
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
        isPrivateReference: Bool
    ) -> String {
        let source = isPrivateReference ? "Private · unverified" : "Your saved swing"
        let viewMatch = session.cameraView == payload.analysis.context.cameraView
            ? "same view"
            : "different view"
        return "\(source) · \(session.cameraView.displayName) · \(session.selectedClub.displayName) · \(viewMatch)"
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
