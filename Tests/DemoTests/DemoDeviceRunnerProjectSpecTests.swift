import Foundation
import XCTest

final class DemoDeviceRunnerProjectSpecTests: XCTestCase {
    func testGeneratedRunnerProjectUsesReleaseDefaults() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specURL = repoRoot.appendingPathComponent("Xcode/DemoDeviceRunner/project.yml")

        _ = try runCommand(
            [
                "xcodegen",
                "generate",
                "--spec", specURL.path,
            ],
            currentDirectory: repoRoot
        )

        let projectURL = repoRoot.appendingPathComponent("Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj")
        let schemeURL = projectURL.appendingPathComponent("xcshareddata/xcschemes/DemoDeviceRunner.xcscheme")

        guard FileManager.default.fileExists(atPath: schemeURL.path) else {
            XCTFail("Expected a shared DemoDeviceRunner scheme to be generated.")
            return
        }

        let schemeXML = try String(contentsOf: schemeURL, encoding: .utf8)
        for action in ["LaunchAction", "TestAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"] {
            XCTAssertNotNil(
                schemeXML.range(
                    of: #"<\#(action)\b[^>]*buildConfiguration\s*=\s*"Release""#,
                    options: .regularExpression
                ),
                "\(action) should use Release."
            )
        }

        let buildSettings = try runCommand(
            [
                "xcodebuild",
                "-project", projectURL.path,
                "-scheme", "DemoDeviceRunner",
                "-showBuildSettings",
            ],
            currentDirectory: repoRoot
        )

        XCTAssertTrue(
            buildSettings.contains("CONFIGURATION = Release"),
            "Expected xcodebuild to default DemoDeviceRunner to Release.\n\(buildSettings)"
        )
    }
}

private func runCommand(_ arguments: [String], currentDirectory: URL) throws -> String {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        + String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    guard process.terminationStatus == 0 else {
        throw CommandError(arguments: arguments, output: output, status: process.terminationStatus)
    }

    return output
}

private struct CommandError: Error, CustomStringConvertible {
    let arguments: [String]
    let output: String
    let status: Int32

    var description: String {
        """
        Command failed (\(status)): \(arguments.joined(separator: " "))
        \(output)
        """
    }
}
