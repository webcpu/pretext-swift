import BenchmarkSupport
import SwiftUI

enum DemoScreen: String, CaseIterable, Identifiable {
    case situationalAwareness
    case editorialEngine
    case benchmark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .situationalAwareness:
            "Situational Awareness"
        case .editorialEngine:
            "Editorial Engine"
        case .benchmark:
            "Benchmark"
        }
    }
}

struct ContentView: View {
    @State private var selection: DemoScreen = .situationalAwareness

    var body: some View {
        Group {
            switch selection {
            case .situationalAwareness:
                EditorialView()
            case .editorialEngine:
                OrbEditorialView()
            case .benchmark:
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
