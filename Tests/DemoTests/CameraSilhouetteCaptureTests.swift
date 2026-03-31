import AVFoundation
import XCTest
@testable import Demo

final class CameraSilhouetteCaptureTests: XCTestCase {
    func testFrameGateDropsFramesInsideMinimumInterval() {
        let minimumInterval = 1.0 / 8.0

        XCTAssertTrue(
            cameraSilhouetteShouldProcessFrame(
                currentTimestamp: 0,
                lastProcessedTimestamp: nil,
                minimumInterval: minimumInterval
            )
        )
        XCTAssertFalse(
            cameraSilhouetteShouldProcessFrame(
                currentTimestamp: 0.04,
                lastProcessedTimestamp: 0,
                minimumInterval: minimumInterval
            )
        )
        XCTAssertTrue(
            cameraSilhouetteShouldProcessFrame(
                currentTimestamp: 0.13,
                lastProcessedTimestamp: 0,
                minimumInterval: minimumInterval
            )
        )
    }

    func testIOSCapturePolicyPrefersMirroredFrontPortraitFeed() {
        let policy = cameraSilhouetteCapturePolicy(for: .ios)

        XCTAssertTrue(policy.prefersFrontCamera)
        XCTAssertTrue(policy.usesPortraitOrientation)
        XCTAssertTrue(cameraSilhouetteShouldMirrorCapture(devicePosition: .front, platform: .ios))
        XCTAssertTrue(cameraSilhouetteShouldMirrorCapture(devicePosition: .unspecified, platform: .ios))
    }

    func testMacOSCapturePolicyUsesDefaultCameraAndNativeOrientation() {
        let policy = cameraSilhouetteCapturePolicy(for: .macOS)

        XCTAssertFalse(policy.prefersFrontCamera)
        XCTAssertFalse(policy.usesPortraitOrientation)
        XCTAssertTrue(cameraSilhouetteShouldMirrorCapture(devicePosition: .front, platform: .macOS))
        XCTAssertFalse(cameraSilhouetteShouldMirrorCapture(devicePosition: .unspecified, platform: .macOS))
    }
}
