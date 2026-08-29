import SwiftUI

struct SwingComparisonView: View {
    let userVideo: ImportedVideo
    let userAnalysis: SwingAnalysisResult
    let reference: ReferenceSwing
    let initialFindingID: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var userPlayer: VideoPlayerController
    @StateObject private var referencePlayer: VideoPlayerController
    @State private var findingIndex: Int
    @State private var showsOverlays = true

    init(
        userVideo: ImportedVideo,
        userAnalysis: SwingAnalysisResult,
        reference: ReferenceSwing,
        initialFindingID: String? = nil
    ) {
        self.userVideo = userVideo
        self.userAnalysis = userAnalysis
        self.reference = reference
        self.initialFindingID = initialFindingID
        _userPlayer = StateObject(wrappedValue: VideoPlayerController(video: userVideo))
        _referencePlayer = StateObject(wrappedValue: VideoPlayerController(video: reference.video))
        let initialIndex = userAnalysis.findings.firstIndex { $0.id == initialFindingID } ?? 0
        _findingIndex = State(initialValue: initialIndex)
    }

    private var finding: SwingFinding? {
        guard userAnalysis.findings.indices.contains(findingIndex) else { return nil }
        return userAnalysis.findings[findingIndex]
    }

    private var userPose: PoseFrame? {
        nearestPose(in: userAnalysis.poseTrack, at: userPlayer.currentTime)
    }

    private var referencePose: PoseFrame? {
        nearestPose(in: reference.analysis.poseTrack, at: referencePlayer.currentTime)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                comparisonHeader
                swingPane(
                    title: "YOUR SWING",
                    subtitle: finding?.title,
                    player: userPlayer,
                    pose: userPose,
                    aspectRatio: userVideo.aspectRatio,
                    highlight: SwingTheme.coral
                )

                Rectangle()
                    .fill(SwingTheme.cream.opacity(0.8))
                    .frame(height: 2)

                swingPane(
                    title: reference.descriptor.sourceKind == .bestSelf ? "BEST SWING" : "REFERENCE",
                    subtitle: reference.descriptor.displayName,
                    player: referencePlayer,
                    pose: referencePose,
                    aspectRatio: reference.video.aspectRatio,
                    highlight: SwingTheme.success
                )

                comparisonControls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            userPlayer.setPlaybackRange(
                playbackSelection(for: userAnalysis.poseTrack, video: userVideo)
            )
            referencePlayer.setPlaybackRange(
                playbackSelection(for: reference.analysis.poseTrack, video: reference.video)
            )
            seekToFinding()
        }
        .onChange(of: findingIndex) { _, _ in seekToFinding() }
    }

    private var comparisonHeader: some View {
        HStack(spacing: SwingTheme.Spacing.medium) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(SwingTheme.elevated, in: Circle())
            }
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("PHASE MATCH")
                    .font(SwingTheme.Typography.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(SwingTheme.coral)
                Text(finding?.phase.rawValue.capitalized ?? "Comparison")
                    .font(SwingTheme.Typography.headline)
                    .foregroundStyle(SwingTheme.cream)
            }

            Spacer()

            Button {
                showsOverlays.toggle()
            } label: {
                Image(systemName: showsOverlays ? "eye.slash" : "eye")
                    .frame(width: 42, height: 42)
                    .background(SwingTheme.elevated, in: Circle())
            }
            .accessibilityLabel(showsOverlays ? "Hide overlays" : "Show overlays")
        }
        .foregroundStyle(SwingTheme.cream)
        .padding(.horizontal, SwingTheme.Spacing.screen)
        .padding(.vertical, SwingTheme.Spacing.small)
        .background(SwingTheme.deepCanvas)
    }

    private func swingPane(
        title: String,
        subtitle: String?,
        player: VideoPlayerController,
        pose: PoseFrame?,
        aspectRatio: CGFloat,
        highlight: Color
    ) -> some View {
        ZStack(alignment: .topLeading) {
            VideoPlayerView(player: player.player, gravity: .fit)
            if showsOverlays {
                PoseOverlayView(
                    pose: pose,
                    videoAspectRatio: aspectRatio,
                    highlightedJoints: [.leftWrist, .rightWrist, .leftShoulder, .rightShoulder],
                    highlightColor: highlight
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SwingTheme.Typography.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(highlight)
                if let subtitle {
                    Text(subtitle)
                        .font(SwingTheme.Typography.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .padding(SwingTheme.Spacing.medium)
            .background(.black.opacity(0.52), in: RoundedRectangle(
                cornerRadius: SwingTheme.Radius.small,
                style: .continuous
            ))
            .padding(SwingTheme.Spacing.medium)
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .background(.black)
    }

    private var comparisonControls: some View {
        HStack(spacing: SwingTheme.Spacing.large) {
            Button {
                findingIndex = max(0, findingIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(findingIndex == 0)

            VStack(spacing: 2) {
                Text("CHECK \(min(findingIndex + 1, userAnalysis.findings.count)) OF \(userAnalysis.findings.count)")
                    .font(SwingTheme.Typography.eyebrow)
                    .tracking(1.2)
                Text(finding?.title ?? "No comparison checks")
                    .font(SwingTheme.Typography.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button {
                findingIndex = min(max(0, userAnalysis.findings.count - 1), findingIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(findingIndex >= userAnalysis.findings.count - 1)
        }
        .foregroundStyle(SwingTheme.cream)
        .padding(.horizontal, SwingTheme.Spacing.screen)
        .padding(.vertical, SwingTheme.Spacing.medium)
        .background(SwingTheme.deepCanvas)
    }

    private func seekToFinding() {
        guard let finding else { return }
        let userTime = evidenceTime(for: finding, in: userAnalysis)
        let referenceTime = ReferenceMatcher.alignedTime(
            userTime: userTime,
            userEvents: userAnalysis.events,
            referenceEvents: reference.analysis.events
        )
        userPlayer.pause()
        referencePlayer.pause()
        userPlayer.seek(to: userTime)
        referencePlayer.seek(to: referenceTime)
    }

    private func evidenceTime(for finding: SwingFinding, in result: SwingAnalysisResult) -> Double {
        result.primaryEvidence(for: finding)?.timestampSeconds
            ?? result.events[finding.phase]
    }

    private func nearestPose(in track: PoseTrack, at time: Double) -> PoseFrame? {
        track.frames.min {
            abs($0.timestampSeconds - time) < abs($1.timestampSeconds - time)
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
