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

        let requestedTimes = makeRequestedTimes(video: video, count: count)
        var thumbnails: [VideoThumbnail] = []
        thumbnails.reserveCapacity(requestedTimes.count)

        for (index, requestedTime) in requestedTimes.enumerated() {
            try Task.checkCancellation()
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

    private func makeRequestedTimes(video: ImportedVideo, count: Int) -> [CMTime] {
        let duration = video.durationSeconds
        guard duration > 0 else { return [.zero] }

        let lastSafeTime = max(0, duration - video.frameDurationSeconds)
        guard count > 1 else {
            return [CMTime(seconds: lastSafeTime / 2, preferredTimescale: 60_000)]
        }

        return (0 ..< count).map { index in
            let progress = Double(index) / Double(count - 1)
            return CMTime(
                seconds: lastSafeTime * progress,
                preferredTimescale: 60_000
            )
        }
    }
}
