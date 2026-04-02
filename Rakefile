require "json"
require "open3"
require "shellwords"
require "timeout"
require "tmpdir"

def latest_path(glob)
  Dir[File.expand_path(glob)].max_by { |path| File.mtime(path) }
end

def xcode_build_settings(project:, scheme:, configuration:, destination: nil)
  command = [
    "xcodebuild",
    "-project", project,
    "-scheme", scheme,
    "-configuration", configuration,
    "-showBuildSettings",
  ]
  command += ["-destination", destination] if destination

  output, status = Open3.capture2e(*command)
  raise "Unable to resolve build settings for #{scheme}.\n#{output}" unless status.success?

  output.each_line.each_with_object({}) do |line, settings|
    match = line.match(/^\s*([A-Z0-9_]+)\s=\s(.*)$/)
    next unless match

    settings[match[1]] = match[2]
  end
end

def xcode_built_product_path(project:, scheme:, configuration:, destination: nil)
  settings = xcode_build_settings(
    project: project,
    scheme: scheme,
    configuration: configuration,
    destination: destination
  )
  target_build_dir = settings["TARGET_BUILD_DIR"]
  product_name = settings["FULL_PRODUCT_NAME"]

  raise "Unable to locate TARGET_BUILD_DIR for #{scheme}." if target_build_dir.nil? || target_build_dir.empty?
  raise "Unable to locate FULL_PRODUCT_NAME for #{scheme}." if product_name.nil? || product_name.empty?

  File.join(target_build_dir, product_name)
end

def devicectl_devices
  output_path = File.join(Dir.tmpdir, "devicectl-devices-#{Process.pid}.json")
  success = system(
    "xcrun", "devicectl", "list", "devices", "--json-output", output_path,
    out: File::NULL, err: File::NULL
  )
  raise "Unable to query devices with devicectl." unless success

  JSON.parse(File.read(output_path)).fetch("result").fetch("devices")
ensure
  File.delete(output_path) if output_path && File.exist?(output_path)
end

def watchos_demo_device
  requested = ENV["WATCHOS_DEVICE"]
  devices = devicectl_devices

  device = if requested
    devices.find do |entry|
      [
        entry["identifier"],
        entry.dig("hardwareProperties", "udid"),
        entry.dig("deviceProperties", "name"),
      ].compact.include?(requested)
    end
  else
    devices.find do |entry|
      entry.dig("hardwareProperties", "platform") == "watchOS" &&
        entry.dig("hardwareProperties", "reality") == "physical" &&
        entry.dig("connectionProperties", "tunnelState") == "connected"
    end
  end

  if device.nil? && requested
    raise "No watchOS device matching WATCHOS_DEVICE=#{requested.inspect} found."
  end

  raise "No connected physical watchOS device found. Set WATCHOS_DEVICE to a device name, identifier, or UDID to override." if device.nil?

  {
    name: device.dig("deviceProperties", "name") || device.fetch("identifier"),
    selector: requested || device.dig("hardwareProperties", "udid") || device.fetch("identifier"),
    udid: device.dig("hardwareProperties", "udid") || device.fetch("identifier"),
  }
end

def ios_simulator_destination(name_prefix)
  devices = JSON.parse(`xcrun simctl list devices available --json`).fetch("devices").values.flatten
  device = devices.find { |entry| entry["isAvailable"] && entry["name"].start_with?(name_prefix) }

  raise "No available #{name_prefix} simulator found" unless device

  "platform=iOS Simulator,id=#{device.fetch("udid")}"
end

def watchos_simulator_destination(name_prefix)
  devices = JSON.parse(`xcrun simctl list devices available --json`).fetch("devices").values.flatten
  device = devices.find { |entry| entry["isAvailable"] && entry["name"].start_with?(name_prefix) }

  raise "No available #{name_prefix} simulator found" unless device

  "platform=watchOS Simulator,id=#{device.fetch("udid")}"
end

def ios_pretext_test_destination
  ios_simulator_destination("iPhone")
end

def watchos_pretext_test_destination
  watchos_simulator_destination("Apple Watch")
end

desc "Debug build (all targets)"
task :build do
  sh "swift build"
end

desc "Build the Pretext library for iOS Simulator"
task :build_ios_pretext do
  sh "xcodebuild -scheme Pretext -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO"
end

desc "Build the Demo app for iPhone and iPad simulators"
task :build_ios_demo do
  sh "xcodebuild build -scheme Demo -destination '#{ios_simulator_destination("iPhone")}' CODE_SIGNING_ALLOWED=NO"
  sh "xcodebuild build -scheme Demo -destination '#{ios_simulator_destination("iPad")}' CODE_SIGNING_ALLOWED=NO"
end

desc "Build the Demo macOS app bundle"
task :build_macos_demo do
  sh "xcodegen generate --spec Xcode/DemoMacRunner/project.yml"
  sh "xcodebuild -project Xcode/DemoMacRunner/DemoMacRunner.xcodeproj -scheme DemoMacRunner -configuration Release build"
end

