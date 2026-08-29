import AVFoundation
import PhotosUI
import SwiftUI

/// Camera-roll entry point for the import and trim flow.
public struct ImportTrimView: View {
    private let onAnalyze: (ImportedVideo, TrimSelection, SwingContextInput) -> Void

    @StateObject private var importModel: VideoImportModel
    @StateObject private var discoveryModel: SwingDiscoveryModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var preparedSelection: TrimSelection?

    public init(
        onAnalyze: @escaping (ImportedVideo, TrimSelection, SwingContextInput) -> Void
    ) {
        self.onAnalyze = onAnalyze
        self._importModel = StateObject(wrappedValue: VideoImportModel())
        self._discoveryModel = StateObject(wrappedValue: SwingDiscoveryModel())
    }

    public var body: some View {
        Group {
            if let video = importModel.importedVideo {
                readyContent(for: video)
            } else {
                pickerContent
            }
        }
        .background(Color(red: 0.045, green: 0.055, blue: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            importModel.importVideo(from: newItem)
        }
        .onChange(of: importModel.phase) { _, phase in
            if case .failed = phase {
                // Let the user pick the same asset again after it finishes
                // downloading in Photos.
                pickerItem = nil
            }
        }
    }

    @ViewBuilder
    private func readyContent(for video: ImportedVideo) -> some View {
        if Self.shouldAutomaticallyDiscover(videoDuration: video.durationSeconds) {
            if let preparedSelection {
                TrimSwingView(
                    video: video,
                    initialSelection: preparedSelection,
                    onAnalyze: onAnalyze,
                    onChooseAnother: returnToDiscovery,
                    backButtonAccessibilityLabel: "Back to detected swings"
                )
            } else {
                SwingDiscoveryView(
                    video: video,
                    model: discoveryModel,
                    onSelectCandidate: { candidate in
                        preparedSelection = candidate.trimSelection(for: video)
                    },
                    onManualTrim: {
                        discoveryModel.cancel()
                        preparedSelection = TrimSelection(video: video)
                    },
                    onChooseAnother: chooseAnotherVideo
                )
            }
        } else {
            TrimSwingView(
                video: video,
                onAnalyze: onAnalyze,
                onChooseAnother: chooseAnotherVideo
            )
        }
    }

    static func shouldAutomaticallyDiscover(videoDuration: TimeInterval) -> Bool {
        videoDuration.isFinite && videoDuration >= 1
    }

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Replay Caddie")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
                    Text("See the frame.\nFix the swing.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .foregroundStyle(Color(red: 0.97, green: 0.94, blue: 0.86))
                    Text("Choose one swing video. You’ll trim the exact swing before analysis starts.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                importCard

                VStack(alignment: .leading, spacing: 14) {
                    Label("Portrait or landscape video", systemImage: "rectangle.on.rectangle")
                    Label("Face-on or down-the-line camera", systemImage: "video")
                    Label("Your original stays in Photos", systemImage: "lock.shield")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
    }

    private var importCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(red: 1, green: 0.42, blue: 0.34).opacity(0.16))
                    .frame(width: 72, height: 72)
                Image(systemName: importModel.isLoading ? "icloud.and.arrow.down" : "play.rectangle.on.rectangle")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
            }

            switch importModel.phase {
            case .idle:
                Text("Import a swing")
                    .font(.title3.weight(.bold))
                Text("Pick a video from your camera roll. Replay Caddie makes a private working copy for analysis.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))

                pickerButton(title: "Choose from Photos", systemImage: "photo.on.rectangle")

            case .loading:
                Text("Loading full-quality video…")
                    .font(.title3.weight(.bold))
                Text("If this video is in iCloud, the download can take a moment. Keep Replay Caddie open.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 1, green: 0.42, blue: 0.34))
                Button("Cancel") {
                    importModel.cancelImport()
                    pickerItem = nil
                }
                .foregroundStyle(.white.opacity(0.8))

            case let .failed(failure):
                Text(failure.title)
                    .font(.title3.weight(.bold))
                Text(failure.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                Text(failure.recoverySuggestion)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                pickerButton(title: "Try another video", systemImage: "arrow.clockwise")

            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func pickerButton(title: String, systemImage: String) -> some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .videos,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(red: 1, green: 0.42, blue: 0.34),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .accessibilityHint("Opens your photo library with videos only")
    }

    private func chooseAnotherVideo() {
        discoveryModel.reset()
        preparedSelection = nil
        importModel.reset(removeImportedFile: true)
        pickerItem = nil
    }

    private func returnToDiscovery() {
        preparedSelection = nil
    }
}

// MARK: - Automatic swing discovery

/// A presentation-safe range produced by the automatic detector.
///
/// The range refers to the imported source file. Selecting a candidate does
/// not copy, export, or otherwise duplicate video data.
struct SwingDiscoveryCandidate: Identifiable, Equatable, Sendable {
    let id: Double
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double

    init(
        id: Double,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        confidence: Double
    ) {
        let safeStart = startSeconds.isFinite ? max(0, startSeconds) : 0
        let safeEnd = endSeconds.isFinite ? max(safeStart, endSeconds) : safeStart
        self.id = id.isFinite ? id : safeStart
        self.startSeconds = safeStart
        self.endSeconds = safeEnd
        self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
    }

    init(_ detectedClip: DetectedSwingClip) {
        self.init(
            id: detectedClip.id,
            startSeconds: detectedClip.startSeconds,
            endSeconds: detectedClip.endSeconds,
            confidence: detectedClip.confidence
        )
    }

    var durationSeconds: TimeInterval {
        max(0, endSeconds - startSeconds)
    }

    var matchLabel: String {
        switch confidence {
        case 0.76 ... 1:
            "Strong match"
        case 0.62 ..< 0.76:
            "Good match"
        default:
            "Possible swing"
        }
    }

    func trimSelection(for video: ImportedVideo) -> TrimSelection {
        TrimSelection(
            assetDuration: video.durationSeconds,
            frameDuration: video.frameDurationSeconds,
            start: startSeconds,
            end: endSeconds
        )
    }
}

protocol SwingClipDiscovering: Sendable {
    func discover(
        in video: ImportedVideo,
        progress: SwingAnalysisProgress
    ) async throws -> [SwingDiscoveryCandidate]
}

/// Bridges full-video pose extraction to the deterministic swing-clip detector.
struct VideoSwingDiscoveryService: SwingClipDiscovering, Sendable {
    static let defaultSampleRate = 5.0

    let sampleRate: Double
    let minimumJointConfidence: Double
    let detectorMinimumConfidence: Double

    init(
        sampleRate: Double = Self.defaultSampleRate,
        minimumJointConfidence: Double = 0.25,
        detectorMinimumConfidence: Double = 0.30
    ) {
        self.sampleRate = min(max(sampleRate, 1), 10)
        self.minimumJointConfidence = min(max(minimumJointConfidence, 0), 1)
        self.detectorMinimumConfidence = min(max(detectorMinimumConfidence, 0), 1)
    }

    func discover(
        in video: ImportedVideo,
        progress: SwingAnalysisProgress
    ) async throws -> [SwingDiscoveryCandidate] {
        guard video.durationSeconds >= 1 else { return [] }

        await progress.update(
            phase: .preparing,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Preparing the full video"
        )

        let extractor = VideoPoseExtractor()
        let poseTrack = try await extractor.extract(
            videoURL: video.fileURL,
            selectedRange: CMTimeRange(start: .zero, duration: video.duration),
            sampleRate: sampleRate,
            minimumJointConfidence: minimumJointConfidence,
            orientationOverride: nil,
            progress: progress
        )

        try Task.checkCancellation()
        try await progress.checkCancellation()
        await progress.update(
            phase: .detectingEvents,
            fractionCompleted: 0.86,
            message: "Grouping complete swings"
        )

        let clips = try SwingClipDetector.detect(
            in: poseTrack,
            assetDuration: video.durationSeconds,
            minimumConfidence: detectorMinimumConfidence,
            cancellationCheck: { try Task.checkCancellation() }
        )

        try Task.checkCancellation()
        try await progress.checkCancellation()
        await progress.update(
            phase: .complete,
            fractionCompleted: 1,
            message: clips.isEmpty ? "No complete swings found" : "Swings ready to review"
        )
        return clips.map(SwingDiscoveryCandidate.init)
    }
}

struct SwingDiscoveryFailure: Equatable, Sendable {
    let title: String
    let message: String
    let recoverySuggestion: String
}

@MainActor
final class SwingDiscoveryModel: ObservableObject {
    enum Phase: Equatable, Sendable {
        case idle
        case scanning
        case results([SwingDiscoveryCandidate])
        case noSwings
        case cancelled
        case failed(SwingDiscoveryFailure)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = SwingAnalysisProgressSnapshot(
        phase: .preparing,
        fractionCompleted: 0,
        processedFrameCount: 0,
        message: "Preparing the full video"
    )

    private let service: any SwingClipDiscovering
    private var currentVideoID: UUID?
    private var activeScanID = UUID()
    private var activeProgress: SwingAnalysisProgress?
    private var scanTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init(service: any SwingClipDiscovering = VideoSwingDiscoveryService()) {
        self.service = service
    }

    var isScanning: Bool {
        phase == .scanning
    }

    var progressStatusText: String {
        switch progress.phase {
        case .preparing:
            "Preparing the full video"
        case .extractingPose:
            "Checking the full video for golfer motion"
        case .detectingEvents:
            "Grouping complete swings"
        case .complete:
            "Swings ready to review"
        case .cancelled:
            "Scan cancelled"
        default:
            "Finding swings"
        }
    }

    func startIfNeeded(video: ImportedVideo) {
        guard currentVideoID != video.id || phase == .idle else { return }
        start(video: video)
    }

    func retry(video: ImportedVideo) {
        start(video: video)
    }

    func cancel() {
        guard isScanning else { return }
        stopActiveWork()
        phase = .cancelled
    }

    func reset() {
        stopActiveWork()
        currentVideoID = nil
        phase = .idle
        progress = Self.initialProgress
    }

    private func start(video: ImportedVideo) {
        stopActiveWork()
        currentVideoID = video.id
        guard video.durationSeconds >= 1 else {
            phase = .noSwings
            return
        }

        let scanID = UUID()
        let scanProgress = SwingAnalysisProgress()
        let service = self.service
        activeScanID = scanID
        activeProgress = scanProgress
        progress = Self.initialProgress
        phase = .scanning

        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await scanProgress.currentSnapshot()
                guard let self, self.activeScanID == scanID else { return }
                self.progress = snapshot
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }
            }
        }

        scanTask = Task { [weak self] in
            do {
                let candidates = try await service.discover(
                    in: video,
                    progress: scanProgress
                )
                try Task.checkCancellation()
                let finalProgress = await scanProgress.currentSnapshot()
                guard let self, self.activeScanID == scanID else { return }
                self.progressTask?.cancel()
                self.progressTask = nil
                self.scanTask = nil
                self.activeProgress = nil
                self.progress = finalProgress
                self.phase = candidates.isEmpty ? .noSwings : .results(candidates)
            } catch is CancellationError {
                guard let self, self.activeScanID == scanID else { return }
                self.progressTask?.cancel()
                self.progressTask = nil
                self.scanTask = nil
                self.activeProgress = nil
                self.phase = .cancelled
            } catch {
                guard let self, self.activeScanID == scanID else { return }
                self.progressTask?.cancel()
                self.progressTask = nil
                self.scanTask = nil
                self.activeProgress = nil
                self.phase = .failed(Self.failure(for: error))
            }
        }
    }

    private func stopActiveWork() {
        activeScanID = UUID()
        scanTask?.cancel()
        progressTask?.cancel()
        scanTask = nil
        progressTask = nil
        let progress = activeProgress
        activeProgress = nil
        if let progress {
            Task {
                await progress.cancel()
            }
        }
    }

    private static var initialProgress: SwingAnalysisProgressSnapshot {
        SwingAnalysisProgressSnapshot(
            phase: .preparing,
            fractionCompleted: 0,
            processedFrameCount: 0,
            message: "Preparing the full video"
        )
    }

    private static func failure(for error: Error) -> SwingDiscoveryFailure {
        if let poseError = error as? PoseExtractionError {
            let title: String
            switch poseError {
            case .insufficientPoseFrames:
                title = "Couldn’t see a golfer clearly"
            case .visionUnavailable:
                title = "Automatic detection isn’t available"
            default:
                title = "Couldn’t scan this video"
            }
            return SwingDiscoveryFailure(
                title: title,
                message: poseError.localizedDescription,
                recoverySuggestion: "Try again, or place the trim handles yourself."
            )
        }

        return SwingDiscoveryFailure(
            title: "Couldn’t find swings automatically",
            message: error.localizedDescription,
            recoverySuggestion: "Try again, or trim the swing manually."
        )
    }
}

private struct SwingDiscoveryView: View {
    let video: ImportedVideo
    @ObservedObject var model: SwingDiscoveryModel
    let onSelectCandidate: (SwingDiscoveryCandidate) -> Void
    let onManualTrim: () -> Void
    let onChooseAnother: () -> Void

    private let coral = Color(red: 1, green: 0.42, blue: 0.34)
    private let cream = Color(red: 0.97, green: 0.94, blue: 0.86)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                switch model.phase {
                case .idle, .scanning:
                    scanningCard
                case let .results(candidates):
                    resultsContent(candidates)
                case .noSwings:
                    recoveryCard(
                        icon: "figure.golf",
                        title: "No complete swings found",
                        message: "Keep the golfer fully visible, then scan again or place the trim handles yourself."
                    )
                case .cancelled:
                    recoveryCard(
                        icon: "pause.circle",
                        title: "Scan cancelled",
                        message: "You can restart the scan or trim the video yourself."
                    )
                case let .failed(failure):
                    recoveryCard(
                        icon: "exclamationmark.triangle",
                        title: failure.title,
                        message: "\(failure.message) \(failure.recoverySuggestion)"
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color(red: 0.045, green: 0.055, blue: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            model.startIfNeeded(video: video)
        }
        .onDisappear {
            if model.isScanning {
                model.cancel()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find your swings")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(cream)
                    Text(Self.videoSummary(video))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 8)

                Button(action: onChooseAnother) {
                    Label("Another video", systemImage: "photo.on.rectangle")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Choose another video")
            }

            Text("Replay Caddie checks the full video on this iPhone. Found clips are time ranges on this one private copy—not new video files.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanningCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(coral.opacity(0.15))
                        .frame(width: 58, height: 58)
                    Image(systemName: "figure.golf")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(coral)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finding swings")
                        .font(.title3.weight(.bold))
                    Text(model.progressStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            ProgressView(value: model.progress.fractionCompleted)
                .tint(coral)

            HStack {
                if model.progress.processedFrameCount > 0 {
                    Text("\(model.progress.processedFrameCount) frames checked")
                } else {
                    Text("This can take a moment for a long video")
                }
                Spacer()
                Text("\(Int(model.progress.fractionCompleted * 100))%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.48))

            HStack(spacing: 10) {
                Button("Cancel scan") {
                    model.cancel()
                }
                .buttonStyle(DiscoverySecondaryButtonStyle())

                Button("Trim manually", action: onManualTrim)
                    .buttonStyle(DiscoverySecondaryButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func resultsContent(_ candidates: [SwingDiscoveryCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidates.count == 1 ? "1 swing found" : "\(candidates.count) swings found")
                    .font(.title3.weight(.bold))
                Text("Choose one, then fine-tune its start and end before analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                candidateCard(candidate, number: index + 1)
            }

            HStack(spacing: 10) {
                Button("Scan again") {
                    model.retry(video: video)
                }
                .buttonStyle(DiscoverySecondaryButtonStyle())

                Button("Trim manually", action: onManualTrim)
                    .buttonStyle(DiscoverySecondaryButtonStyle())
            }
        }
    }

    private func candidateCard(
        _ candidate: SwingDiscoveryCandidate,
        number: Int
    ) -> some View {
        Button {
            onSelectCandidate(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(coral.opacity(0.14))
                            .frame(width: 48, height: 48)
                        Image(systemName: "figure.golf")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(coral)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Swing \(number)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(Self.formatTime(candidate.startSeconds))–\(Self.formatTime(candidate.endSeconds))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer(minLength: 8)

                    Text(candidate.matchLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(coral)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(coral.opacity(0.13), in: Capsule())
                }

                candidateRangeBar(candidate)

                HStack {
                    Text("\(candidate.durationSeconds, specifier: "%.1f") sec")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Label("Refine trim", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this detected range in the trim editor")
    }

    private func candidateRangeBar(_ candidate: SwingDiscoveryCandidate) -> some View {
        GeometryReader { proxy in
            let duration = max(video.durationSeconds, 0.000_001)
            let start = min(max(candidate.startSeconds / duration, 0), 1)
            let end = min(max(candidate.endSeconds / duration, start), 1)
            let availableWidth = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(coral)
                    .frame(width: max(4, availableWidth * (end - start)))
                    .offset(x: availableWidth * start)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func recoveryCard(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(coral)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Try scan again") {
                model.retry(video: video)
            }
            .buttonStyle(DiscoveryPrimaryButtonStyle(color: coral))

            Button("Trim manually", action: onManualTrim)
                .buttonStyle(DiscoverySecondaryButtonStyle())
        }
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static func videoSummary(_ video: ImportedVideo) -> String {
        "\(formatTime(video.durationSeconds)) video · \(ByteCountFormatter.string(fromByteCount: video.fileSizeBytes, countStyle: .file))"
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let minutes = Int(safeSeconds) / 60
        let remainingSeconds = safeSeconds - (Double(minutes) * 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }
}

private struct DiscoveryPrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                color.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private struct DiscoverySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
