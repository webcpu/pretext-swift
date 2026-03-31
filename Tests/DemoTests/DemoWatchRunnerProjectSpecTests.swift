import Foundation
import XCTest

final class DemoWatchRunnerProjectSpecTests: XCTestCase {
    func testGeneratedRunnerProjectUsesSharedWatchScheme() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specURL = repoRoot.appendingPathComponent("Xcode/DemoWatchRunner/project.yml")

        _ = try runCommand(
            [
                "xcodegen",
                "generate",
                "--spec", specURL.path,
            ],
            currentDirectory: repoRoot
        )

        let projectURL = repoRoot.appendingPathComponent("Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj")
        let schemeURL = projectURL.appendingPathComponent("xcshareddata/xcschemes/DemoWatchRunner.xcscheme")

        guard FileManager.default.fileExists(atPath: schemeURL.path) else {
            XCTFail("Expected a shared DemoWatchRunner scheme to be generated.")
            return
        }

        let schemeContents = try String(contentsOf: schemeURL, encoding: .utf8)
        XCTAssertTrue(
            schemeContents.contains("<LaunchAction\n      buildConfiguration = \"Release\""),
            "Expected DemoWatchRunner to launch in Release.\n\(schemeContents)"
        )
        XCTAssertTrue(
            schemeContents.contains("<ProfileAction\n      buildConfiguration = \"Release\""),
            "Expected DemoWatchRunner to profile in Release.\n\(schemeContents)"
        )

        let buildSettings = try runCommand(
            [
                "xcodebuild",
                "-project", projectURL.path,
                "-scheme", "DemoWatchRunner",
                "-showBuildSettings",
            ],
            currentDirectory: repoRoot
        )

        XCTAssertTrue(
            buildSettings.contains("PLATFORM_NAME = watchos"),
            "Expected DemoWatchRunner to target watchOS.\n\(buildSettings)"
        )
        XCTAssertTrue(
            buildSettings.contains("WATCHOS_DEPLOYMENT_TARGET = 11.0"),
            "Expected DemoWatchRunner to target watchOS.\n\(buildSettings)"
        )
        XCTAssertTrue(
            buildSettings.contains("LD_RUNPATH_SEARCH_PATHS =  @executable_path/Frameworks"),
            "Expected DemoWatchRunner to load embedded frameworks from the app bundle.\n\(buildSettings)"
        )

        let rakefileURL = repoRoot.appendingPathComponent("Rakefile")
        let rakefileContents = try String(contentsOf: rakefileURL, encoding: .utf8)
        XCTAssertTrue(
            rakefileContents.contains(#"xcodebuild -project Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj -scheme DemoWatchRunner -configuration Release"#),
            "Expected build_watchos_demo to build the watch runner in Release.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains("task :run_watchos_demo do"),
            "Expected a run_watchos_demo task for physical watch launches.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains(#"xcodebuild -project Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj -scheme DemoWatchRunner -configuration Release -destination 'id=#{device.fetch(:udid)}' build"#),
            "Expected run_watchos_demo to build the watch runner in Release for a physical watch.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains("xcrun devicectl device install app --device"),
            "Expected run_watchos_demo to install the built watch app.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains("xcrun devicectl device process launch --device"),
            "Expected run_watchos_demo to launch the installed watch app.\n\(rakefileContents)"
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