desc "Build the Demo watchOS app for Apple Watch simulators"
task :build_watchos_demo do
  sh "xcodegen generate --spec Xcode/DemoWatchRunner/project.yml"
  sh "xcodebuild -project Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj -scheme DemoWatchRunner -configuration Release -destination 'generic/platform=watchOS Simulator' build CODE_SIGNING_ALLOWED=NO"
end

desc "Build, install, and launch the Demo watchOS app on a connected Apple Watch"
task :run_watchos_demo do
  device = watchos_demo_device
  device_selector = Shellwords.escape(device.fetch(:selector))

  sh "xcodegen generate --spec Xcode/DemoWatchRunner/project.yml"
  sh "xcodebuild -project Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj -scheme DemoWatchRunner -configuration Release -destination 'id=#{device.fetch(:udid)}' build"

  app_path = latest_path("~/Library/Developer/Xcode/DerivedData/DemoWatchRunner-*/Build/Products/Release-watchos/Demo.app")
  raise "Built Demo.app not found in DerivedData." unless app_path

  app_path_escaped = Shellwords.escape(app_path)
  bundle_id = "com.liang.pretextswift.demowatchrunner"

  sh "xcrun devicectl device install app --device #{device_selector} #{app_path_escaped}"

  Dir.mktmpdir("watchos-demo-run") do |tmpdir|
    launch_json = File.join(tmpdir, "launch.json")
    processes_json = File.join(tmpdir, "processes.json")
    launch_json_escaped = Shellwords.escape(launch_json)
    processes_json_escaped = Shellwords.escape(processes_json)

    sh "xcrun devicectl device process launch --device #{device_selector} #{bundle_id} --activate --terminate-existing --json-output #{launch_json_escaped}"

    process_id = JSON.parse(File.read(launch_json)).dig("result", "process", "processIdentifier")
    sleep 2

    sh "xcrun devicectl device info processes --device #{device_selector} --json-output #{processes_json_escaped}"

    running_processes = JSON.parse(File.read(processes_json)).dig("result", "runningProcesses").to_a
    running = running_processes.any? { |entry| entry["processIdentifier"] == process_id }
    raise "Demo.app exited immediately after launch on #{device.fetch(:name)}." unless running
  end

  puts "Launched #{bundle_id} on #{device.fetch(:name)} (#{device.fetch(:udid)})."
end

desc "Run PretextTests on an iOS Simulator"
task :test_ios_pretext do
  sh "xcodebuild test -scheme PretextSwift-Package -destination '#{ios_pretext_test_destination}' -only-testing:PretextTests CODE_SIGNING_ALLOWED=NO"
end

desc "Run PretextTests on a watchOS Simulator"
task :test_watchos_pretext do
  sh "xcodegen generate --spec Xcode/PretextWatchTestRunner/project.yml"
  sh "xcodebuild test -project Xcode/PretextWatchTestRunner/PretextWatchTestRunner.xcodeproj -scheme PretextWatchTests -destination '#{watchos_pretext_test_destination}' CODE_SIGNING_ALLOWED=NO"
end

desc "Run DemoTests on an iOS Simulator"
task :test_ios_demo do
  sh "xcodebuild test -scheme PretextSwift-Package -destination '#{ios_simulator_destination("iPhone")}' -only-testing:DemoTests CODE_SIGNING_ALLOWED=NO"
end

desc "Release build"
task :release do
  sh "swift build -c release"
end

desc "Run all tests"
task :test do
  sh "swift test"
end

desc "Run complete Pretext test cases on the host platform"
task :test_pretext_host do
  sh "swift test --filter '^PretextTests\\.'"
end

desc "Run complete Pretext test cases"
task test_pretext: :test_pretext_host

desc "Run demo tests only"
task :test_demo do
  sh "swift test --filter DemoTests"
end

desc "Launch the demo app"
task :demo do
  if RUBY_PLATFORM.include?("darwin")
    Rake::Task[:build_macos_demo].invoke
    app_path = xcode_built_product_path(
      project: "Xcode/DemoMacRunner/DemoMacRunner.xcodeproj",
      scheme: "DemoMacRunner",
      configuration: "Release"
    )
    raise "Built Demo.app not found at #{app_path}." unless File.exist?(app_path)

    executable_path = File.join(
      app_path,
      "Contents",
      "MacOS",
      File.basename(app_path, ".app")
    )
    escaped_executable_path = Shellwords.escape(executable_path)
    escaped_app_path = Shellwords.escape(app_path)

    sh "pkill -TERM -f #{escaped_executable_path} || true"

    begin
      Timeout.timeout(5) do
        loop do
          running = system("pgrep -f #{escaped_executable_path} >/dev/null 2>&1")
          break unless running

          sleep 0.1
        end
      end
    rescue Timeout::Error
      raise "Timed out waiting for #{executable_path} to terminate before relaunch."
    end

    sh "open -n #{escaped_app_path}"
  else
    Rake::Task[:release].invoke
    sh ".build/release/Demo"
  end
end

desc "Launch the benchmark GUI (release mode)"
task :benchmark => :release do
  sh ".build/release/Benchmark"
end

desc "Run CLI benchmark (release mode)"
task :bench => :release do
  sh ".build/release/Benchmark --cli"
end

desc "Clean build artifacts"
task :clean do
  sh "swift package clean"
end

task default: :build
