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
