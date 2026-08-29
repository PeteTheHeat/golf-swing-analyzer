import AVFoundation
import CoreGraphics
import Foundation

public struct VideoThumbnail: Identifiable, @unchecked Sendable {
    public let id: Int
    public let requestedTime: CMTime
    public let actualTime: CMTime
    public let image: CGImage

    public init(id: Int, requestedTime: CMTime, actualTime: CMTime, image: CGImage) {
        self.id = id
        self.requestedTime = requestedTime
        self.actualTime = actualTime
        self.image = image
    }
}

/// Produces an evenly spaced filmstrip without decoding the entire video.
public actor VideoThumbnailGenerator {
    public init() {}

    public func thumbnails(
        for video: ImportedVideo,
        range: CMTimeRange? = nil,
        count: Int,
        maximumSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> [VideoThumbnail] {
        guard count > 0 else { return [] }

        let asset = AVURLAsset(url: video.fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize

        // A small tolerance lets AVFoundation use nearby keyframes. This keeps
        // filmstrip generation responsive even for long, highly compressed clips.
        let tolerance = CMTime(
            seconds: min(max(video.frameDurationSeconds * 2, 1 / 30), 0.1),
            preferredTimescale: 60_000
        )
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let usesSelectedRange: Bool
        if let range {
            usesSelectedRange = range.start.isNumeric
                && range.duration.isNumeric
                && range.duration.seconds > 0
        } else {
            usesSelectedRange = false
        }
        let requestedTimes = ThumbnailTimeSampler.seconds(
            videoDuration: video.durationSeconds,
            frameDuration: video.frameDurationSeconds,
            rangeStart: range?.start.seconds,
            rangeDuration: range?.duration.seconds,
            count: count
        ).map {
            CMTime(seconds: $0, preferredTimescale: 60_000)
        }
        var thumbnails: [VideoThumbnail] = []
        thumbnails.reserveCapacity(requestedTimes.count)

        for (index, requestedTime) in requestedTimes.enumerated() {
            try Task.checkCancellation()
            // Keep tolerance inside the selected swing. Interior requests can
            // still use nearby keyframes, while edge requests become exact.
            if usesSelectedRange,
               let firstTime = requestedTimes.first?.seconds,
               let lastTime = requestedTimes.last?.seconds {
                generator.requestedTimeToleranceBefore = CMTime(
                    seconds: min(
                        tolerance.seconds,
                        max(0, requestedTime.seconds - firstTime)
                    ),
                    preferredTimescale: 60_000
                )
                generator.requestedTimeToleranceAfter = CMTime(
                    seconds: min(
                        tolerance.seconds,
                        max(0, lastTime - requestedTime.seconds)
                    ),
                    preferredTimescale: 60_000
                )
            } else {
                generator.requestedTimeToleranceBefore = tolerance
                generator.requestedTimeToleranceAfter = tolerance
            }
            do {
                let (image, actualTime) = try await generator.image(at: requestedTime)
                thumbnails.append(
                    VideoThumbnail(
                        id: index,
                        requestedTime: requestedTime,
                        actualTime: actualTime,
                        image: image
                    )
                )
            } catch is CancellationError {
                generator.cancelAllCGImageGeneration()
                throw CancellationError()
            } catch {
                // One damaged GOP should not blank the complete filmstrip.
                continue
            }
        }

        guard !thumbnails.isEmpty else {
            throw VideoImportError.thumbnailGenerationFailed
        }
        return thumbnails
    }
}

enum ThumbnailTimeSampler {
    static func seconds(
        videoDuration: Double,
        frameDuration: Double,
        rangeStart: Double? = nil,
        rangeDuration: Double? = nil,
        count: Int
    ) -> [Double] {
        guard count > 0 else { return [] }
        guard videoDuration.isFinite, videoDuration > 0 else { return [0] }

        let safeFrameDuration = frameDuration.isFinite && frameDuration > 0
            ? frameDuration
            : 1 / 30
        let videoEnd = max(0, videoDuration - safeFrameDuration)

        let requestedStart = rangeStart.flatMap { $0.isFinite ? $0 : nil }
        let requestedDuration = rangeDuration.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let start: Double
        let end: Double
        if let requestedStart, let requestedDuration {
            start = min(videoEnd, max(0, requestedStart))
            end = min(videoEnd, max(start, requestedStart + requestedDuration - safeFrameDuration))
        } else {
            start = 0
            end = videoEnd
        }

        guard count > 1 else { return [(start + end) / 2] }
        return (0 ..< count).map { index in
            let progress = Double(index) / Double(count - 1)
            return start + (end - start) * progress
        }
    }
}
