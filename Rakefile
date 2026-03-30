require "json"

def ios_pretext_test_destination
  devices = JSON.parse(`xcrun simctl list devices available --json`).fetch("devices").values.flatten
  iphone = devices.find { |device| device["isAvailable"] && device["name"].start_with?("iPhone") }

  raise "No available iPhone simulator found" unless iphone

  "platform=iOS Simulator,id=#{iphone.fetch("udid")}"
end

desc "Debug build (all targets)"
task :build do
  sh "swift build"
end

desc "Build the Pretext library for iOS Simulator"
task :build_ios_pretext do
  sh "xcodebuild -scheme Pretext -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO"
end

desc "Run PretextTests on an iOS Simulator"
task :test_ios_pretext do
  sh "xcodebuild test -scheme PretextSwift-Package -destination '#{ios_pretext_test_destination}' -only-testing:PretextTests CODE_SIGNING_ALLOWED=NO"
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
