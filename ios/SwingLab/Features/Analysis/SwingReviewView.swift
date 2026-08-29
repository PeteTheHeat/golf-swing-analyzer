import SwiftUI

struct SwingReviewView: View {
    let video: ImportedVideo
    let analysis: SwingAnalysisResult
    let clubName: String
    let subjectLabel: String
    var onCompare: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerController: VideoPlayerController
    @State private var selectedFindingID: String?
    @State private var showsAnalysis = true

    init(
        video: ImportedVideo,
        analysis: SwingAnalysisResult,
        clubName: String,
        subjectLabel: String = "Your swing",
        onCompare: ((String) -> Void)? = nil
    ) {
        self.video = video
        self.analysis = analysis
        self.clubName = clubName
        self.subjectLabel = subjectLabel
        self.onCompare = onCompare
        _playerController = StateObject(wrappedValue: VideoPlayerController(video: video))
        _selectedFindingID = State(initialValue: analysis.findings.first?.id)
    }

    private var selectedFinding: SwingFinding? {
        guard let selectedFindingID else { return nil }
        return analysis.findings.first { $0.id == selectedFindingID }
    }

    private var currentPose: PoseFrame? {
        analysis.poseTrack.frames.min {
            abs($0.timestampSeconds - playerController.currentTime)
                < abs($1.timestampSeconds - playerController.currentTime)
        }
    }

    private var selectedOverlay: SwingFindingOverlay? {
        selectedFinding.flatMap { analysis.resolvedOverlay(for: $0) }
    }

    private var highlightedJoints: Set<PoseJoint> {
        Set(selectedOverlay?.highlightedJoints ?? [])
    }

    private var selectedBaselinePose: PoseFrame? {
        guard let selectedFinding, let selectedOverlay else { return nil }
        let evidenceID = selectedOverlay.baselineEvidenceID
            ?? selectedFinding.evidenceIDs.first
        return pose(forEvidenceID: evidenceID)
    }

    private var selectedHandTrail: [PoseFrame] {
        guard let selectedFinding,
              let selectedOverlay,
              selectedOverlay.kind == .takeawayHandPath
                || selectedOverlay.kind == .transitionHandPath else {
            return []
        }
        let baselineID = selectedOverlay.baselineEvidenceID
            ?? selectedFinding.evidenceIDs.first
        let primaryID = selectedOverlay.primaryEvidenceID
            ?? selectedFinding.evidenceIDs.last
        guard let start = evidence(withID: baselineID)?.timestampSeconds,
              let end = evidence(withID: primaryID)?.timestampSeconds else {
            return []
        }
        let lower = min(start, end)
        let upper = max(start, end)
        return analysis.poseTrack.frames.filter {
            $0.timestampSeconds >= lower && $0.timestampSeconds <= upper
        }
    }

    private var selectedGuidePose: PoseFrame? {
        guard selectedOverlay?.kind == .headMovement else { return nil }
        return pose(forEvidenceID: selectedOverlay?.primaryEvidenceID)
    }

    private var selectedGuideNote: String? {
        switch selectedOverlay?.kind {
        case .headMovement where selectedGuidePose == nil:
            return "Peak head-movement frame is unavailable in this older saved analysis."
        case .transitionHandPath where selectedBaselinePose == nil:
            return "Matched-height baseline is unavailable in this older saved analysis."
        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            SwingTheme.deepCanvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    playerStage
                    controlDeck
                    findingsSection
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            playerController.setPlaybackRange(
                playbackSelection(for: analysis.poseTrack, video: video),
                seekIfOutsideRange: true
            )
            if let first = analysis.findings.first {
                seek(to: first)
            } else {
                playerController.seek(to: analysis.events.addressSeconds)
            }
        }
    }

