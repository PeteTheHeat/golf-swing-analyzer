import Foundation
import SwiftData
import Testing
@testable import SwingLab
@Suite("App persistence")
@MainActor
struct AppAndPersistenceTests {
    @Test("Release identity reads display name, version, and build metadata")
    func releaseIdentityMetadata() {
        let identity = AppReleaseIdentity(infoDictionary: [
            "CFBundleDisplayName": "  Test Fairway  ",
            "CFBundleName": "InternalTarget",
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleVersion": "57"
        ])

        #expect(identity.displayName == "Test Fairway")
        #expect(identity.version == "2.3.4")
        #expect(identity.build == "57")
        #expect(identity.footerText == "Test Fairway 2.3.4 (57)")
    }

    @Test("Release identity uses safe fallbacks for missing metadata")
    func releaseIdentityFallbacks() {
        let targetFallback = AppReleaseIdentity(infoDictionary: [
            "CFBundleDisplayName": " \n ",
            "CFBundleName": "InternalTarget",
            "CFBundleVersion": "8"
        ])
        let genericFallback = AppReleaseIdentity(infoDictionary: [:])

        #expect(targetFallback.footerText == "InternalTarget build 8")
        #expect(genericFallback.footerText == "Replay Caddie")
    }

    @Test("A session stores clip and golfer context")
    func sessionFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let session = SwingSession(
            id: id,
            title: "Range driver",
            date: date,
            videoRelativePath: "Videos/range-driver.mov",
            cameraView: .downTheLine,
            handedness: .left,
            club: .driver,
            rangeStart: 4.25,
            rangeEnd: 7.75,
            score: 7.4,
            status: .complete,
            referenceID: "pro-rory-dtl-driver"
        )

