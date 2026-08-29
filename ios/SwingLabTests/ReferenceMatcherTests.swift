import XCTest
@testable import SwingLab

final class ReferenceMatcherTests: XCTestCase {
    func testCompatibilityPrefersMatchingViewHandednessAndClub() {
        let descriptor = ReferenceSwingDescriptor(
            id: "best-self",
            displayName: "Best driver",
            golferName: "You",
            sourceKind: .bestSelf,
            videoRelativePath: "best.mov",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: nil,
            attribution: "Your saved swing",
            sourceURL: nil,
            licenseURL: nil,
            allowedUse: .privateAnalysisOnly,
            rightsStatus: .unverified,
            analysisJSON: "{}"
        )

        XCTAssertEqual(
            ReferenceMatcher.compatibilityScore(
                reference: descriptor,
                view: .downTheLine,
                handedness: .right,
                club: .driver
            ),
            10
        )
        XCTAssertEqual(
            ReferenceMatcher.compatibilityScore(
                reference: descriptor,
                view: .faceOn,
                handedness: .left,
                club: .wedge
            ),
            0
        )
    }

    func testAlignedTimePreservesFractionBetweenNamedEvents() {
        let user = SwingEventTimestamps(
            addressSeconds: 10,
            topSeconds: 12,
            impactSeconds: 13,
            finishSeconds: 15,
            confidence: 1
        )
        let reference = SwingEventTimestamps(
            addressSeconds: 20,
            topSeconds: 24,
            impactSeconds: 26,
            finishSeconds: 30,
            confidence: 1
        )

        XCTAssertEqual(
            ReferenceMatcher.alignedTime(
                userTime: 12.5,
                userEvents: user,
                referenceEvents: reference
            ),
            25,
            accuracy: 0.000_1
        )
    }

    func testDistributionReadinessRequiresCompleteVerifiedWebProvenance() {
        var descriptor = ReferenceSwingDescriptor(
            id: "licensed-reference",
            displayName: "Instructor driver",
            golferName: "Instructor",
            sourceKind: .instructor,
            videoRelativePath: "instructor.mov",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: "Commercial license",
            attribution: "Provided by Example Golf",
            sourceURL: URL(string: "https://example.com/source"),
            licenseURL: URL(string: "https://example.com/license"),
            allowedUse: .distributionAllowed,
            rightsStatus: .verified,
            analysisJSON: "{}"
        )

        XCTAssertTrue(descriptor.isDistributionReady)

        descriptor.attribution = "   "
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.attribution = "Provided by Example Golf"
        descriptor.rightsStatus = .unverified
        XCTAssertFalse(descriptor.isDistributionReady)
    }

    func testLocalReferenceCanNeverBecomeDistributionReadyFromLabels() {
        let descriptor = ReferenceSwingDescriptor(
            id: "local-reference",
            displayName: "Famous golfer",
            golferName: "Famous golfer",
            sourceKind: .userImported,
            videoRelativePath: "reference.mov",
            cameraView: .faceOn,
            handedness: .right,
            club: .driver,
            licenseName: "Looks licensed",
            attribution: "A label entered by the user",
            sourceURL: URL(string: "https://example.com/source"),
            licenseURL: URL(string: "https://example.com/license"),
            allowedUse: .distributionAllowed,
            rightsStatus: .verified,
            analysisJSON: "{}"
        )

        XCTAssertFalse(descriptor.isDistributionReady)
    }

    func testDescriptorFactoryClassifiesLegacyNilAsBestSelf() {
        let session = SwingSession(
            title: "Legacy driver",
            videoRelativePath: "legacy.mov",
            status: .complete,
            analysisJSON: "{}"
        )

        XCTAssertEqual(session.sessionOrigin, .personal)
        XCTAssertEqual(
            ReferenceSwingDescriptorFactory.make(from: session)?.sourceKind,
            .bestSelf
        )
    }

    func testDescriptorFactoryFailsClosedForMalformedExplicitOrigin() {
        let session = SwingSession(
            title: "Malformed",
            videoRelativePath: "malformed.mov",
            status: .complete,
            analysisJSON: "{}"
        )
        session.origin = "  "

        XCTAssertEqual(session.sessionOrigin, .unknown)
        XCTAssertFalse(session.isPersonalSwing)
        XCTAssertNil(ReferenceSwingDescriptorFactory.make(from: session))
    }

