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
            rightsBasis: .unknown,
            verificationRecordID: nil,
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

    func testPublicLicenseRequiresCompleteVerifiedWebProvenance() {
        var descriptor = publicLicenseDescriptor()

        XCTAssertTrue(descriptor.isDistributionReady)

        descriptor.attribution = "   "
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.attribution = "Provided by Example Golf"
        descriptor.rightsStatus = .unverified
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.rightsStatus = .verified
        descriptor.licenseURL = nil
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.licenseURL = URL(string: "file:///private/license.pdf")
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.licenseURL = URL(string: "https://example.com/license")
        descriptor.sourceURL = nil
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.sourceURL = URL(string: "https://example.com/source")
        descriptor.verificationRecordID = "RC-REF-2026-0001"
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.verificationRecordID = nil
        descriptor.rightsBasis = .unknown
        XCTAssertFalse(descriptor.isDistributionReady)
    }

    func testSignedReleaseRequiresOpaqueRecordButNoPublicLicenseURL() {
        var descriptor = signedReleaseDescriptor()

        XCTAssertTrue(descriptor.isDistributionReady)

        descriptor.verificationRecordID = nil
        XCTAssertFalse(descriptor.isDistributionReady)

        for unsafeRecord in [
            "RC-REF-2026-0001 ",
            "rc-ref-2026-0001",
            "https://example.com/release",
            "../private-contract.pdf",
            "RC-REF-SECRET@example.com",
            "RC-REF-2026-Ä001",
            "RC-REF-CONTRACT-0001",
            "RC-REF-2026-NDA1",
            "RC-REF-2026-001",
            "RC-REF-2026-00001",
        ] {
            descriptor.verificationRecordID = unsafeRecord
            XCTAssertFalse(
                descriptor.isDistributionReady,
                "Accepted unsafe verification record: \(unsafeRecord)"
            )
        }

        descriptor.verificationRecordID = "RC-REF-2026-0001"
        descriptor.licenseURL = URL(string: "https://example.com/private-release")
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.licenseURL = nil
        descriptor.sourceURL = URL(fileURLWithPath: "/private/source")
        XCTAssertFalse(descriptor.isDistributionReady)

        descriptor.sourceURL = nil
        XCTAssertTrue(descriptor.isDistributionReady)
    }

    func testBothRightsBasesRequireAllSharedDistributionProof() {
        for baseline in [publicLicenseDescriptor(), signedReleaseDescriptor()] {
            var descriptor = baseline
            descriptor.allowedUse = .privateAnalysisOnly
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.rightsStatus = .unknown
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.sourceKind = .bestSelf
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.displayName = "  "
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.golferName = nil
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.licenseName = "\n"
            XCTAssertFalse(descriptor.isDistributionReady)

            descriptor = baseline
            descriptor.attribution = ""
            XCTAssertFalse(descriptor.isDistributionReady)
        }
    }

    func testLegacyPrivateDescriptorDecodesWithoutElevatingRights() throws {
        let original = ReferenceSwingDescriptor(
            id: "legacy-private",
            displayName: "Old saved swing",
            golferName: "You",
            sourceKind: .bestSelf,
            videoRelativePath: "old.mov",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: nil,
            attribution: "Your saved swing",
            sourceURL: nil,
            licenseURL: nil,
            rightsBasis: .unknown,
            verificationRecordID: nil,
            allowedUse: .privateAnalysisOnly,
            rightsStatus: .unverified,
            analysisJSON: "{}"
        )
        let legacyData = try removingKeys(
            ["rightsBasis", "verificationRecordID"],
            from: JSONEncoder().encode(original)
        )

        let decoded = try JSONDecoder().decode(
            ReferenceSwingDescriptor.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.rightsBasis, .unknown)
        XCTAssertNil(decoded.verificationRecordID)
        XCTAssertTrue(decoded.isPrivateOnly)
        XCTAssertFalse(decoded.isDistributionReady)
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
            rightsBasis: .publicLicense,
            verificationRecordID: nil,
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

    func testBundledCatalogAcceptsVerifiedSignedReleaseRecord() throws {
        let data = try JSONEncoder().encode(BundledReferenceManifest(
            schemaVersion: 1,
            references: [validSignedReleaseReference()]
        ))

        let entries = try BundledReferenceCatalog.validatedEntries(from: data)

        XCTAssertEqual(entries.map(\.id), ["released-driver"])
        XCTAssertEqual(entries[0].rightsBasis, .signedRelease)
        XCTAssertEqual(entries[0].verificationRecordID, "RC-REF-2026-0001")
        XCTAssertNil(entries[0].licenseURL)
        XCTAssertTrue(entries[0].descriptor.isDistributionReady)
    }

    func testBundledCatalogRejectsLegacyManifestWithoutExplicitRightsBasis() throws {
        let manifest = BundledReferenceManifest(
            schemaVersion: 1,
            references: [validBundledReference()]
        )
        let encoded = try JSONEncoder().encode(manifest)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var references = try XCTUnwrap(root["references"] as? [[String: Any]])
        references[0].removeValue(forKey: "rightsBasis")
        root["references"] = references
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: legacyData)) {
            XCTAssertEqual(
                $0 as? BundledReferenceCatalogError,
                .invalidRights("licensed-driver")
            )
        }
    }

    func testBundledPublicLicenseStillRequiresPublicLicenseURL() throws {
        var entry = validBundledReference()
        entry.licenseURL = nil
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

    func testBundledSignedReleaseRejectsMissingOrMalformedVerificationRecord() throws {
        for recordID in [nil, "release.pdf", "RC-REF-private-note"] as [String?] {
            var entry = validSignedReleaseReference()
            entry.verificationRecordID = recordID
            let data = try JSONEncoder().encode(BundledReferenceManifest(
                schemaVersion: 1,
                references: [entry]
            ))

            XCTAssertThrowsError(try BundledReferenceCatalog.validatedEntries(from: data)) {
                XCTAssertEqual(
                    $0 as? BundledReferenceCatalogError,
                    .invalidRights("released-driver")
                )
            }
        }
    }

    func testBundledReferenceMetadataRequiresKnownClubToMatch() {
        let entry = validBundledReference()

        XCTAssertTrue(BundledReferenceCatalog.analysisMetadataMatches(
            SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                club: .driver
            ),
            entry: entry
        ))
        XCTAssertTrue(BundledReferenceCatalog.analysisMetadataMatches(
            SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                club: .unknown
            ),
            entry: entry
        ))
        XCTAssertFalse(BundledReferenceCatalog.analysisMetadataMatches(
            SwingAnalysisContext(
                cameraView: .downTheLine,
                handedness: .right,
                club: .wedge
            ),
            entry: entry
        ))
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
            rightsBasis: .publicLicense,
            verificationRecordID: nil,
            allowedUse: .distributionAllowed,
            rightsStatus: .verified
        )
    }

    private func validSignedReleaseReference() -> BundledReferenceManifestEntry {
        BundledReferenceManifestEntry(
            id: "released-driver",
            displayName: "Released professional driver",
            golferName: "Reference golfer",
            sourceKind: .licensedProfessional,
            videoRelativePath: "References/released-driver.mov",
            analysisRelativePath: "References/released-driver.json",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: "Signed commercial footage and likeness release",
            attribution: "Reference golfer",
            sourceURL: nil,
            licenseURL: nil,
            rightsBasis: .signedRelease,
            verificationRecordID: "RC-REF-2026-0001",
            allowedUse: .distributionAllowed,
            rightsStatus: .verified
        )
    }

    private func signedReleaseDescriptor() -> ReferenceSwingDescriptor {
        ReferenceSwingDescriptor(
            id: "released-reference",
            displayName: "Professional driver",
            golferName: "Reference golfer",
            sourceKind: .licensedProfessional,
            videoRelativePath: "released.mov",
            cameraView: .downTheLine,
            handedness: .right,
            club: .driver,
            licenseName: "Signed commercial footage and likeness release",
            attribution: "Reference golfer",
            sourceURL: nil,
            licenseURL: nil,
            rightsBasis: .signedRelease,
            verificationRecordID: "RC-REF-2026-0001",
            allowedUse: .distributionAllowed,
            rightsStatus: .verified,
            analysisJSON: "{}"
        )
    }

    private func publicLicenseDescriptor() -> ReferenceSwingDescriptor {
        ReferenceSwingDescriptor(
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
            rightsBasis: .publicLicense,
            verificationRecordID: nil,
            allowedUse: .distributionAllowed,
            rightsStatus: .verified,
            analysisJSON: "{}"
        )
    }

    private func removingKeys(_ keys: [String], from data: Data) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for key in keys {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
