import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The FileRepresentation used by PhotosPicker.
///
/// `loadTransferable` can materialize an iCloud-backed asset. The import closure
/// immediately copies that materialized file into app-owned Application Support
/// storage, so callers never retain the picker's short-lived URL.
public struct VideoFileTransfer: Transferable, Sendable {
    public let storedFileURL: URL
    public let originalFilename: String

    public init(storedFileURL: URL, originalFilename: String) {
        self.storedFileURL = storedFileURL
        self.originalFilename = originalFilename
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { receivedFile in
            try Task.checkCancellation()

            let originalFilename = receivedFile.file.lastPathComponent
            let storedURL = try await MediaStorage.shared.importTransferredFile(
                at: receivedFile.file,
                suggestedFilename: originalFilename
            )

            do {
                try Task.checkCancellation()
                return VideoFileTransfer(
                    storedFileURL: storedURL,
                    originalFilename: originalFilename
                )
            } catch {
                try? await MediaStorage.shared.removeImportedVideo(at: storedURL)
                throw error
            }
        }
    }
}

public enum VideoImporter {
    /// Validates a picker transfer and removes its app-owned copy if validation
    /// fails or the task is cancelled.
    public static func validate(_ transfer: VideoFileTransfer) async throws -> ImportedVideo {
        do {
            try Task.checkCancellation()
            let video = try await ImportedVideoValidator.validate(
                storedFileURL: transfer.storedFileURL,
                displayName: transfer.originalFilename
            )
            try Task.checkCancellation()
            return video
        } catch {
            try? await MediaStorage.shared.removeImportedVideo(at: transfer.storedFileURL)
            throw error
        }
    }
}
