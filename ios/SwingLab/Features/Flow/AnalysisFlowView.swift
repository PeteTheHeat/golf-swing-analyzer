import SwiftData
import SwiftUI

struct AnalysisFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var model = AnalysisFlowModel()

    var body: some View {
        NavigationStack {
            ZStack {
                ImportTrimView { video, selection, input in
                    model.start(
                        video: video,
                        selection: selection,
                        input: input,
                        modelContext: modelContext
                    )
                }
                .allowsHitTesting(!model.isAnalyzing)
                .accessibilityHidden(model.isAnalyzing)

                if model.isAnalyzing {
                    AnalysisProcessingView(
                        snapshot: model.progressSnapshot,
                        subject: model.activeSubject,
                        onCancel: model.cancelAnalysis
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.isAnalyzing)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $model.isShowingReview) {
                if let payload = model.reviewPayload {
                    ReviewWithComparisonView(payload: payload)
                    .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        .alert(item: $model.failure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("Try again"))
            )
        }
        .onChange(of: model.isShowingReview) { _, isShowing in
            if !isShowing {
                model.reviewDidClose()
            }
        }
    }
}

private struct AnalysisProcessingView: View {
    let snapshot: SwingAnalysisProgressSnapshot
    let subject: AnalysisReviewSubject
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SwingTheme.canvas, SwingTheme.deepCanvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: SwingTheme.Spacing.xLarge) {
                Spacer()

                progressDial

                VStack(spacing: SwingTheme.Spacing.small) {
                    Text("READING \(subject.reviewLabel.uppercased())")
                        .font(SwingTheme.Typography.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(SwingTheme.coral)
                    Text(snapshot.message)
                        .font(SwingTheme.Typography.title)
                        .foregroundStyle(SwingTheme.cream)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                    Text(progressDetail)
                        .font(SwingTheme.Typography.caption)
                        .foregroundStyle(SwingTheme.mutedText)
                }

                ProgressView(value: snapshot.fractionCompleted)
                    .tint(SwingTheme.coral)
                    .frame(maxWidth: 280)

                Spacer()

                Button("Cancel analysis", action: onCancel)
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.mutedText)
                    .padding(.bottom, SwingTheme.Spacing.xLarge)
            }
            .padding(.horizontal, SwingTheme.Spacing.screen)
        }
    }

    private var progressDial: some View {
        ZStack {
            Circle()
                .stroke(SwingTheme.elevated, lineWidth: 8)
            Circle()
                .trim(from: 0, to: snapshot.fractionCompleted)
                .stroke(
                    SwingTheme.coral,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.18), value: snapshot.fractionCompleted)
            Text(snapshot.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(SwingTheme.cream)
                .contentTransition(.numericText())
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysis progress")
        .accessibilityValue(snapshot.fractionCompleted.formatted(.percent))
    }

    private var progressDetail: String {
        guard snapshot.processedFrameCount > 0 else {
            return "Keep Replay Caddie open while on-device analysis runs."
        }
        return "\(snapshot.processedFrameCount) frames checked on this iPhone"
    }
}
