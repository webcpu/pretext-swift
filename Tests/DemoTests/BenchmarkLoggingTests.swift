import XCTest
@testable import BenchmarkSupport

final class BenchmarkLoggingTests: XCTestCase {
    func testBenchmarkProfileLogURLLivesInTemporaryDirectory() {
        let url = benchmarkProfileLogURL(fileManager: .default)

        XCTAssertEqual(url.lastPathComponent, "pretext-profile.log")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, FileManager.default.temporaryDirectory.standardizedFileURL)
    }

    func testOpenBenchmarkProfileLogHandleCreatesWritableFile() throws {
        let fileManager = FileManager.default
        let url = benchmarkProfileLogURL(fileManager: fileManager)

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let handle = try openBenchmarkProfileLogHandle(fileManager: fileManager)
        handle.closeFile()

        XCTAssertTrue(fileManager.fileExists(atPath: url.path))
    }
}
