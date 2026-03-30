import SwiftUI

@main
struct PretextDemoApp: App {
    init() {
        if CommandLine.arguments.contains("--benchmark") {
            DispatchQueue.global(qos: .userInitiated).async {
                runCLIBenchmark()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
        }
        .defaultSize(width: 1440, height: 960)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

// MARK: - CLI Benchmark (Test 1 only)

private func runCLIBenchmark() {
    let result = runBatchPrepareAndLayout()

    // Run one more pass to capture profile breakdowns (the benchmark
    // resets profiles between median iterations, so they are zeroed
    // after runBatchPrepareAndLayout returns).
    PrepareProfile.reset()
    AnalysisSubProfile.reset()
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let width = BenchmarkCorpus.testWidth
    let lineHeight = BenchmarkCorpus.lineHeight
    for text in texts {
        let prepared = prepare(text, font: font)
        _ = layout(prepared, maxWidth: width, lineHeight: lineHeight)
    }

    print("=== Batch Prepare+Layout (500 texts) ===")
    print(String(format: "Pretext:    %8.2f ms", result.pretextMs))
    print(String(format: "Core Text:  %8.2f ms", result.coreTextMs))
    if let swiftUI = result.swiftUIMs {
        print(String(format: "SwiftUI:    %8.2f ms", swiftUI))
    }
    print(String(format: "Speedup vs Core Text: %.1fx", result.speedupVsCoreText))
    if let speedup = result.speedupVsSwiftUI {
        print(String(format: "Speedup vs SwiftUI:   %.1fx", speedup))
    }
    print()
    print(PrepareProfile.summary())
    print(AnalysisSubProfile.summary())

    exit(0)
}
