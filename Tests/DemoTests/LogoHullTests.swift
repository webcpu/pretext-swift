import XCTest
@testable import Demo

final class LogoHullTests: XCTestCase {
    func testBundledLogoResourcesUseRealPathMarkup() throws {
        for resourceName in ["openai-symbol", "claude-symbol"] {
            let contents = try String(
                contentsOf: resourceURL(named: resourceName),
                encoding: .utf8
            )

            XCTAssertTrue(contents.contains("<path"))
            XCTAssertFalse(contents.contains("<polygon"))
        }
    }

    func testBundledSVGsProduceHulls() {
        let openai = loadBundledLogo(named: "openai-symbol", layoutSmoothRadius: 6, hitSmoothRadius: 3)
        let claude = loadBundledLogo(named: "claude-symbol", layoutSmoothRadius: 6, hitSmoothRadius: 5)

        XCTAssertFalse(openai.layoutHull.isEmpty)
        XCTAssertFalse(claude.layoutHull.isEmpty)
    }
}

private func resourceURL(named resourceName: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Demo/Resources/\(resourceName).svg")
}
