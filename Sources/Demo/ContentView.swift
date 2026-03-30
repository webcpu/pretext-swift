import BenchmarkSupport
import SwiftUI

enum DemoScreen: String, CaseIterable, Identifiable {
    case situationalAwareness
    case editorialEngine
    case masonry
    case chikaDance
    case illustratedManuscript
    case benchmark

    var id: String { rawValue }

    static func launchSelection(arguments: [String] = CommandLine.arguments) -> DemoScreen? {
        guard let flagIndex = arguments.firstIndex(of: "--demo-screen"),
              arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }

        return DemoScreen(rawValue: arguments[arguments.index(after: flagIndex)])
    }

    var title: String {
        switch self {
        case .situationalAwareness:
            "Situational Awareness"
        case .editorialEngine:
            "Editorial Engine"
        case .masonry:
            "Masonry"
        case .chikaDance:
            "Chika Dance"
        case .illustratedManuscript:
            "Illustrated Manuscript"
        case .benchmark:
            "Benchmark"
        }
    }

    var compactTitle: String {
        switch self {
        case .situationalAwareness:
            "Aware"
        case .editorialEngine:
            "Editorial"
        case .masonry:
            "Masonry"
        case .chikaDance:
            "Chika"
        case .illustratedManuscript:
            "Script"
        case .benchmark:
            "Bench"
        }
    }

    var systemImage: String {
        switch self {
        case .situationalAwareness:
            "text.alignleft"
        case .editorialEngine:
            "circle.grid.3x3.fill"
        case .masonry:
            "square.grid.2x2"
        case .chikaDance:
            "play.rectangle"
        case .illustratedManuscript:
            "text.book.closed"
        case .benchmark:
            "speedometer"
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: DemoScreen = DemoScreen.launchSelection() ?? .situationalAwareness

    var body: some View {
        switch DemoNavigationStyle.forWidthClass(isCompact: isCompactWidth) {
        case .tabBar:
            TabView(selection: $selection) {
                ForEach(DemoScreen.allCases) { screen in
                    demoView(for: screen)
                        .tabItem {
                            Label(screen.compactTitle, systemImage: screen.systemImage)
                        }
                        .tag(screen)
                }
            }
            .ignoresSafeArea()
        case .toolbarPicker:
            demoView(for: selection)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Demo", selection: $selection) {
                            ForEach(DemoScreen.allCases) { screen in
                                Text(screen.title).tag(screen)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 640)
                    }
                }
        }
    }

    private var isCompactWidth: Bool? {
        horizontalSizeClass.map { $0 == .compact }
    }

    @ViewBuilder
    private func demoView(for screen: DemoScreen) -> some View {
        switch screen {
        case .situationalAwareness:
            EditorialView()
        case .editorialEngine:
            OrbEditorialView()
        case .masonry:
            MasonryView()
        case .chikaDance:
            ChikaDanceView()
        case .illustratedManuscript:
            IllustratedManuscriptView()
        case .benchmark:
            BenchmarkView()
        }
    }
}
