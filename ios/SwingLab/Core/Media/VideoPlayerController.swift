import AVFoundation
import Combine
import Foundation

@MainActor
public final class VideoPlayerController: ObservableObject {
    public let player: AVPlayer
    public let video: ImportedVideo

    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isReady = false
    @Published public private(set) var playbackError: String?

    private var trimStart: TimeInterval = 0
    private var trimEnd: TimeInterval
    // AVFoundation and NotificationCenter return opaque Objective-C tokens.
    // Access is still confined to this @MainActor controller during life; the
    // unsafe annotation only permits deterministic cleanup from nonisolated deinit.
    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var wasPlayingBeforeScrub = false

    public init(video: ImportedVideo) {
        self.video = video
        self.trimEnd = video.durationSeconds

        let item = AVPlayerItem(url: video.fileURL)
        self.player = AVPlayer(playerItem: item)
        self.player.actionAtItemEnd = .pause
        self.player.automaticallyWaitsToMinimizeStalling = true

        installObservers(for: item)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObservation?.invalidate()
    }

    public func setPlaybackRange(_ selection: TrimSelection, seekIfOutsideRange: Bool = true) {
        trimStart = selection.start
        trimEnd = selection.end
        player.currentItem?.forwardPlaybackEndTime = selection.endTime

        if seekIfOutsideRange,
           currentTime < selection.start || currentTime > selection.end {
            seek(to: selection.start)
        }
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func play() {
        isPlaying = true
        if currentTime >= trimEnd - video.frameDurationSeconds {
            seek(to: trimStart) { [weak self] in
                self?.player.play()
            }
        } else {
            player.play()
        }
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func seek(
        to seconds: TimeInterval,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let boundedSeconds = min(max(seconds, trimStart), trimEnd)
        let time = CMTime(seconds: boundedSeconds, preferredTimescale: 60_000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                self?.currentTime = boundedSeconds
                completion?()
            }
        }
    }

    public func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        pause()
    }

    public func scrub(to seconds: TimeInterval) {
        seek(to: seconds)
    }

    public func endScrubbing() {
        if wasPlayingBeforeScrub {
            play()
        }
        wasPlayingBeforeScrub = false
    }

    public func stepFrames(_ count: Int) {
        guard count != 0, isReady else { return }
        pause()

        guard let item = player.currentItem else { return }
        item.step(byCount: count)

        // AVPlayerItem's step operation is frame-accurate. Publish an immediate
        // estimate; the periodic observer then replaces it with the actual time.
        currentTime = min(
            max(currentTime + (Double(count) * video.frameDurationSeconds), trimStart),
            trimEnd
        )
        if currentTime <= trimStart || currentTime >= trimEnd {
            seek(to: currentTime)
        }
    }

    private func installObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 1 / 30, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds.isFinite ? time.seconds : 0
                self.currentTime = seconds
                self.isPlaying = self.player.rate != 0

                if seconds >= self.trimEnd {
                    self.player.pause()
                    self.isPlaying = false
                    self.currentTime = self.trimEnd
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.trimEnd
            }
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    self.playbackError = nil
                case .failed:
                    self.isReady = false
                    self.playbackError = item.error?.localizedDescription
                        ?? "This video could not be played."
                case .unknown:
                    self.isReady = false
                @unknown default:
                    self.isReady = false
                }
            }
        }
    }
}
