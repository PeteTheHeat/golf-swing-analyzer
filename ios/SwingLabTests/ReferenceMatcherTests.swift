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
}
