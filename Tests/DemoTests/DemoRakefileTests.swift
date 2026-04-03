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
        require "shellwords"
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

    func testRakefileIncludesRunIOSDemoTaskForPhysicalDevices() throws {
        let repoRoot = try repositoryRoot()
        let rakefileURL = repoRoot.appendingPathComponent("Rakefile")
        let rakefileContents = try String(contentsOf: rakefileURL, encoding: .utf8)

        XCTAssertTrue(
            rakefileContents.contains("task :run_ios_demo do"),
            "Expected a run_ios_demo task for physical iPhone/iPad launches.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains(#"xcodegen generate --spec Xcode/DemoDeviceRunner/project.yml"#),
            "Expected run_ios_demo to generate the iOS runner project.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains(#"xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj -scheme DemoDeviceRunner -configuration Release -destination 'id=#{device.fetch(:udid)}' build"#),
            "Expected run_ios_demo to build the iOS runner in Release for a physical device.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains("xcrun devicectl device install app --device"),
            "Expected run_ios_demo to install the built iOS app.\n\(rakefileContents)"
        )
        XCTAssertTrue(
            rakefileContents.contains("xcrun devicectl device process launch --device"),
            "Expected run_ios_demo to launch the installed iOS app.\n\(rakefileContents)"
        )
    }

    func testRunIOSDemoInstallsAndLaunchesResolvedBuildProduct() throws {
        let repoRoot = try repositoryRoot()
        let rubyScript = #"""
        require "json"
        require "fileutils"
        require "rake"
        require "tmpdir"

        Dir.chdir(ARGV.fetch(0)) do
          load "Rakefile"

          Dir.mktmpdir("demo-rakefile-ios-tests") do |tmpdir|
            app_path = File.join(tmpdir, "BuildProducts", "Demo.app")
            FileUtils.mkdir_p(app_path)
            commands = []

            define_singleton_method(:ios_demo_device) do
              { name: "Liang iPhone", selector: "iphone-udid", udid: "iphone-udid" }
            end

            define_singleton_method(:xcode_built_product_path) { |**| app_path }
            define_singleton_method(:sh) do |command|
              commands << command

              if (match = command.match(/--json-output\s+(\S+)/))
                json_path = Shellwords.split(match[1]).first

                if command.include?("device process launch")
                  File.write(
                    json_path,
                    JSON.dump({ "result" => { "process" => { "processIdentifier" => 42 } } })
                  )
                elsif command.include?("device info processes")
                  File.write(
                    json_path,
                    JSON.dump({ "result" => { "runningProcesses" => [{ "processIdentifier" => 42 }] } })
                  )
                end
              end
            end
            define_singleton_method(:puts) { |*_args| nil }

            Kernel.singleton_class.class_eval do
              alias_method :__demo_rakefile_tests_original_sleep, :sleep
              define_method(:sleep) { |_seconds| }
            end

            begin
              Rake::Task[:run_ios_demo].reenable
              Rake::Task[:run_ios_demo].invoke
            ensure
              Kernel.singleton_class.class_eval do
                alias_method :sleep, :__demo_rakefile_tests_original_sleep
                remove_method :__demo_rakefile_tests_original_sleep
              end
            end

            STDOUT.write(JSON.dump({
              commands: commands,
              app_path: app_path,
            }))
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
        let appPath = try XCTUnwrap(json["app_path"] as? String)

        XCTAssertEqual(commands.count, 5)
        XCTAssertEqual(
            commands[0],
            "xcodegen generate --spec Xcode/DemoDeviceRunner/project.yml"
        )
        XCTAssertEqual(
            commands[1],
            "xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj -scheme DemoDeviceRunner -configuration Release -destination 'id=iphone-udid' build"
        )
        XCTAssertEqual(
            commands[2],
            "xcrun devicectl device install app --device iphone-udid \(appPath.shellEscapedForTest)"
        )
        XCTAssertTrue(
            commands[3].contains("xcrun devicectl device process launch --device iphone-udid com.liang.pretextswift.demodevicerunner --activate --terminate-existing --json-output ")
        )
        XCTAssertTrue(
            commands[4].hasPrefix("xcrun devicectl device info processes --device iphone-udid --json-output "),
            "Expected the final command to verify the launched iOS process is still running.\n\(commands)"
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
