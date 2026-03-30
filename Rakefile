desc "Debug build (all targets)"
task :build do
  sh "swift build"
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