    private var playerStage: some View {
        ZStack(alignment: .top) {
            VideoPlayerView(player: playerController.player, gravity: .fit)
                .aspectRatio(video.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(.black)

            if showsAnalysis {
                PoseOverlayView(
                    pose: currentPose,
                    videoAspectRatio: video.aspectRatio,
                    highlightedJoints: highlightedJoints,
                    findingOverlay: selectedOverlay,
                    baselinePose: selectedBaselinePose,
                    guidePose: selectedGuidePose,
                    handTrail: selectedHandTrail
                )
                .aspectRatio(video.aspectRatio, contentMode: .fit)

                if let selectedFinding {
                    VStack {
                        Spacer()
                        HStack {
                            findingBubble(selectedFinding)
                            Spacer(minLength: 42)
                        }
                        .padding(.horizontal, SwingTheme.Spacing.screen)
                        .padding(.bottom, SwingTheme.Spacing.large)
                    }
                    .aspectRatio(video.aspectRatio, contentMode: .fit)
                }
            }

            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.56), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Back")

                Spacer()

                VStack(alignment: .trailing, spacing: SwingTheme.Spacing.small) {
                    SwingScoreRing(score: Double(analysis.score.value))
                    SwingPill(text: subjectLabel, tint: .black.opacity(0.58))
                    SwingPill(text: clubName, tint: .black.opacity(0.58))
                }
            }
            .padding(SwingTheme.Spacing.screen)
        }
    }

    private func findingBubble(_ finding: SwingFinding) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(finding.title)
                .font(SwingTheme.Typography.headline)
            if let summary = analysis.resolvedOverlay(for: finding)?.measurementSummary {
                Text(summary)
                    .font(SwingTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
            }
            if let selectedGuideNote {
                Text(selectedGuideNote)
                    .font(SwingTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
            .foregroundStyle(.white)
            .padding(.horizontal, SwingTheme.Spacing.medium)
            .padding(.vertical, 12)
            .background(.black.opacity(0.82), in: RoundedRectangle(
                cornerRadius: SwingTheme.Radius.medium,
                style: .continuous
            ))
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(severityColor(finding.severity))
                    .frame(width: 9, height: 9)
                    .offset(x: 4)
            }
    }

    private var controlDeck: some View {
        VStack(spacing: SwingTheme.Spacing.medium) {
            ReviewTimeline(
                rangeStart: analysis.poseTrack.selectedRangeStartSeconds,
                rangeEnd: analysis.poseTrack.selectedRangeStartSeconds
                    + analysis.poseTrack.selectedRangeDurationSeconds,
                currentTime: playerController.currentTime,
                events: analysis.events,
                findings: analysis.findings,
                evidenceTime: evidenceTime(for:),
                onScrub: { time in
                    playerController.pause()
                    selectedFindingID = ReviewFindingSelection.findingID(
                        nearestTo: time,
                        findings: analysis.findings,
                        evidenceTime: evidenceTime(for:),
                        tolerance: manualSelectionTolerance
                    )
                    playerController.seek(to: time)
                },
                onSelectFinding: { finding in
                    select(finding)
                }
            )

            HStack(spacing: SwingTheme.Spacing.large) {
                Button {
                    selectedFindingID = nil
                    playerController.stepFrames(-1)
                } label: {
                    Image(systemName: "backward.frame.fill")
                }
                .accessibilityLabel("Previous frame")

                Button {
                    if !playerController.isPlaying {
                        selectedFindingID = nil
                    }
                    playerController.togglePlayback()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 54, height: 46)
                        .background(SwingTheme.cream, in: Capsule())
                        .foregroundStyle(SwingTheme.deepCanvas)
                }
                .accessibilityLabel(playerController.isPlaying ? "Pause" : "Play")

                Button {
                    selectedFindingID = nil
                    playerController.stepFrames(1)
                } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .accessibilityLabel("Next frame")

                Spacer()

                Button {
                    showsAnalysis.toggle()
                } label: {
                    Label(
                        showsAnalysis ? "Hide" : "Show",
                        systemImage: showsAnalysis ? "eye.slash" : "eye"
                    )
                    .font(SwingTheme.Typography.caption.weight(.semibold))
                }
            }
            .foregroundStyle(SwingTheme.cream)
        }
        .padding(SwingTheme.Spacing.screen)
        .background(SwingTheme.canvas)
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: SwingTheme.Spacing.medium) {
            scoreBreakdownSection

            SectionHeading(
                eyebrow: "Evidence",
                title: "What to work on",
                trailingText: "\(analysis.findings.count) checks"
            )

            ForEach(analysis.findings) { finding in
                Button {
                    select(finding)
                } label: {
                    AnalysisFindingCard(
                        finding: finding,
                        isSelected: finding.id == selectedFindingID
                    )
                }
                .buttonStyle(.plain)
            }

            if let onCompare, let selectedFinding {
                Button {
                    onCompare(selectedFinding.id)
                } label: {
                    Label("Compare this position", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SwingPrimaryButtonStyle())
                .padding(.top, SwingTheme.Spacing.small)
            }

            SwingCard {
                VStack(alignment: .leading, spacing: SwingTheme.Spacing.small) {
                    Text("Measurement boundary")
                        .font(SwingTheme.Typography.headline)
                        .foregroundStyle(SwingTheme.cream)
                    ForEach(analysis.limitations, id: \.self) { limitation in
                        Label(limitation, systemImage: "info.circle")
                            .font(SwingTheme.Typography.caption)
                            .foregroundStyle(SwingTheme.mutedText)
                    }
                }
            }
        }
        .padding(SwingTheme.Spacing.screen)
        .padding(.bottom, SwingTheme.Spacing.xLarge)
        .background(SwingTheme.deepCanvas)
    }

    private var scoreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: SwingTheme.Spacing.medium) {
            SectionHeading(
                eyebrow: "Score",
                title: analysis.score.label,
                trailingText: "\(analysis.score.value)/100"
            )

            SwingCard {
                VStack(alignment: .leading, spacing: SwingTheme.Spacing.medium) {
                    Text(analysis.score.explanation)
                        .font(SwingTheme.Typography.body)
                        .foregroundStyle(SwingTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    if !analysis.score.components.isEmpty {
                        Divider()
                            .overlay(SwingTheme.hairline)

                        VStack(alignment: .leading, spacing: SwingTheme.Spacing.medium) {
                            ForEach(
                                Array(analysis.score.components.enumerated()),
                                id: \.element.id
                            ) { index, component in
                                SwingScoreComponentRow(component: component)

                                if index < analysis.score.components.count - 1 {
                                    Divider()
                                        .overlay(SwingTheme.hairline)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func select(_ finding: SwingFinding) {
        selectedFindingID = finding.id
        seek(to: finding)
    }

    private func seek(to finding: SwingFinding) {
        playerController.pause()
        playerController.seek(to: evidenceTime(for: finding))
    }

    private func evidenceTime(for finding: SwingFinding) -> Double {
        analysis.primaryEvidence(for: finding)?.timestampSeconds
            ?? analysis.events[finding.phase]
    }

    private func evidence(withID id: String?) -> SwingEvidence? {
        guard let id else { return nil }
        return analysis.evidence.first { $0.id == id }
    }

    private func pose(forEvidenceID id: String?) -> PoseFrame? {
        guard let timestamp = evidence(withID: id)?.timestampSeconds else { return nil }
        return analysis.poseTrack.frames.min {
            abs($0.timestampSeconds - timestamp) < abs($1.timestampSeconds - timestamp)
        }
    }

    private var manualSelectionTolerance: Double {
        max(0.04, min(0.15, video.frameDurationSeconds * 1.5))
    }

    private func severityColor(_ severity: SwingFindingSeverity) -> Color {
        switch severity {
        case .priority: SwingTheme.coral
        case .watch: Color.orange
        case .good: SwingTheme.success
        case .info: SwingTheme.cream
        }
    }

    private func playbackSelection(
        for track: PoseTrack,
        video: ImportedVideo
    ) -> TrimSelection {
        TrimSelection(
            assetDuration: video.durationSeconds,
            frameDuration: video.frameDurationSeconds,
            minimumDuration: min(1, track.selectedRangeDurationSeconds),
            maximumDuration: max(1, track.selectedRangeDurationSeconds),
            start: track.selectedRangeStartSeconds,
            end: track.selectedRangeStartSeconds + track.selectedRangeDurationSeconds
        )
    }
}

enum ReviewFindingSelection {
    static func findingID(
        nearestTo timestamp: Double,
        findings: [SwingFinding],
        evidenceTime: (SwingFinding) -> Double,
        tolerance: Double
    ) -> String? {
        guard timestamp.isFinite, tolerance.isFinite, tolerance >= 0,
              let nearest = findings.min(by: {
                  abs(evidenceTime($0) - timestamp) < abs(evidenceTime($1) - timestamp)
              }),
              abs(evidenceTime(nearest) - timestamp) <= tolerance
        else {
            return nil
        }
        return nearest.id
    }
}

private struct SwingScoreComponentRow: View {
    let component: SwingScoreComponent

    private var earnedPointsText: String {
        component.earnedPoints.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var availablePointsText: String {
        component.availablePoints.formatted(.number.precision(.fractionLength(0...1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SwingTheme.Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: SwingTheme.Spacing.medium) {
                Text(component.title)
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SwingTheme.Spacing.small)

                Text("\(earnedPointsText) / \(availablePointsText)")
                    .font(SwingTheme.Typography.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SwingTheme.coral)
                    .fixedSize()
            }

            Text(component.explanation)
                .font(SwingTheme.Typography.caption)
                .foregroundStyle(SwingTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.title)
        .accessibilityValue(
            "\(earnedPointsText) of \(availablePointsText) points. \(component.explanation)"
        )
    }
}

private struct AnalysisFindingCard: View {
    let finding: SwingFinding
    let isSelected: Bool

    var body: some View {
        SwingCard {
            VStack(alignment: .leading, spacing: SwingTheme.Spacing.medium) {
                HStack {
                    SwingPill(text: finding.phase.rawValue.capitalized)
                    Spacer()
                    Text(finding.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(SwingTheme.Typography.caption.monospacedDigit())
                        .foregroundStyle(SwingTheme.mutedText)
                }

                Text(finding.title)
                    .font(SwingTheme.Typography.title)
                    .foregroundStyle(SwingTheme.cream)

                Text(finding.observation)
                    .font(SwingTheme.Typography.body)
                    .foregroundStyle(SwingTheme.cream)

                Text(finding.coachingTip)
                    .font(SwingTheme.Typography.body)
                    .foregroundStyle(SwingTheme.mutedText)

                if let caveat = finding.caveat {
                    Label(caveat, systemImage: "camera.metering.unknown")
                        .font(SwingTheme.Typography.caption)
                        .foregroundStyle(SwingTheme.subtleText)
                }
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SwingTheme.Radius.large, style: .continuous)
                    .stroke(SwingTheme.coral, lineWidth: 2)
            }
        }
    }
}

private struct ReviewTimeline: View {
    let rangeStart: Double
    let rangeEnd: Double
    let currentTime: Double
    let events: SwingEventTimestamps
    let findings: [SwingFinding]
    let evidenceTime: (SwingFinding) -> Double
    let onScrub: (Double) -> Void
    let onSelectFinding: (SwingFinding) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SwingTheme.elevated)
                    .frame(height: 34)

                ForEach(SwingPhase.allCases, id: \.self) { phase in
                    eventMarker(phase, width: width)
                }

                ForEach(findings) { finding in
                    Button {
                        onSelectFinding(finding)
                    } label: {
                        Circle()
                            .fill(SwingTheme.coral)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: position(for: evidenceTime(finding), width: width) - 5)
                    .accessibilityLabel("\(finding.title) at \(finding.phase.rawValue)")
                }

                Capsule()
                    .fill(SwingTheme.cream)
                    .frame(width: 3, height: 46)
                    .offset(x: position(for: currentTime, width: width) - 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(1, max(0, value.location.x / width))
                        onScrub(rangeStart + (rangeEnd - rangeStart) * fraction)
                    }
            )
        }
        .frame(height: 46)
        .accessibilityLabel("Swing timeline")
    }

    private func eventMarker(_ phase: SwingPhase, width: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.28))
            .frame(width: 1, height: 34)
            .offset(x: position(for: events[phase], width: width))
            .accessibilityHidden(true)
    }

    private func position(for time: Double, width: CGFloat) -> CGFloat {
        guard rangeEnd > rangeStart else { return 0 }
        let fraction = min(1, max(0, (time - rangeStart) / (rangeEnd - rangeStart)))
        return width * fraction
    }
}
