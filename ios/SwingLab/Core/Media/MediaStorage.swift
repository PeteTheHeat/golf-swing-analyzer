import Foundation

/// Owns large imported media files without loading them into memory.
///
/// Picker-provided URLs are temporary. Every file is coordinated, copied to a
/// staging URL, and then moved into Application Support before the picker load
/// completes.
public actor MediaStorage {
    public static let shared = MediaStorage()

    private let fileManager: FileManager
    private let directoryName = "Imported Videos"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func importTransferredFile(
        at sourceURL: URL,
        suggestedFilename: String? = nil
    ) async throws -> URL {
        try Task.checkCancellation()

        let storageDirectory: URL
        do {
            storageDirectory = try importedVideosDirectory()
        } catch {
            throw VideoImportError.storageUnavailable
        }

        let fileExtension = safeExtension(
            from: suggestedFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }
                ?? sourceURL.pathExtension
        )
        let identifier = UUID().uuidString.lowercased()
        let destinationURL = storageDirectory
            .appendingPathComponent(identifier)
            .appendingPathExtension(fileExtension)
        let stagingURL = storageDirectory
            .appendingPathComponent(".\(identifier).importing")

        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            try? fileManager.removeItem(at: stagingURL)
        }

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: stagingURL)
            } catch {
                copyError = error
            }
        }

        if coordinationError != nil || copyError != nil {
            throw VideoImportError.copyFailed
        }

        try Task.checkCancellation()

        do {
            #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: stagingURL.path
            )
            #endif
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            try excludeFromBackup(destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw VideoImportError.copyFailed
        }

        return destinationURL
    }

    public func removeImportedVideo(at fileURL: URL) throws {
        guard isInsideImportedVideosDirectory(fileURL) else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw VideoImportError.storageUnavailable
        }
    }

    public func importedVideosDirectory() throws -> URL {
        let applicationSupport: URL
        do {
            applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw VideoImportError.storageUnavailable
        }

        let directory = applicationSupport
            .appendingPathComponent("SwingLab", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try excludeFromBackup(directory)
        } catch {
            throw VideoImportError.storageUnavailable
        }

        return directory
    }

    private func isInsideImportedVideosDirectory(_ fileURL: URL) -> Bool {
        guard let directory = try? importedVideosDirectory() else { return false }
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        return resolvedFile.deletingLastPathComponent() == resolvedDirectory
    }

    private func safeExtension(from candidate: String) -> String {
        let normalized = candidate.lowercased()
        let allowed = CharacterSet.alphanumerics
        let scalarsAreSafe = normalized.unicodeScalars.allSatisfy(allowed.contains)
        guard scalarsAreSafe, (1 ... 10).contains(normalized.count) else {
            return "mov"
        }
        return normalized
    }

    private func excludeFromBackup(_ fileURL: URL) throws {
        var mutableURL = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

/// Coordinates the temporary import owner with durable session references.
///
/// A video is deleted only after both kinds of ownership have been released.
/// All state changes run on the main actor so a session can claim a video in
/// the same synchronous transaction that creates its SwiftData record.
@MainActor
enum ImportedMediaOwnership {
    private static var temporaryImports: Set<URL> = []
    private static var sessionReferences: Set<URL> = []

    static func registerTemporaryImport(_ fileURL: URL) {
        temporaryImports.insert(key(for: fileURL))
    }

    static func retainForSession(_ fileURL: URL) {
        sessionReferences.insert(key(for: fileURL))
    }

    static func replaceKnownSessionReferences(with fileURLs: [URL]) {
        sessionReferences = Set(fileURLs.map(key(for:)))
    }

    static func releaseTemporaryImport(_ fileURL: URL) async throws {
        let fileKey = key(for: fileURL)
        temporaryImports.remove(fileKey)
        try await removeIfUnowned(fileKey)
    }

    static func releaseSessionReference(
        to fileURL: URL,
        hasRemainingSessionReference: Bool
    ) async throws {
        let fileKey = key(for: fileURL)
        if hasRemainingSessionReference {
            sessionReferences.insert(fileKey)
            return
        }

        sessionReferences.remove(fileKey)
        try await removeIfUnowned(fileKey)
    }

    @discardableResult
    static func removeOrphanedFile(_ fileURL: URL) async throws -> Bool {
        let fileKey = key(for: fileURL)
        guard !temporaryImports.contains(fileKey),
              !sessionReferences.contains(fileKey) else {
            return false
        }

        try await MediaStorage.shared.removeImportedVideo(at: fileKey)
        return true
    }

    private static func removeIfUnowned(_ fileURL: URL) async throws {
        guard !temporaryImports.contains(fileURL),
              !sessionReferences.contains(fileURL) else {
            return
        }
        try await MediaStorage.shared.removeImportedVideo(at: fileURL)
    }

    private static func key(for fileURL: URL) -> URL {
        fileURL.standardizedFileURL.resolvingSymlinksInPath()
    }
}
