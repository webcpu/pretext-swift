import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
        }
        .defaultSize(width: 1440, height: 960)
        .windowToolbarStyle(.unified(showsTitle: false))
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
