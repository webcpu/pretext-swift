import SwiftUI

enum DemoScreen: String, CaseIterable, Identifiable {
    case situationalAwareness
    case editorialEngine
    case benchmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .situationalAwareness:
            "Situational Awareness"
        case .editorialEngine:
            "Editorial Engine"
        case .benchmarks:
            "Benchmarks"
        }
    }
}

struct ContentView: View {
    @State private var selection: DemoScreen = .benchmarks

    var body: some View {
        Group {
            switch selection {
            case .situationalAwareness:
                EditorialView()
            case .editorialEngine:
                OrbEditorialView()
            case .benchmarks:
                BenchmarkView()
            }
        }
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Demo", selection: $selection) {
                    ForEach(DemoScreen.allCases) { screen in
                        Text(screen.title).tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
        }
    }
}