    func testBundledCatalogAcceptsCompleteDistributionManifest() throws {
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [validBundledReference()]
        ))

        let entries = try BundledReferenceCatalog.validatedEntries(from: data)

        XCTAssertEqual(entries.map(\.id), ["licensed-driver"])
        XCTAssertTrue(entries[0].descriptor.isDistributionReady)
    }

    func testBundledCatalogRejectsUnverifiedRights() throws {
        var entry = validBundledReference()
        entry.rightsStatus = .unverified
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [entry]
        ))

        XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: data)) {
            XCTAssertEqual(
                $0 as? BundledReferenceCatalogError,
                .invalidRights("licensed-driver")
            )
        }
    }

    func testBundledCatalogRejectsDuplicateIDs() throws {
        let entry = validBundledReference()
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [entry, entry]
        ))

        XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: data)) {
            XCTAssertEqual(
                $0 as? BundledReferenceCatalogError,
                .duplicateID("licensed-driver")
            )
        }
    }

    func testBundledCatalogRejectsUnsafeResourcePath() throws {
        var entry = validBundledReference()
        entry.videoRelativePath = "../private.mov"
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [entry]
        ))

        XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: data)) {
            XCTAssertEqual(
                $0 as? BundledReferenceCatalogError,
                .unsafeResourcePath("../private.mov")
            )
        }
    }

    func testBundledCatalogRejectsBlankID() throws {
        let entry = validBundledReference(id: " ")
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [entry]
        ))

        XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: data)) {
            XCTAssertEqual(
                $0 as? BundledReferenceCatalogError,
                .invalidRights(" ")
            )
        }
    }

    func testBundledCatalogRejectsInvalidAnalysisTimeline() {
        let validTrack = PoseTrack(
            selectedRangeStartSeconds: 1,
            selectedRangeDurationSeconds: 4,
            nominalSampleRate: 15,
            orientation: .up,
            frames: [
                PoseFrame(timestampSeconds: 1.5, joints: [:]),
                PoseFrame(timestampSeconds: 4.5, joints: [:]),
            ]
        )
        let validEvents = SwingEventTimestamps(
            addressSeconds: 1.5,
            topSeconds: 2.5,
            impactSeconds: 3,
            finishSeconds: 4.5,
            confidence: 0.9
        )

        XCTAssertTrue(BundledReferenceCatalog.analysisTimelineIsValid(
            track: validTrack,
            events: validEvents,
            videoDuration: 8,
            tolerance: 1.0 / 30
        ))

        var invalidDurationTrack = validTrack
        invalidDurationTrack.selectedRangeDurationSeconds = -1
        XCTAssertFalse(BundledReferenceCatalog.analysisTimelineIsValid(
            track: invalidDurationTrack,
            events: validEvents,
            videoDuration: 8,
            tolerance: 1.0 / 30
        ))

        let unorderedEvents = SwingEventTimestamps(
            addressSeconds: 1.5,
            topSeconds: 3.2,
            impactSeconds: 3,
            finishSeconds: 4.5,
            confidence: 0.9
        )
        XCTAssertFalse(BundledReferenceCatalog.analysisTimelineIsValid(
            track: validTrack,
            events: unorderedEvents,
            videoDuration: 8,
            tolerance: 1.0 / 30
        ))

        var outsideEvents = validEvents
        outsideEvents.finishSeconds = 5.5
        XCTAssertFalse(BundledReferenceCatalog.analysisTimelineIsValid(
            track: validTrack,
            events: outsideEvents,
            videoDuration: 8,
            tolerance: 1.0 / 30
        ))

        var emptyTrack = validTrack
        emptyTrack.frames = []
        XCTAssertFalse(BundledReferenceCatalog.analysisTimelineIsValid(
            track: emptyTrack,
            events: validEvents,
            videoDuration: 8,
            tolerance: 1.0 / 30
        ))
    }

    private func validBundledReference(
        id: String = "licensed-driver"
    ) -> BundledReferenceManifestEntry {
        BundledReferenceManifestEntry(
            id: id,
            displayName: "Licensed driver",
            golferName: "Reference golfer",
            sourceKind: .instructor,
            videoRelativePath: "References/driver.mov",
            analysisRelativePath: "References/driver.json",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: "Commercial video license",
            attribution: "Example Golf Studio",
            sourceURL: URL(string: "https://example.com/source")!,
            licenseURL: URL(string: "https://example.com/license")!,
            allowedUse: .distributionAllowed,
            rightsStatus: .verified
        )
    }
}
