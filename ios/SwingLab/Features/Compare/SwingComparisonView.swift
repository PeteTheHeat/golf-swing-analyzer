import SwiftUI

struct SwingComparisonView: View {
    let userVideo: ImportedVideo
    let userAnalysis: SwingAnalysisResult
    let reference: ReferenceSwing
    let initialFindingID: String?
    let primaryPaneTitle: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var userPlayer: VideoPlayerController
    @StateObject private var referencePlayer: VideoPlayerController
    @State private var findingIndex: Int
    @State private var frameOffset = 0
    @State private var showsOverlays = true
    @State private var showsReferenceRights = false

    init(
        userVideo: ImportedVideo,
        userAnalysis: SwingAnalysisResult,
        reference: ReferenceSwing,
        initialFindingID: String? = nil,
        primaryPaneTitle: String = "YOUR SWING"
    ) {
        self.userVideo = userVideo
        self.userAnalysis = userAnalysis
        self.reference = reference
        self.initialFindingID = initialFindingID
        self.primaryPaneTitle = primaryPaneTitle
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
                    title: primaryPaneTitle,
                    subtitle: finding?.title,
                    player: userPlayer,
                    pose: userPose,
                    analysis: userAnalysis,
                    aspectRatio: userVideo.aspectRatio,
                    highlight: SwingTheme.coral
                )

                Rectangle()
                    .fill(SwingTheme.cream.opacity(0.8))
                    .frame(height: 2)

