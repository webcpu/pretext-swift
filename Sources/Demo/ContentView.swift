import BenchmarkSupport
import SwiftUI

enum DemoScreen: String, CaseIterable, Identifiable, Hashable {
    case situationalAwareness
    case editorialEngine
    case masonry
    case chikaDance
    case illustratedManuscript
    case liveCameraSilhouette
    case fluid
    case benchmark

    var id: String { rawValue }

    static func availableCases(for platform: DemoNavigationPlatform = .current) -> [DemoScreen] {
        switch platform {
        case .ios, .macOS:
            DemoScreen.allCases
        case .watchOS:
            [
                .situationalAwareness,
                .editorialEngine,
                .masonry,
                .illustratedManuscript,
                .benchmark,
            ]
        }
    }

    static func defaultSelection(for platform: DemoNavigationPlatform = .current) -> DemoScreen {
        availableCases(for: platform).first ?? .situationalAwareness
    }

    static func launchSelection(
        arguments: [String] = CommandLine.arguments,
        platform: DemoNavigationPlatform = .current
    ) -> DemoScreen? {
        guard let flagIndex = arguments.firstIndex(of: "--demo-screen"),
              arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }

        guard let selection = DemoScreen(rawValue: arguments[arguments.index(after: flagIndex)]) else {
            return nil
        }

        return availableCases(for: platform).contains(selection) ? selection : nil
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
        case .liveCameraSilhouette:
            "Live Camera Silhouette"
        case .fluid:
            "Fluid"
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
        case .liveCameraSilhouette:
            "Camera"
        case .fluid:
            "Fluid"
        case .benchmark:
            "Bench"
        }
    }

    var toolbarPickerTitle: String {
        compactTitle
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
        case .liveCameraSilhouette:
            "person.crop.rectangle"
        case .fluid:
            "drop.fill"
        case .benchmark:
            "speedometer"
        }
    }
}

func demoInitialNavigationPath(
    launchSelection: DemoScreen?,
    platform: DemoNavigationPlatform = .current
) -> [DemoScreen] {
    guard platform == .watchOS, let launchSelection else {
        return []
    }

    return [launchSelection]
}

private struct WatchUnsupportedDemoView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "applewatch.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("This demo is intentionally excluded from the Apple Watch catalog.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(18)
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: DemoScreen
    @State private var watchPath: [DemoScreen]

    init(
        arguments: [String] = CommandLine.arguments,
        platform: DemoNavigationPlatform = .current
    ) {
        let launchSelection = DemoScreen.launchSelection(
            arguments: arguments,
            platform: platform
        )
        _selection = State(
            initialValue: launchSelection ?? DemoScreen.defaultSelection(for: platform)
        )
        _watchPath = State(
            initialValue: demoInitialNavigationPath(
                launchSelection: launchSelection,
                platform: platform
            )
        )
    }

    var body: some View {
        switch DemoNavigationStyle.forWidthClass(isCompact: isCompactWidth, platform: .current) {
        case .tabBar:
            TabView(selection: $selection) {
                ForEach(availableScreens) { screen in
                    demoView(for: screen)
                        .tabItem {
                            Label(screen.compactTitle, systemImage: screen.systemImage)
                        }
                        .tag(screen)
                }
            }
            .ignoresSafeArea()
        case .toolbarPicker:
            #if os(watchOS)
            demoView(for: selection)
            #else
            demoView(for: selection)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Demo", selection: $selection) {
                            ForEach(availableScreens) { screen in
                                Text(screen.toolbarPickerTitle)
                                    .help(screen.title)
                                    .accessibilityLabel(screen.title)
                                    .tag(screen)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 640)
                    }
                }
            #endif
        case .watchList:
            NavigationStack(path: $watchPath) {
                List(availableScreens) { screen in
                    NavigationLink(value: screen) {
                        Label(screen.title, systemImage: screen.systemImage)
                    }
                }
                .navigationTitle("Pretext")
                .navigationDestination(for: DemoScreen.self) { screen in
                    let destinationView = demoView(for: screen)

                    if demoNavigationDestinationUsesSafeArea(platform: .current) {
                        if demoNavigationDestinationShowsTitle(platform: .current) {
                            if demoNavigationDestinationFillsContainer(platform: .current) {
                                destinationView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .navigationTitle(screen.compactTitle)
                            } else {
                                destinationView
                                    .navigationTitle(screen.compactTitle)
                            }
                        } else {
                            if demoNavigationDestinationFillsContainer(platform: .current) {
                                destinationView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            } else {
                                destinationView
                            }
                        }
                    } else {
                        if demoNavigationDestinationShowsTitle(platform: .current) {
                            if demoNavigationDestinationFillsContainer(platform: .current) {
                                destinationView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .ignoresSafeArea()
                                    .navigationTitle(screen.compactTitle)
                            } else {
                                destinationView
                                    .ignoresSafeArea()
                                    .navigationTitle(screen.compactTitle)
                            }
                        } else {
                            if demoNavigationDestinationFillsContainer(platform: .current) {
                                destinationView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .ignoresSafeArea()
                            } else {
                                destinationView
                                    .ignoresSafeArea()
                            }
                        }
                    }
                }
            }
        }
    }

    private var isCompactWidth: Bool? {
        horizontalSizeClass.map { $0 == .compact }
    }

    private var availableScreens: [DemoScreen] {
        DemoScreen.availableCases(for: .current)
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
            #if os(watchOS)
            WatchUnsupportedDemoView(title: screen.title)
            #else
            ChikaDanceView()
            #endif
        case .illustratedManuscript:
            IllustratedManuscriptView()
        case .liveCameraSilhouette:
            #if os(watchOS)
            WatchUnsupportedDemoView(title: screen.title)
            #else
            CameraSilhouetteView()
            #endif
        case .fluid:
            #if os(watchOS)
            WatchUnsupportedDemoView(title: screen.title)
            #else
            FluidView()
            #endif
        case .benchmark:
            BenchmarkView()
        }
    }
}
