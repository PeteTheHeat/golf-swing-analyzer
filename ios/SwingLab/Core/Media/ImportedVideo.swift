import AVFoundation
import CoreGraphics
import Foundation

/// A validated video that has been copied into Replay Caddie's private app storage.
///
/// This type deliberately contains no persistence-model references. Feature and
/// persistence layers can pass it across their boundary without retaining a
/// Photos-library identifier or temporary picker URL.
public struct ImportedVideo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let displayName: String
    public let duration: CMTime
    public let naturalSize: CGSize
    public let nominalFrameRate: Float
    public let frameDuration: CMTime
    public let fileSizeBytes: Int64
    public let importedAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String,
        duration: CMTime,
        naturalSize: CGSize,
        nominalFrameRate: Float,
        frameDuration: CMTime,
        fileSizeBytes: Int64,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.duration = duration
        self.naturalSize = naturalSize
        self.nominalFrameRate = nominalFrameRate
        self.frameDuration = frameDuration
        self.fileSizeBytes = fileSizeBytes
        self.importedAt = importedAt
    }

    public static func == (lhs: ImportedVideo, rhs: ImportedVideo) -> Bool {
        lhs.id == rhs.id
            && lhs.fileURL == rhs.fileURL
            && lhs.duration == rhs.duration
            && lhs.naturalSize == rhs.naturalSize
            && lhs.nominalFrameRate == rhs.nominalFrameRate
            && lhs.frameDuration == rhs.frameDuration
            && lhs.fileSizeBytes == rhs.fileSizeBytes
    }

    public var durationSeconds: TimeInterval {
        guard duration.isNumeric else { return 0 }
        return max(0, duration.seconds)
    }

    public var frameDurationSeconds: TimeInterval {
        if frameDuration.isNumeric, frameDuration.seconds > 0 {
            return frameDuration.seconds
        }
        if nominalFrameRate > 0 {
            return 1 / Double(nominalFrameRate)
        }
        return 1 / 30
    }

    public var aspectRatio: CGFloat {
        guard naturalSize.height > 0 else { return 9 / 16 }
        return naturalSize.width / naturalSize.height
    }
}

public enum VideoImportError: Error, Equatable, LocalizedError, Sendable {
    case noFileWasProvided
    case fileIsNotReadable
    case fileIsEmpty
    case unsupportedVideo
    case noVideoTrack
    case invalidDuration
    case storageUnavailable
    case copyFailed
    case metadataLoadFailed
    case thumbnailGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .noFileWasProvided:
            "The selected item did not contain a video file."
        case .fileIsNotReadable:
            "Replay Caddie could not read this video."
        case .fileIsEmpty:
            "The selected video is empty."
        case .unsupportedVideo:
            "This video format cannot be played on this device."
        case .noVideoTrack:
            "The selected file does not contain a video track."
        case .invalidDuration:
            "Replay Caddie could not determine the video's duration."
        case .storageUnavailable:
            "Replay Caddie could not open its private video storage."
        case .copyFailed:
            "Replay Caddie could not save a private copy of this video."
        case .metadataLoadFailed:
            "Replay Caddie could not inspect this video."
        case .thumbnailGenerationFailed:
            "Replay Caddie could not create preview frames for this video."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noFileWasProvided, .unsupportedVideo, .noVideoTrack, .invalidDuration, .fileIsEmpty:
            "Choose a different video from your camera roll."
        case .fileIsNotReadable, .copyFailed, .metadataLoadFailed:
            "Make sure the video has finished downloading from iCloud, then try again."
        case .storageUnavailable:
            "Free some storage on this iPhone, then try again."
        case .thumbnailGenerationFailed:
            "You can still trim the video. Try reopening this screen if previews do not appear."
        }
    }
}

/// Reads AVFoundation metadata only after a picker transfer has produced a
/// durable, app-owned file.
public enum ImportedVideoValidator {
    public static func validate(
        storedFileURL: URL,
        displayName: String? = nil
    ) async throws -> ImportedVideo {
        let values: URLResourceValues
        do {
            values = try storedFileURL.resourceValues(forKeys: [
                .isReadableKey,
                .isRegularFileKey,
                .fileSizeKey,
            ])
        } catch {
            throw VideoImportError.fileIsNotReadable
        }

        guard values.isRegularFile == true, values.isReadable == true else {
            throw VideoImportError.fileIsNotReadable
        }

        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize > 0 else {
            throw VideoImportError.fileIsEmpty
        }

        let asset = AVURLAsset(url: storedFileURL)

        do {
            let (isReadable, isPlayable, duration) = try await asset.load(
                .isReadable,
                .isPlayable,
                .duration
            )

            guard isReadable else {
                throw VideoImportError.fileIsNotReadable
            }
            guard isPlayable else {
                throw VideoImportError.unsupportedVideo
            }
            guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
                throw VideoImportError.invalidDuration
            }

            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else {
                throw VideoImportError.noVideoTrack
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let loadedFrameDuration = try await videoTrack.load(.minFrameDuration)

            let transformedRect = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
            let orientedSize = CGSize(
                width: abs(transformedRect.width),
                height: abs(transformedRect.height)
            )
            let safeSize = orientedSize.width > 0 && orientedSize.height > 0
                ? orientedSize
                : naturalSize
            let safeFrameDuration: CMTime
            if loadedFrameDuration.isNumeric, loadedFrameDuration.seconds > 0 {
                safeFrameDuration = loadedFrameDuration
            } else if nominalFrameRate > 0 {
                safeFrameDuration = CMTime(
                    seconds: 1 / Double(nominalFrameRate),
                    preferredTimescale: 60_000
                )
            } else {
                safeFrameDuration = CMTime(value: 1, timescale: 30)
            }

            return ImportedVideo(
                fileURL: storedFileURL,
                displayName: normalizedDisplayName(
                    displayName ?? storedFileURL.lastPathComponent
                ),
                duration: duration,
                naturalSize: safeSize,
                nominalFrameRate: nominalFrameRate,
                frameDuration: safeFrameDuration,
                fileSizeBytes: fileSize
            )
        } catch let error as VideoImportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoImportError.metadataLoadFailed
        }
    }

    private static func normalizedDisplayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Camera Roll Video" }
        return trimmed
    }
}