                swingPane(
                    title: referencePaneTitle,
                    subtitle: reference.descriptor.displayLabel,
                    player: referencePlayer,
                    pose: referencePose,
                    analysis: reference.analysis,
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
        .onChange(of: findingIndex) { _, _ in
            frameOffset = 0
            seekToFinding()
        }
        .onChange(of: frameOffset) { _, _ in seekToFinding() }
        .sheet(isPresented: $showsReferenceRights) {
            referenceRightsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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

            if reference.descriptor.isDistributionReady {
                Button {
                    showsReferenceRights = true
                } label: {
                    Image(systemName: "checkmark.seal")
                        .frame(width: 42, height: 42)
                        .background(SwingTheme.elevated, in: Circle())
                }
                .accessibilityLabel("Reference rights and attribution")
            }

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
        analysis: SwingAnalysisResult,
        aspectRatio: CGFloat,
        highlight: Color
    ) -> some View {
        let requestedOverlay = finding?.resolvedOverlay
        let overlay = resolvedOverlay(for: analysis)
        let overlayNote = overlayNote(
            requested: requestedOverlay,
            resolved: overlay,
            in: analysis
        )
        return ZStack(alignment: .topLeading) {
            VideoPlayerView(player: player.player, gravity: .fit)
            if showsOverlays {
                PoseOverlayView(
                    pose: pose,
                    videoAspectRatio: aspectRatio,
                    highlightedJoints: Set(overlay?.highlightedJoints ?? []),
                    findingOverlay: overlay,
                    baselinePose: baselinePose(for: overlay, in: analysis),
                    guidePose: guidePose(
                        for: overlay,
                        in: analysis
                    ),
                    handTrail: handTrail(for: overlay, in: analysis),
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
                if let summary = overlay?.measurementSummary {
                    Text(summary)
                        .font(SwingTheme.Typography.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }
                if let overlayNote {
                    Text(overlayNote)
                        .font(SwingTheme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
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
        VStack(spacing: SwingTheme.Spacing.xSmall) {
            HStack(spacing: SwingTheme.Spacing.large) {
                Button {
                    findingIndex = max(0, findingIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .disabled(findingIndex == 0)
                .accessibilityLabel("Previous check")

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
                    findingIndex = min(
                        max(0, userAnalysis.findings.count - 1),
                        findingIndex + 1
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(findingIndex >= userAnalysis.findings.count - 1)
                .accessibilityLabel("Next check")
            }

            HStack(spacing: SwingTheme.Spacing.medium) {
                Button {
                    frameOffset = ComparisonFrameStepper.clampedOffset(
                        frameOffset - 1
                    )
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(!canStepBackward)
                .accessibilityLabel("Previous matched frame")
                .accessibilityValue(
                    ComparisonFrameStepper.accessibilityValue(for: frameOffset)
                )
                .accessibilityHint("Moves both videos one frame earlier")

                Button {
                    frameOffset = 0
                } label: {
                    Text(ComparisonFrameStepper.label(for: frameOffset))
                        .font(SwingTheme.Typography.eyebrow.monospacedDigit())
                        .tracking(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(
                    frameOffset == 0
                        ? "Matched evidence frame"
                        : "Reset to matched evidence frame"
                )
                .accessibilityValue(
                    ComparisonFrameStepper.accessibilityValue(for: frameOffset)
                )
                .accessibilityHint(
                    frameOffset == 0
                        ? "Both videos are at the matched frame"
                        : "Returns both videos to the matched frame"
                )

                Button {
                    frameOffset = ComparisonFrameStepper.clampedOffset(
                        frameOffset + 1
                    )
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(!canStepForward)
                .accessibilityLabel("Next matched frame")
                .accessibilityValue(
                    ComparisonFrameStepper.accessibilityValue(for: frameOffset)
                )
                .accessibilityHint("Moves both videos one frame later")
            }
        }
        .foregroundStyle(SwingTheme.cream)
        .padding(.horizontal, SwingTheme.Spacing.screen)
        .padding(.vertical, SwingTheme.Spacing.small)
        .background(SwingTheme.deepCanvas)
    }

    private var referenceRightsSheet: some View {
        NavigationStack {
            List {
                Section("Reference") {
                    LabeledContent("Name", value: reference.descriptor.displayLabel)
                    if let golfer = reference.descriptor.golferLabel {
                        LabeledContent("Golfer", value: golfer)
                    }
                }

                Section("Rights") {
                    if let attribution = reference.descriptor.attribution {
                        LabeledContent("Attribution", value: attribution)
                    }
                    if let licenseName = reference.descriptor.licenseName {
                        LabeledContent("License", value: licenseName)
                    }
                    if let sourceURL = reference.descriptor.sourceURL {
                        Link("Open source page", destination: sourceURL)
                    }
                    if let licenseURL = reference.descriptor.licenseURL {
                        Link("Open license", destination: licenseURL)
                    }
                }
            }
            .navigationTitle("Reference details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsReferenceRights = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var referencePaneTitle: String {
        switch reference.descriptor.sourceKind {
        case .bestSelf:
            "SAVED SWING"
        case .userImported:
            "PRIVATE REFERENCE"
        case .licensedProfessional, .instructor:
            reference.descriptor.isDistributionReady
                ? "REFERENCE"
                : "UNVERIFIED REFERENCE"
        case .unknown:
            "UNVERIFIED REFERENCE"
        }
    }

    private func seekToFinding() {
        guard let times = comparisonTimes(for: frameOffset) else { return }
        userPlayer.pause()
        referencePlayer.pause()
        userPlayer.seek(to: times.user)
        referencePlayer.seek(to: times.reference)
    }

    private var canStepBackward: Bool {
        canStep(by: -1)
    }

    private var canStepForward: Bool {
        canStep(by: 1)
    }

    private func canStep(by direction: Int) -> Bool {
        guard let anchors = comparisonAnchors else { return false }
        let userStart = userAnalysis.poseTrack.selectedRangeStartSeconds
        let referenceStart = reference.analysis.poseTrack.selectedRangeStartSeconds
        return ComparisonFrameStepper.canStep(
            base: anchors.user,
            frameDuration: userVideo.frameDurationSeconds,
            offset: frameOffset,
            direction: direction,
            rangeStart: userStart,
            rangeEnd: userStart + userAnalysis.poseTrack.selectedRangeDurationSeconds
        ) && ComparisonFrameStepper.canStep(
            base: anchors.reference,
            frameDuration: reference.video.frameDurationSeconds,
            offset: frameOffset,
            direction: direction,
            rangeStart: referenceStart,
            rangeEnd: referenceStart
                + reference.analysis.poseTrack.selectedRangeDurationSeconds
        )
    }

    private var comparisonAnchors: (user: Double, reference: Double)? {
        guard let finding else { return nil }
        let userStart = userAnalysis.poseTrack.selectedRangeStartSeconds
        let userBase = ComparisonFrameStepper.timestamp(
            base: evidenceTime(for: finding, in: userAnalysis),
            frameDuration: userVideo.frameDurationSeconds,
            offset: 0,
            rangeStart: userStart,
            rangeEnd: userStart + userAnalysis.poseTrack.selectedRangeDurationSeconds
        )
        let referenceBase = ReferenceMatcher.alignedTime(
            userTime: userBase,
            userEvents: userAnalysis.events,
            referenceEvents: reference.analysis.events
        )
        return (userBase, referenceBase)
    }

    private func comparisonTimes(
        for offset: Int
    ) -> (user: Double, reference: Double)? {
        guard let anchors = comparisonAnchors else { return nil }
        let userStart = userAnalysis.poseTrack.selectedRangeStartSeconds
        let referenceStart = reference.analysis.poseTrack.selectedRangeStartSeconds
        return (
            ComparisonFrameStepper.timestamp(
                base: anchors.user,
                frameDuration: userVideo.frameDurationSeconds,
                offset: offset,
                rangeStart: userStart,
                rangeEnd: userStart + userAnalysis.poseTrack.selectedRangeDurationSeconds
            ),
            ComparisonFrameStepper.timestamp(
                base: anchors.reference,
                frameDuration: reference.video.frameDurationSeconds,
                offset: offset,
                rangeStart: referenceStart,
                rangeEnd: referenceStart
                    + reference.analysis.poseTrack.selectedRangeDurationSeconds
            )
        )
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

    private func resolvedOverlay(
        for analysis: SwingAnalysisResult
    ) -> SwingFindingOverlay? {
        finding.flatMap { analysis.resolvedOverlay(for: $0) }
    }

    private func baselinePose(
        for overlay: SwingFindingOverlay?,
        in analysis: SwingAnalysisResult
    ) -> PoseFrame? {
        guard let overlay else { return nil }
        if let exact = pose(forEvidenceID: overlay.baselineEvidenceID, in: analysis) {
            return exact
        }
        let fallbackID: String?
        switch overlay.kind {
        case .headMovement, .torsoPosture, .takeawayHandPath:
            fallbackID = "event-address"
        case .tempo:
            fallbackID = "event-top"
        case .kneeGeometry, .transitionHandPath:
            fallbackID = nil
        }
        return pose(forEvidenceID: fallbackID, in: analysis)
    }

    private func guidePose(
        for overlay: SwingFindingOverlay?,
        in analysis: SwingAnalysisResult
    ) -> PoseFrame? {
        guard overlay?.kind == .headMovement else { return nil }
        return pose(forEvidenceID: overlay?.primaryEvidenceID, in: analysis)
    }

    private func handTrail(
        for overlay: SwingFindingOverlay?,
        in analysis: SwingAnalysisResult
    ) -> [PoseFrame] {
        guard let overlay,
              overlay.kind == .takeawayHandPath || overlay.kind == .transitionHandPath else {
            return []
        }
        let start: Double?
        let end: Double?
        if overlay.kind == .transitionHandPath {
            start = evidence(
                withID: overlay.baselineEvidenceID,
                in: analysis
            )?.timestampSeconds
            end = evidence(
                withID: overlay.primaryEvidenceID,
                in: analysis
            )?.timestampSeconds
        } else {
            start = evidence(
                withID: overlay.baselineEvidenceID,
                in: analysis
            )?.timestampSeconds ?? evidence(
                withID: "event-address",
                in: analysis
            )?.timestampSeconds
            end = evidence(
                withID: overlay.primaryEvidenceID,
                in: analysis
            )?.timestampSeconds ?? evidence(
                withID: "hand-takeaway",
                in: analysis
            )?.timestampSeconds
        }
        guard let start, let end else { return [] }
        let lower = min(start, end)
        let upper = max(start, end)
        return analysis.poseTrack.frames.filter {
            $0.timestampSeconds >= lower && $0.timestampSeconds <= upper
        }
    }

    private func pose(
        forEvidenceID id: String?,
        in analysis: SwingAnalysisResult
    ) -> PoseFrame? {
        guard let timestamp = evidence(withID: id, in: analysis)?.timestampSeconds else {
            return nil
        }
        return nearestPose(in: analysis.poseTrack, at: timestamp)
    }

    private func evidence(
        withID id: String?,
        in analysis: SwingAnalysisResult
    ) -> SwingEvidence? {
        guard let id else { return nil }
        return analysis.evidence.first { $0.id == id }
    }

    private func overlayNote(
        requested: SwingFindingOverlay?,
        resolved: SwingFindingOverlay?,
        in analysis: SwingAnalysisResult
    ) -> String? {
        if let requested, !analysis.supportsOverlay(requested.kind) {
            return "Not comparable from \(analysis.context.cameraView.displayName.lowercased()) footage. Choose a down-the-line reference for this check."
        }
        if resolved?.kind == .transitionHandPath,
           baselinePose(for: resolved, in: analysis) == nil {
            return "Matched-height baseline is unavailable in this older saved analysis."
        }
        if resolved?.kind == .headMovement,
           guidePose(for: resolved, in: analysis) == nil {
            return "Peak head-movement frame is unavailable in this older saved analysis."
        }
        return nil
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

enum ComparisonFrameStepper {
    private static let maximumOffset = 12

    static func clampedOffset(_ offset: Int) -> Int {
        min(maximumOffset, max(-maximumOffset, offset))
    }

    static func timestamp(
        base: Double,
        frameDuration: Double,
        offset: Int,
        rangeStart: Double,
        rangeEnd: Double
    ) -> Double {
        guard rangeStart.isFinite,
              rangeEnd.isFinite,
              rangeEnd >= rangeStart else {
            return base.isFinite ? base : 0
        }
        guard base.isFinite else { return rangeStart }
        let boundedBase = min(rangeEnd, max(rangeStart, base))
        guard frameDuration.isFinite, frameDuration > 0 else {
            return boundedBase
        }
        let candidate = boundedBase
            + Double(clampedOffset(offset)) * frameDuration
        return min(rangeEnd, max(rangeStart, candidate))
    }

    static func canStep(
        base: Double,
        frameDuration: Double,
        offset: Int,
        direction: Int,
        rangeStart: Double,
        rangeEnd: Double
    ) -> Bool {
        guard direction != 0 else { return false }
        let currentOffset = clampedOffset(offset)
        let nextOffset = clampedOffset(currentOffset + (direction < 0 ? -1 : 1))
        guard nextOffset != currentOffset else { return false }
        let currentTime = timestamp(
            base: base,
            frameDuration: frameDuration,
            offset: currentOffset,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        let nextTime = timestamp(
            base: base,
            frameDuration: frameDuration,
            offset: nextOffset,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        return nextTime != currentTime
    }

    static func label(for offset: Int) -> String {
        let safeOffset = clampedOffset(offset)
        guard safeOffset != 0 else { return "MATCHED FRAME" }
        return safeOffset < 0
            ? "\(abs(safeOffset)) BEFORE"
            : "\(safeOffset) AFTER"
    }

    static func accessibilityValue(for offset: Int) -> String {
        let safeOffset = clampedOffset(offset)
        guard safeOffset != 0 else { return "Matched evidence frame" }
        let count = abs(safeOffset)
        let unit = count == 1 ? "frame" : "frames"
        return safeOffset < 0
            ? "\(count) \(unit) before the matched frame"
            : "\(count) \(unit) after the matched frame"
    }
}
