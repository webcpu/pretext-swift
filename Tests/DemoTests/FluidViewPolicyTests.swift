import XCTest
@testable import Demo

final class FluidViewPolicyTests: XCTestCase {
    func testFluidUsesSixtyHertzTimelineWhileInteracting() {
        XCTAssertEqual(
            fluidTimelineMinimumInterval(isInteracting: true),
            1.0 / 60.0,
            accuracy: 0.000_001
        )
    }

    func testFluidUsesSixtyHertzTimelineWhileNotInteractingLikeWebParity() {
        XCTAssertEqual(
            fluidTimelineMinimumInterval(isInteracting: false),
            1.0 / 60.0,
            accuracy: 0.000_001
        )
    }

    func testMacOSHoverEndDoesNotClearPointerDuringActiveDrag() {
        let state = FluidInteractionState(
            pointerLocation: CGPoint(x: 120, y: 80),
            isDragActive: true
        )

        let next = fluidInteractionState(
            state,
            applying: .hoverChanged(nil),
            platform: .macOS
        )

        XCTAssertEqual(next.pointerLocation, CGPoint(x: 120, y: 80))
        XCTAssertTrue(next.isDragActive)
    }

    func testMacOSHoverUpdatesAreIgnoredWhileDragIsActive() {
        let state = FluidInteractionState(
            pointerLocation: CGPoint(x: 120, y: 80),
            isDragActive: true
        )

        let next = fluidInteractionState(
            state,
            applying: .hoverChanged(CGPoint(x: 40, y: 20)),
            platform: .macOS
        )

        XCTAssertEqual(next.pointerLocation, CGPoint(x: 120, y: 80))
        XCTAssertTrue(next.isDragActive)
    }

    func testDragEndClearsPointerAndDragState() {
        let state = FluidInteractionState(
            pointerLocation: CGPoint(x: 120, y: 80),
            isDragActive: true
        )

        let next = fluidInteractionState(
            state,
            applying: .dragEnded,
            platform: .macOS
        )

        XCTAssertNil(next.pointerLocation)
        XCTAssertFalse(next.isDragActive)
    }
}
