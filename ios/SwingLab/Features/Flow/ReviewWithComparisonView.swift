import SwiftData
import SwiftUI

/// Adds a user-owned reference picker around the core review screen.
/// Licensed instructor or professional references can use the same
/// `ReferenceSwing` boundary when distribution rights are available.
struct ReviewWithComparisonView: View {
    let payload: AnalysisReviewPayload

    @Query(sort: \SwingSession.date, order: .reverse)
    private var sessions: [SwingSession]

    @State private var isShowingReferencePicker = false
    @State private var isLoadingReference = false
    @State private var reference: ReferenceSwing?
    @State private var failure: ComparisonLoadFailure?
    @State private var comparisonFindingID: String?

    private var candidates: [SwingSession] {
        sessions
            .filter {
                $0.id != payload.sessionID
                    && $0.analysisStatus == .complete
                    && $0.analysisJSON != nil
            }
            .sorted {
                compatibilityScore(for: $0) > compatibilityScore(for: $1)
            }
    }

    var body: some View {
        SwingReviewView(
            video: payload.video,
            analysis: payload.analysis,
            clubName: payload.clubName,
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
                initialFindingID: comparisonFindingID
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
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Analyze one more swing", systemImage: "rectangle.split.2x1")
                    } description: {
                        Text("A second saved swing becomes your Best Swing reference. Matching camera views gives the clearest comparison.")
                    }
                } else {
                    List(candidates) { session in
                        Button {
                            loadReference(session)
                        } label: {
                            HStack(spacing: SwingTheme.Spacing.medium) {
                                SessionReferenceScore(score: session.score)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundStyle(SwingTheme.cream)
                                    Text(referenceDetail(for: session))
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
                    .scrollContentBackground(.hidden)
                }
            }
            .background(SwingTheme.deepCanvas)
            .navigationTitle("Choose Best Swing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingReferencePicker = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadReference(_ session: SwingSession) {
        isShowingReferencePicker = false
        isLoadingReference = true

        Task { @MainActor in
            defer { isLoadingReference = false }
            do {
                let saved = try await SavedSwingPayloadLoader.load(session: session)
                let descriptor = ReferenceSwingDescriptor(
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
                    analysisJSON: session.analysisJSON ?? ""
                )
                reference = ReferenceSwing(
                    descriptor: descriptor,
                    video: saved.video,
                    analysis: saved.analysis
                )
            } catch {
                failure = ComparisonLoadFailure(message: error.localizedDescription)
            }
        }
    }

    private func compatibilityScore(for session: SwingSession) -> Int {
        ReferenceMatcher.compatibilityScore(
            reference: ReferenceSwingDescriptor(
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
                analysisJSON: session.analysisJSON ?? ""
            ),
            view: payload.analysis.context.cameraView,
            handedness: payload.analysis.context.handedness,
            club: durableClub(named: payload.clubName)
        )
    }

    private func durableClub(named displayName: String) -> SwingClub {
        SwingClub.allCases.first { $0.displayName == displayName } ?? .unknown
    }

    private func referenceDetail(for session: SwingSession) -> String {
        let viewMatch = session.cameraView == payload.analysis.context.cameraView
            ? "same view"
            : "different view"
        return "\(session.cameraView.displayName) · \(session.selectedClub.displayName) · \(viewMatch)"
    }
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
