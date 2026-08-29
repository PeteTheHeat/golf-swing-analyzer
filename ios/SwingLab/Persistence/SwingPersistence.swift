import Foundation
import OSLog
import SwiftData

enum SwingPersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.peterargany.SwingLab",
        category: "Persistence"
    )

    static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([SwingSession.self])
        let configuration = ModelConfiguration(
            "SwingLab",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        if !isStoredInMemoryOnly {
            excludeLocalStoreFromBackup(configuration.url.deletingLastPathComponent())
        }

        return container
    }

    @MainActor
    static func makeLaunchContainer(
        factory: (_ isStoredInMemoryOnly: Bool) throws -> ModelContainer = {
            try makeContainer(isStoredInMemoryOnly: $0)
        }
    ) -> ModelContainer? {
        do {
            return try factory(false)
        } catch {
            logger.error(
                "The persistent store could not be opened: \(error.localizedDescription, privacy: .private). Existing data was left unchanged. Using a temporary in-memory store for this launch."
            )
        }

        do {
            return try factory(true)
        } catch {
            logger.fault(
                "The temporary in-memory store could not be created: \(error.localizedDescription, privacy: .private)."
            )
            return nil
        }
    }

    @MainActor
    static let previewContainer: ModelContainer = {
        do {
            return try makeContainer(isStoredInMemoryOnly: true)
        } catch {
            fatalError("Unable to create the SwingLab preview store: \(error.localizedDescription)")
        }
    }()

    private static func excludeLocalStoreFromBackup(_ directoryURL: URL) {
        var mutableURL = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true

        do {
            try mutableURL.setResourceValues(values)
        } catch {
            logger.error(
                "The local data directory could not be excluded from backup: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}

@MainActor
struct SwingSessionRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create(
        title: String,
        videoRelativePath: String,
        date: Date = .now,
        cameraView: SwingCameraView = .unknown,
        handedness: GolferHandedness = .right,
        club: SwingClub = .unknown,
        rangeStart: TimeInterval = 0,
        rangeEnd: TimeInterval = 0,
        status: SwingAnalysisStatus = .draft
    ) throws -> SwingSession {
        let session = SwingSession(
            title: title,
            date: date,
            videoRelativePath: videoRelativePath,
            cameraView: cameraView,
            handedness: handedness,
            club: club,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            status: status
        )
        context.insert(session)
        try context.save()
        return session
    }

    func fetchAll() throws -> [SwingSession] {
        let descriptor = FetchDescriptor<SwingSession>(
            sortBy: [SortDescriptor(\SwingSession.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save() throws {
        try context.save()
    }

    func delete(_ session: SwingSession) async throws {
        let relativePath = session.videoRelativePath
        context.delete(session)
        try context.save()

        guard let fileURL = try await importedVideoURL(for: relativePath) else {
            return
        }

        let hasRemainingReference = try fetchAll().contains {
            $0.videoRelativePath == relativePath
        }
        try await ImportedMediaOwnership.releaseSessionReference(
            to: fileURL,
            hasRemainingSessionReference: hasRemainingReference
        )
    }

    /// Converts sessions left in an active state by process termination into a
    /// removable, honest failure state on the next launch.
    @discardableResult
    func recoverInterruptedSessions() throws -> Int {
        let interrupted = try fetchAll().filter {
            $0.analysisStatus == .queued || $0.analysisStatus == .analyzing
        }
        guard !interrupted.isEmpty else { return 0 }

        for session in interrupted {
            session.analysisStatus = .failed
        }
        try context.save()
        return interrupted.count
    }

    /// Removes imported files that have no corresponding SwiftData session.
    /// Live picker imports are protected by `ImportedMediaOwnership`.
    @discardableResult
    func removeOrphanedImportedVideos() async throws -> Int {
        let directory = try await MediaStorage.shared.importedVideosDirectory()
        let sessions = try fetchAll()
        let referencedFilenames = Set(
            sessions.compactMap { session in
                Self.isSafeRelativeFilename(session.videoRelativePath)
                    ? session.videoRelativePath
                    : nil
            }
        )
        let referencedURLs = referencedFilenames.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
        ImportedMediaOwnership.replaceKnownSessionReferences(with: referencedURLs)

        let storedFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        var removalCount = 0

        for fileURL in storedFiles {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  !referencedFilenames.contains(fileURL.lastPathComponent) else {
                continue
            }

            if try await ImportedMediaOwnership.removeOrphanedFile(fileURL) {
                removalCount += 1
            }
        }

        return removalCount
    }

    private func importedVideoURL(for relativePath: String) async throws -> URL? {
        guard Self.isSafeRelativeFilename(relativePath) else { return nil }
        let directory = try await MediaStorage.shared.importedVideosDirectory()
        return directory.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func isSafeRelativeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.contains("/")
            && !filename.contains("\\")
    }
}
