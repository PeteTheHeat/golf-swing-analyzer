import AVFoundation
import XCTest
@testable import SwingLab

final class TrimSelectionTests: XCTestCase {
    func testDefaultSelectionIsCappedAtMaximumDuration() {
        let selection = TrimSelection(
            assetDuration: 42,
            frameDuration: 1 / 30
        )

        XCTAssertEqual(selection.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 12, accuracy: 0.000_001)
        XCTAssertEqual(selection.duration, 12, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testStartHandleCannotCrossMinimumDuration() {
        var selection = TrimSelection(
            assetDuration: 20,
            frameDuration: 0.1,
            minimumDuration: 1,
            maximumDuration: 8,
            start: 2,
            end: 6
        )

        selection.setStart(10)

        XCTAssertEqual(selection.start, 5, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 6, accuracy: 0.000_001)
        XCTAssertEqual(selection.duration, 1, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testStartHandleCannotMakeSelectionLongerThanMaximum() {
        var selection = TrimSelection(
            assetDuration: 30,
            frameDuration: 0.1,
            minimumDuration: 1,
            maximumDuration: 5,
            start: 10,
            end: 14
        )

        selection.setStart(0)

        XCTAssertEqual(selection.start, 9, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 14, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testEndHandlePreservesDurationBounds() {
        var selection = TrimSelection(
            assetDuration: 30,
            frameDuration: 0.1,
            minimumDuration: 1,
            maximumDuration: 5,
            start: 10,
            end: 14
        )

        selection.setEnd(30)
        XCTAssertEqual(selection.end, 15, accuracy: 0.000_001)

        selection.setEnd(10)
        XCTAssertEqual(selection.end, 11, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testShortAssetUsesWholeAssetAsOnlyValidSelection() {
        var selection = TrimSelection(
            assetDuration: 0.6,
            frameDuration: 1 / 30,
            minimumDuration: 1,
            maximumDuration: 12
        )

        selection.setStart(0.4)
        selection.setEnd(0.2)

        XCTAssertEqual(selection.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(selection.minimumDuration, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(selection.maximumDuration, 0.6, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testSelectionSnapsToVideoFrames() {
        var selection = TrimSelection(
            assetDuration: 10,
            frameDuration: 0.04,
            minimumDuration: 0.4,
            maximumDuration: 4,
            start: 1.01,
            end: 3.03
        )

        XCTAssertEqual(selection.start, 1, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 3.04, accuracy: 0.000_001)

        selection.setStart(1.07)
        selection.setEnd(3.09)

        XCTAssertEqual(selection.start, 1.08, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 3.08, accuracy: 0.000_001)
    }

    func testThumbnailTimesStayInsideTheSelectedSwingRange() {
        let times = ThumbnailTimeSampler.seconds(
            videoDuration: 100,
            frameDuration: 1 / 30,
            rangeStart: 35.5,
            rangeDuration: 4,
            count: 3
        )

        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 35.5, accuracy: 0.000_001)
        XCTAssertEqual(times[1], 37.483_333, accuracy: 0.000_001)
        XCTAssertEqual(times[2], 39.466_667, accuracy: 0.000_001)
    }

    func testThumbnailTimesUseFullVideoWhenRangeMetadataIsInvalid() {
        let times = ThumbnailTimeSampler.seconds(
            videoDuration: 10,
            frameDuration: 0.1,
            rangeStart: .nan,
            rangeDuration: -1,
            count: 3
        )

        XCTAssertEqual(times, [0, 4.95, 9.9])
        XCTAssertTrue(ThumbnailTimeSampler.seconds(
            videoDuration: 10,
            frameDuration: 0.1,
            count: 0
        ).isEmpty)
    }

    func testSingleThumbnailUsesTheSelectedRangeMidpoint() {
        let times = ThumbnailTimeSampler.seconds(
            videoDuration: 10,
            frameDuration: 0.1,
            rangeStart: 2,
            rangeDuration: 4,
            count: 1
        )

        XCTAssertEqual(times, [3.95])
    }

    func testThumbnailTimesClampAnOverhangingRangeToTheVideo() {
        let times = ThumbnailTimeSampler.seconds(
            videoDuration: 10,
            frameDuration: 0.1,
            rangeStart: 9.8,
            rangeDuration: 2,
            count: 3
        )

        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 9.8, accuracy: 0.000_001)
        XCTAssertEqual(times[1], 9.85, accuracy: 0.000_001)
        XCTAssertEqual(times[2], 9.9, accuracy: 0.000_001)
        XCTAssertTrue(times.allSatisfy { $0 >= 9.8 && $0 < 10 })
    }

    func testReviewTimelineAccessibilityStepsByOneFrameAndClamps() throws {
        XCTAssertEqual(
            try XCTUnwrap(ReviewTimelineAccessibility.adjustedTime(
                currentTime: 2,
                frameDuration: 0.04,
                direction: 1,
                rangeStart: 1,
                rangeEnd: 3
            )),
            2.04,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(ReviewTimelineAccessibility.adjustedTime(
                currentTime: 1,
                frameDuration: 0.04,
                direction: -1,
                rangeStart: 1,
                rangeEnd: 3
            )),
            1,
            accuracy: 0.000_001
        )
        XCTAssertNil(ReviewTimelineAccessibility.adjustedTime(
            currentTime: 2,
            frameDuration: 0.04,
            direction: 0,
            rangeStart: 1,
            rangeEnd: 3
        ))
    }

    func testMoveRangePreservesDurationAndClampsAtAssetBoundary() {
        var selection = TrimSelection(
            assetDuration: 10,
            frameDuration: 0.1,
            minimumDuration: 1,
            maximumDuration: 5,
            start: 2,
            end: 5
        )

        selection.moveRange(toStart: 9)

        XCTAssertEqual(selection.start, 7, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 10, accuracy: 0.000_001)
        XCTAssertEqual(selection.duration, 3, accuracy: 0.000_001)

        selection.moveRange(by: -20)

        XCTAssertEqual(selection.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 3, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testSetRangeOrdersHandlesAndEnforcesMaximum() {
        var selection = TrimSelection(
            assetDuration: 30,
            frameDuration: 0.1,
            minimumDuration: 1,
            maximumDuration: 6
        )

        selection.setRange(start: 20, end: 4)

        XCTAssertEqual(selection.start, 4, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 10, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testZeroDurationAssetIsExplicitlyInvalid() {
        let selection = TrimSelection(
            assetDuration: .nan,
            frameDuration: 0,
            minimumDuration: -1,
            maximumDuration: .infinity
        )

        XCTAssertEqual(selection.assetDuration, 0)
        XCTAssertEqual(selection.start, 0)
        XCTAssertEqual(selection.end, 0)
        XCTAssertFalse(selection.isValid)
    }

    func testPersonalSaveTargetIsValidWithoutReferenceMetadata() {
        XCTAssertTrue(AnalysisSaveTarget.personalSwing.isValidForAnalysis)
    }

    func testPrivateReferenceRequiresNonblankName() {
        XCTAssertFalse(
            AnalysisSaveTarget.privateReference(
                PrivateReferenceInput(displayName: " \n\t ")
            ).isValidForAnalysis
        )
        XCTAssertTrue(
            AnalysisSaveTarget.privateReference(
                PrivateReferenceInput(displayName: "Coach model")
            ).isValidForAnalysis
        )
    }

    func testDetectedCandidateCreatesFrameSnappedTrimSelection() {
        let video = ImportedVideo(
            fileURL: URL(fileURLWithPath: "/tmp/discovery-test.mov"),
            displayName: "Discovery test",
            duration: CMTime(seconds: 30, preferredTimescale: 600),
            naturalSize: CGSize(width: 1920, height: 1080),
            nominalFrameRate: 25,
            frameDuration: CMTime(value: 1, timescale: 25),
            fileSizeBytes: 1
        )
        let candidate = SwingDiscoveryCandidate(
            id: 6.2,
            startSeconds: 4.13,
            endSeconds: 8.17,
            confidence: 0.81
        )

        let selection = candidate.trimSelection(for: video)

        XCTAssertEqual(selection.start, 4.12, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 8.16, accuracy: 0.000_001)
        XCTAssertEqual(selection.duration, 4.04, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    func testDetectedCandidateIsBoundedByTrimInvariants() {
        let video = ImportedVideo(
            fileURL: URL(fileURLWithPath: "/tmp/discovery-bounds.mov"),
            displayName: "Discovery bounds",
            duration: CMTime(seconds: 14, preferredTimescale: 600),
            naturalSize: CGSize(width: 1080, height: 1920),
            nominalFrameRate: 30,
            frameDuration: CMTime(value: 1, timescale: 30),
            fileSizeBytes: 1
        )
        let candidate = SwingDiscoveryCandidate(
            id: 5,
            startSeconds: -4,
            endSeconds: 80,
            confidence: 2
        )

        let selection = candidate.trimSelection(for: video)

        XCTAssertEqual(candidate.startSeconds, 0)
        XCTAssertEqual(candidate.confidence, 1)
        XCTAssertEqual(selection.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(selection.end, 12, accuracy: 0.000_001)
        XCTAssertTrue(selection.isValid)
    }

    @MainActor
    func testAutomaticDiscoveryRunsForEveryViableImportedVideo() {
        XCTAssertTrue(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: 1))
        XCTAssertTrue(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: 10))
        XCTAssertTrue(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: 12))
        XCTAssertTrue(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: 12.01))
        XCTAssertFalse(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: 0.99))
        XCTAssertFalse(ImportTrimView.shouldAutomaticallyDiscover(videoDuration: .nan))
    }

    @MainActor
    func testClipPositionRangePreservesSubsecondSlack() {
        let range = TrimSwingView.clipPositionRange(maximumStart: 0.4)

        XCTAssertEqual(range.lowerBound, 0, accuracy: 0.000_001)
        XCTAssertEqual(range.upperBound, 0.4, accuracy: 0.000_001)
    }

    @MainActor
    func testClipPositionRangeRemainsNonemptyWhenThereIsNoSlack() {
        let range = TrimSwingView.clipPositionRange(maximumStart: 0)

        XCTAssertEqual(range.lowerBound, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(range.upperBound, 0)
        XCTAssertLessThan(range.upperBound, 0.001)
    }
}
