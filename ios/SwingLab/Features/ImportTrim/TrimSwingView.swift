import SwiftUI

public struct TrimSwingView: View {
    public let video: ImportedVideo

    private let onAnalyze: (ImportedVideo, TrimSelection, SwingContextInput) -> Void
    private let onChooseAnother: (() -> Void)?
    private let thumbnailGenerator = VideoThumbnailGenerator()

    @StateObject private var playerController: VideoPlayerController
    @State private var selection: TrimSelection
    @State private var context = SwingContextInput()
    @State private var thumbnails: [VideoThumbnail] = []
    @State private var thumbnailError: String?

    public init(
        video: ImportedVideo,
        onAnalyze: @escaping (ImportedVideo, TrimSelection, SwingContextInput) -> Void,
        onChooseAnother: (() -> Void)? = nil
    ) {
        self.video = video
        self.onAnalyze = onAnalyze
        self.onChooseAnother = onChooseAnother
        self._playerController = StateObject(
            wrappedValue: VideoPlayerController(video: video)
        )
        self._selection = State(initialValue: TrimSelection(video: video))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                player
                trimControls
                contextControls
                analyzeButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color(red: 0.045, green: 0.055, blue: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: video.id) {
            await loadThumbnails()
        }
        .onAppear {
            playerController.setPlaybackRange(selection)
            playerController.seek(to: selection.start)
        }
        .onChange(of: selection) { _, updatedSelection in
            playerController.setPlaybackRange(updatedSelection, seekIfOutsideRange: false)
        }
        .onDisappear {
            playerController.pause()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onChooseAnother {
                Button(action: onChooseAnother) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Choose another video")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Trim your swing")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.97, green: 0.94, blue: 0.86))
                Text("Keep one complete swing in the coral window")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)
        }
    }

    private var player: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black)

            VideoPlayerView(player: playerController.player)
                .aspectRatio(video.aspectRatio, contentMode: .fit)
                .frame(maxHeight: 460)

            if !playerController.isReady {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if let playbackError = playerController.playbackError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
                    Text(playbackError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                playerController.togglePlayback()
            } label: {
                Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.62), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .accessibilityLabel(playerController.isPlaying ? "Pause" : "Play selected swing")
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text(Self.formatTime(playerController.currentTime))
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var trimControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SWING START")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(Self.formatTime(selection.start))
                        .font(.headline.monospacedDigit())
                }

                Spacer()

                Text("\(selection.duration, specifier: "%.1f") sec clip")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color(red: 1, green: 0.42, blue: 0.34).opacity(0.13),
                        in: Capsule()
                    )

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("SWING END")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(Self.formatTime(selection.end))
                        .font(.headline.monospacedDigit())
                }
            }

            TrimTimelineView(
                selection: $selection,
                thumbnails: thumbnails,
                currentTime: playerController.currentTime,
                onSeek: playerController.scrub,
                onScrubbingChanged: { isScrubbing in
                    if isScrubbing {
                        playerController.beginScrubbing()
                    } else {
                        playerController.endScrubbing()
                    }
                }
            )

            clipPositionControl

            if let thumbnailError {
                Label(thumbnailError, systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 12) {
                frameStepButton(direction: -1)

                Button {
                    playerController.togglePlayback()
                } label: {
                    Label(
                        playerController.isPlaying ? "Pause" : "Preview clip",
                        systemImage: playerController.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.09), in: Capsule())
                }

                frameStepButton(direction: 1)
            }
            .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var clipPositionControl: some View {
        let maximumStart = max(0, selection.assetDuration - selection.duration)

        return HStack(spacing: 10) {
            Image(systemName: "arrow.left.and.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))

            Slider(
                value: Binding(
                    get: { selection.start },
                    set: { proposedStart in
                        selection.moveRange(toStart: proposedStart)
                        playerController.seek(to: selection.start)
                    }
                ),
                in: Self.clipPositionRange(maximumStart: maximumStart),
                onEditingChanged: { isEditing in
                    if isEditing {
                        playerController.beginScrubbing()
                    } else {
                        playerController.endScrubbing()
                    }
                }
            )
            .tint(Color(red: 1, green: 0.42, blue: 0.34))
            .disabled(maximumStart <= 0)
            .accessibilityLabel("Clip position")
            .accessibilityValue(
                "Starts at \(Self.formatTime(selection.start))"
            )

            Text(Self.formatTime(selection.start))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 48, alignment: .trailing)
        }
    }

    static func clipPositionRange(
        maximumStart: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        let minimumNonemptySpan = 0.000_001
        let finiteMaximum = maximumStart.isFinite ? maximumStart : 0
        return 0 ... max(minimumNonemptySpan, finiteMaximum)
    }

    private var contextControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tell us about this swing")
                    .font(.title3.weight(.bold))
                Text("These details keep the coaching cues accurate.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("CAMERA VIEW")
                Picker("Camera view", selection: $context.cameraAngle) {
                    ForEach(SwingCameraAngle.allCases) { angle in
                        Text(angle.shortTitle).tag(angle)
                    }
                }
                .pickerStyle(.segmented)
                Text(context.cameraAngle.guidance)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("HANDEDNESS")
                Picker("Handedness", selection: $context.handedness) {
                    ForEach(SwingHandedness.allCases) { handedness in
                        Text(handedness.title).tag(handedness)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("CLUB")
                Menu {
                    Picker("Club", selection: $context.club) {
                        ForEach(SwingClubInput.allCases) { club in
                            Text(club.title).tag(club)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "figure.golf")
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
                        Text(context.club.title)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var analyzeButton: some View {
        Button {
            playerController.pause()
            onAnalyze(video, selection, context)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("Analyze my swing")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                Color(red: 1, green: 0.42, blue: 0.34),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(!selection.isValid)
        .opacity(selection.isValid ? 1 : 0.45)
        .accessibilityHint("Starts pose and swing analysis for the selected clip")
    }

    private func frameStepButton(direction: Int) -> some View {
        Button {
            playerController.stepFrames(direction)
        } label: {
            Image(systemName: direction < 0 ? "backward.frame.fill" : "forward.frame.fill")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 40)
                .background(Color.white.opacity(0.09), in: Capsule())
        }
        .accessibilityLabel(direction < 0 ? "Previous frame" : "Next frame")
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(.white.opacity(0.45))
    }

    private func loadThumbnails() async {
        thumbnailError = nil
        do {
            thumbnails = try await thumbnailGenerator.thumbnails(
                for: video,
                count: 12,
                maximumSize: CGSize(width: 240, height: 160)
            )
        } catch is CancellationError {
            return
        } catch {
            thumbnailError = "Frame previews are unavailable. Trimming and playback still work."
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = Int(safeSeconds) / 60
        let remainingSeconds = safeSeconds - (Double(minutes) * 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }
}
