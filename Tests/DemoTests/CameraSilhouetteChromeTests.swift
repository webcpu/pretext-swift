import XCTest
@testable import Demo

final class CameraSilhouetteChromeTests: XCTestCase {
    func testCameraSilhouetteUsesSituationalAwarenessPaperAndInk() {
        XCTAssertEqual(CameraSilhouettePalette.paperRGB, SituationalAwarenessPalette.paperRGB)
        XCTAssertEqual(CameraSilhouettePalette.inkRGB, SituationalAwarenessPalette.inkRGB)
    }

    func testRunningNoPersonDoesNotShowBottomPanel() {
        XCTAssertNil(cameraSilhouetteOverlayPanel(for: .runningNoPerson))
    }

    func testPermissionDeniedStillShowsRecoveryPanel() {
        let panel = cameraSilhouetteOverlayPanel(for: .permissionDenied)

        XCTAssertEqual(panel?.title, "Turn Camera Access Back On")
        XCTAssertFalse(panel?.body.isEmpty ?? true)
    }
}
