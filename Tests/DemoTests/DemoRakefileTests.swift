import Foundation
import XCTest

final class DemoRakefileTests: XCTestCase {
    func testDemoTaskDoesNotUseGlobalDerivedDataGlobForMacOSApp() throws {
        let repoRoot = try repositoryRoot()
        let rakefileURL = repoRoot.appendingPathComponent("Rakefile")
        let rakefileContents = try String(contentsOf: rakefileURL, encoding: .utf8)

        XCTAssertFalse(
            rakefileContents.contains(#"~/Library/Developer/Xcode/DerivedData/DemoMacRunner-*/Build/Products/Release/Demo.app"#),
            "Expected `rake demo` to launch the app built for the current worktree, not whichever Demo.app is newest in DerivedData.\n\(rakefileContents)"
        )
    }

    func testRakefileResolvesMacOSDemoAppFromBuildSettings() throws {
        let repoRoot = try repositoryRoot()
        let rubyScript = #"""
        require "rake"
        require "open3"

        module Open3
          class << self
            alias_method :original_capture2e, :capture2e

            def capture2e(*args)
              expected = [
                "xcodebuild",
                "-project", "Xcode/DemoMacRunner/DemoMacRunner.xcodeproj",
                "-scheme", "DemoMacRunner",
                "-configuration", "Release",
                "-showBuildSettings",
              ]

              if args == expected
                output = <<~SETTINGS
                    TARGET_BUILD_DIR = /tmp/current/Build/Products/Release
                    FULL_PRODUCT_NAME = Demo.app
                SETTINGS

                status = Object.new
                status.define_singleton_method(:success?) { true }
                return [output, status]
              end

              original_capture2e(*args)
            end
          end
        end

        Dir.chdir(ARGV.fetch(0)) do
          load "Rakefile"
          puts send(
            :xcode_built_product_path,
            project: "Xcode/DemoMacRunner/DemoMacRunner.xcodeproj",
            scheme: "DemoMacRunner",
            configuration: "Release"
          )
        end
        """#

        let output = try runCommand(
            [
                "ruby",
                "-e", rubyScript,
                repoRoot.path,
            ],
            currentDirectory: repoRoot
        )

        XCTAssertEqual(
            output.trimmingCharacters(in: .whitespacesAndNewlines),
            "/tmp/current/Build/Products/Release/Demo.app"
        )
    }

    func testDemoTaskWaitsForExistingMacOSAppToExitBeforeLaunchingFreshInstance() throws {
        let repoRoot = try repositoryRoot()
        let rubyScript = #"""
        require "json"
        require "fileutils"
        require "rake"
        require "tmpdir"

        Dir.chdir(ARGV.fetch(0)) do
          load "Rakefile"

          Dir.mktmpdir("demo-rakefile-tests") do |tmpdir|
            app_path = File.join(tmpdir, "Demo.app")
            FileUtils.mkdir_p(app_path)
            launched_commands = []
            system_commands = []

            define_singleton_method(:xcode_built_product_path) { |**| app_path }
            define_singleton_method(:sh) { |command| launched_commands << command }
            define_singleton_method(:system) do |command|
              system_commands << command
              false
            end

            Rake::Task[:build_macos_demo].clear
            Rake::Task[:build_macos_demo].enhance {}
            Rake::Task[:demo].reenable
            Rake::Task[:demo].invoke

            puts JSON.dump({
              commands: launched_commands,
              system_commands: system_commands,
              app_path: app_path,
            })
          end
        end
        """#

        let output = try runCommand(
            [
                "ruby",
                "-e", rubyScript,
                repoRoot.path,
            ],
            currentDirectory: repoRoot
        )

        let payload = try XCTUnwrap(output.data(using: .utf8))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        let commands = try XCTUnwrap(json["commands"] as? [String])
        let systemCommands = try XCTUnwrap(json["system_commands"] as? [String])
        let appPath = try XCTUnwrap(json["app_path"] as? String)
        let executablePath = "\(appPath)/Contents/MacOS/Demo"

        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(
            commands.first,
            "pkill -TERM -f \(executablePath.shellEscapedForTest) || true"
        )
        XCTAssertEqual(
            commands.last,
            "open -n \(appPath.shellEscapedForTest)"
        )
        XCTAssertEqual(
            systemCommands,
            ["pgrep -f \(executablePath.shellEscapedForTest) >/dev/null 2>&1"]
        )
    }
}

private func repositoryRoot() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
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

private extension String {
    var shellEscapedForTest: String {
        if rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "/._-"))) == nil {
            return self
        }

        return "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
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
