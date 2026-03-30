require "json"

def ios_simulator_destination(name_prefix)
  devices = JSON.parse(`xcrun simctl list devices available --json`).fetch("devices").values.flatten
  device = devices.find { |entry| entry["isAvailable"] && entry["name"].start_with?(name_prefix) }

  raise "No available #{name_prefix} simulator found" unless device

  "platform=iOS Simulator,id=#{device.fetch("udid")}"
end

def ios_pretext_test_destination
  ios_simulator_destination("iPhone")
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

desc "Run PretextTests on an iOS Simulator"
task :test_ios_pretext do
  sh "xcodebuild test -scheme PretextSwift-Package -destination '#{ios_pretext_test_destination}' -only-testing:PretextTests CODE_SIGNING_ALLOWED=NO"
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

desc "Run core engine tests only"
task :test_pretext do
  sh "swift test --filter PretextTests"
end

desc "Run demo tests only"
task :test_demo do
  sh "swift test --filter DemoTests"
end

desc "Launch the demo app (release mode)"
task :demo => :release do
  sh ".build/release/Demo"
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
