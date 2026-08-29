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
}
