import BenchmarkSupport
import SwiftUI

@main
enum BenchmarkMain {
    static func main() {
        if CommandLine.arguments.contains("--cli") {
            runBenchmarkCLI()
        } else {
            BenchmarkGUIApp.main()
        }
    }
}

private struct BenchmarkGUIApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            BenchmarkView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 800)
        #else
        WindowGroup {
            BenchmarkView()
        }
        #endif
    }
}
