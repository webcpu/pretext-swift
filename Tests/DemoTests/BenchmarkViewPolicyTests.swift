import XCTest
@testable import BenchmarkSupport

@MainActor
final class BenchmarkViewPolicyTests: XCTestCase {
    func testAutoRunOnlyHappensOncePerSession() {
        BenchmarkAutoRunPolicy.resetForTests()
        XCTAssertTrue(BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: false))
        XCTAssertFalse(BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: false))
    }

    func testCLINeverAutoRuns() {
        BenchmarkAutoRunPolicy.resetForTests()
        XCTAssertFalse(BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: true))
        XCTAssertTrue(BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: false))
    }
}
