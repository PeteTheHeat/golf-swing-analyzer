import Combine
import Foundation
import PhotosUI
import SwiftUI

public struct VideoImportFailure: Equatable, Sendable {
    public let title: String
    public let message: String
    public let recoverySuggestion: String

    public init(title: String, message: String, recoverySuggestion: String) {
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

@MainActor
public final class VideoImportModel: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready(ImportedVideo)
        case failed(VideoImportFailure)
    }

    @Published public private(set) var phase: Phase = .idle

    private var importTask: Task<Void, Never>?
    private var temporarilyOwnedFileURL: URL?

    public init() {}

    deinit {
        importTask?.cancel()
        let fileURL = temporarilyOwnedFileURL
        Task { @MainActor in
            if let fileURL {
                try? await ImportedMediaOwnership.releaseTemporaryImport(fileURL)
            }
        }
    }

    public var importedVideo: ImportedVideo? {
        guard case let .ready(video) = phase else { return nil }
        return video
    }

    public var isLoading: Bool {
        phase == .loading
    }

    public func importVideo(from item: PhotosPickerItem) {
        importTask?.cancel()
        releaseTemporarilyOwnedFile()
        phase = .loading

        importTask = Task { [weak self] in
            var unclaimedFileURL: URL?
            do {
                // For iCloud-only assets this await remains suspended while the
                // system downloads and materializes the movie.
                guard let transfer = try await item.loadTransferable(
                    type: VideoFileTransfer.self
                ) else {
                    throw VideoImportError.noFileWasProvided
                }

                unclaimedFileURL = transfer.storedFileURL
                try Task.checkCancellation()
                let video = try await VideoImporter.validate(transfer)
                try Task.checkCancellation()
                guard let self else {
                    try? await MediaStorage.shared.removeImportedVideo(at: video.fileURL)
                    return
                }

                ImportedMediaOwnership.registerTemporaryImport(video.fileURL)
                temporarilyOwnedFileURL = video.fileURL
                unclaimedFileURL = nil
                phase = .ready(video)
            } catch is CancellationError {
                if let unclaimedFileURL {
                    try? await MediaStorage.shared.removeImportedVideo(at: unclaimedFileURL)
                }
                guard let self, case .loading = self.phase else { return }
                self.phase = .idle
            } catch {
                if let unclaimedFileURL {
                    try? await MediaStorage.shared.removeImportedVideo(at: unclaimedFileURL)
                }
                self?.phase = .failed(Self.failure(for: error))
            }
        }
    }

    public func cancelImport() {
        importTask?.cancel()
        importTask = nil
        if case .loading = phase {
            phase = .idle
        }
    }

    public func reset(removeImportedFile: Bool = true) {
        importTask?.cancel()
        importTask = nil

        phase = .idle

        if removeImportedFile {
            releaseTemporarilyOwnedFile()
        }
    }

    private func releaseTemporarilyOwnedFile() {
        guard let fileURL = temporarilyOwnedFileURL else { return }
        temporarilyOwnedFileURL = nil
        Task { @MainActor in
            try? await ImportedMediaOwnership.releaseTemporaryImport(fileURL)
        }
    }

    private static func failure(for error: Error) -> VideoImportFailure {
        if let importError = error as? VideoImportError {
            return VideoImportFailure(
                title: "Couldn’t import video",
                message: importError.errorDescription ?? "The video could not be imported.",
                recoverySuggestion: importError.recoverySuggestion
                    ?? "Choose a different video and try again."
            )
        }

        let cocoaError = error as NSError
        let isLikelyCloudOrNetworkError = cocoaError.domain == NSCocoaErrorDomain
            || cocoaError.domain == NSURLErrorDomain

        return VideoImportFailure(
            title: "Couldn’t load video",
            message: isLikelyCloudOrNetworkError
                ? "The full-quality video may not have finished downloading from iCloud."
                : "The selected item could not be opened as a video.",
            recoverySuggestion: "Check your connection, open the video in Photos, then try again."
        )
    }
}