        #expect(session.id == id)
        #expect(session.date == date)
        #expect(session.videoRelativePath == "Videos/range-driver.mov")
        #expect(session.cameraView == .downTheLine)
        #expect(session.golferHandedness == .left)
        #expect(session.selectedClub == .driver)
        #expect(session.rangeDuration == 3.5)
        #expect(session.score == 7.4)
        #expect(session.analysisStatus == .complete)
        #expect(session.referenceID == "pro-rory-dtl-driver")
    }

    @Test("Invalid ranges are normalized")
    func rangeNormalization() {
        let session = SwingSession(
            title: "Trim",
            videoRelativePath: "Videos/trim.mov",
            rangeStart: -2,
            rangeEnd: -1
        )

        #expect(session.rangeStart == 0)
        #expect(session.rangeEnd == 0)

        session.updateRange(start: 8, end: 4)
        #expect(session.rangeStart == 8)
        #expect(session.rangeEnd == 8)
    }

    @Test("Analysis JSON round trips without knowing the result type")
    func analysisRoundTrip() throws {
        struct Finding: Codable, Equatable {
            let title: String
            let frameTime: Double
        }

        let expected = Finding(title: "Maintain spine angle", frameTime: 1.42)
        let session = SwingSession(title: "Analysis", videoRelativePath: "Videos/analysis.mov")

        try session.setAnalysis(expected)
        let decoded = try session.analysis(as: Finding.self)

        #expect(decoded == expected)
        #expect(session.analysisJSON?.contains("Maintain spine angle") == true)
    }

    @Test("Repository writes to an isolated local store")
    func repositoryRoundTrip() throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)

        let inserted = try repository.create(
            title: "Face-on wedge",
            videoRelativePath: "Videos/wedge.mov",
            cameraView: .faceOn,
            handedness: .right,
            club: .wedge,
            rangeStart: 1,
            rangeEnd: 3
        )
        let sessions = try repository.fetchAll()

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == inserted.id)
        #expect(sessions.first?.cameraView == .faceOn)
    }

    @Test("Repository persists local references as private and unverified")
    func privateReferenceProvenance() throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)

        let session = try repository.create(
            title: "Imported coach swing",
            videoRelativePath: "coach.mov",
            cameraView: .downTheLine,
            club: .driver,
            status: .complete,
            saveTarget: .privateReference(PrivateReferenceInput(
                displayName: "  Coach example  ",
                golferName: "  Sam Coach  "
            ))
        )
        try session.setAnalysis(["result": "complete"])
        try repository.save()

        #expect(session.sessionOrigin == .reference)
        #expect(session.isPrivateReference)
        #expect(session.referenceSourceKind == ReferenceSwingDescriptor.SourceKind.userImported.rawValue)
        #expect(session.referenceDisplayName == "Coach example")
        #expect(session.referenceGolferName == "Sam Coach")
        #expect(session.referenceAllowedUse == ReferenceAllowedUse.privateAnalysisOnly.rawValue)
        #expect(session.referenceRightsStatus == ReferenceRightsStatus.unverified.rawValue)
        #expect(session.referenceLicenseName == nil)
        #expect(session.referenceSourceURL == nil)
        #expect(ReferenceSwingDescriptorFactory.make(from: session)?.isDistributionReady == false)
    }

    @Test("Repository rejects an unnamed private reference")
    func rejectsUnnamedPrivateReference() throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)

        #expect(throws: SwingSessionRepositoryError.self) {
            try repository.create(
                title: "Fallback title must not bypass validation",
                videoRelativePath: "reference.mov",
                saveTarget: .privateReference(PrivateReferenceInput(displayName: " \n "))
            )
        }
        #expect(try repository.fetchAll().isEmpty)
    }

    @Test("Review subjects retain private-reference provenance")
    func privateReferenceReviewSubject() {
        let session = SwingSession(
            title: "Coach model",
            videoRelativePath: "coach.mov"
        )
        session.apply(saveTarget: .privateReference(PrivateReferenceInput(
            displayName: "Coach model"
        )))

        let subject = AnalysisReviewSubject(session: session)

        #expect(subject.reviewLabel == "Private reference")
        #expect(subject.comparisonPaneTitle == "PRIVATE REFERENCE")
        #expect(subject.displayName == "Coach model")
    }

    @Test("New personal sessions are explicit while legacy nil remains personal")
    func personalOriginCompatibility() throws {
        let legacy = SwingSession(title: "Legacy", videoRelativePath: "legacy.mov")
        #expect(legacy.origin == nil)
        #expect(legacy.sessionOrigin == .personal)

        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let created = try SwingSessionRepository(context: container.mainContext).create(
            title: "New",
            videoRelativePath: "new.mov"
        )
        #expect(created.origin == SwingSessionOrigin.personal.rawValue)
        #expect(created.isPersonalSwing)
    }

    @Test("Launch uses an in-memory store if the persistent store cannot open")
    func launchStoreFallback() throws {
        enum PersistentStoreError: Error {
            case unavailable
        }

        let fallback = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        var attempts: [Bool] = []

        let container = SwingPersistence.makeLaunchContainer { isStoredInMemoryOnly in
            attempts.append(isStoredInMemoryOnly)
            guard isStoredInMemoryOnly else {
                throw PersistentStoreError.unavailable
            }
            return fallback
        }

        #expect(attempts == [false, true])
        #expect(container === fallback)
    }

    @Test("Launch remains non-crashing if no store can be created")
    func launchStoreUnavailable() {
        enum StoreError: Error {
            case unavailable
        }

        var attempts: [Bool] = []
        let container = SwingPersistence.makeLaunchContainer { isStoredInMemoryOnly in
            attempts.append(isStoredInMemoryOnly)
            throw StoreError.unavailable
        }

        #expect(attempts == [false, true])
        #expect(container == nil)
    }

    @Test("Interrupted sessions become removable failures")
    func interruptedSessionRecovery() throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)
        let analyzing = try repository.create(
            title: "Interrupted",
            videoRelativePath: "interrupted.mov",
            status: .analyzing
        )
        let complete = try repository.create(
            title: "Complete",
            videoRelativePath: "complete.mov",
            status: .complete
        )

        let recoveredCount = try repository.recoverInterruptedSessions()

        #expect(recoveredCount == 1)
        #expect(analyzing.analysisStatus == .failed)
        #expect(complete.analysisStatus == .complete)
    }

    @Test("Releasing the picker owner keeps media retained by a session")
    func completedSessionRetainsImportedMedia() async throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)
        let directory = try await MediaStorage.shared.importedVideosDirectory()
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).mov")
        try Data([0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = try repository.create(
            title: "Saved",
            videoRelativePath: fileURL.lastPathComponent,
            status: .complete
        )
        ImportedMediaOwnership.registerTemporaryImport(fileURL)
        ImportedMediaOwnership.retainForSession(fileURL)

        try await ImportedMediaOwnership.releaseTemporaryImport(fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try await repository.delete(session)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try repository.fetchAll().isEmpty)
    }

    @Test("Deleting one of two sessions preserves shared media")
    func sharedMediaDeletion() async throws {
        let container = try SwingPersistence.makeContainer(isStoredInMemoryOnly: true)
        let repository = SwingSessionRepository(context: container.mainContext)
        let directory = try await MediaStorage.shared.importedVideosDirectory()
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).mov")
        try Data([0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = try repository.create(
            title: "First",
            videoRelativePath: fileURL.lastPathComponent,
            status: .failed
        )
        let second = try repository.create(
            title: "Second",
            videoRelativePath: fileURL.lastPathComponent,
            status: .complete
        )

        try await repository.delete(first)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try repository.fetchAll().count == 1)

        try await repository.delete(second)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try repository.fetchAll().isEmpty)
    }
}
