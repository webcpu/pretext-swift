import SwiftUI

#if os(macOS)
import AppKit
typealias DemoPlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias DemoPlatformImage = UIImage
#elseif os(watchOS)
import CoreGraphics
typealias DemoPlatformImage = CGImage
#endif

enum DemoNavigationStyle: Equatable {
    case tabBar
    case toolbarPicker
    case watchList

    static func forWidthClass(
        isCompact _: Bool?,
        platform: DemoNavigationPlatform = .current
    ) -> Self {
        switch platform {
        case .ios:
            .tabBar
        case .macOS:
            .toolbarPicker
        case .watchOS:
            .watchList
        }
    }
}

enum DemoNavigationPlatform: Equatable {
    case ios
    case macOS
    case watchOS

    static var current: Self {
        #if os(macOS)
        .macOS
        #elseif os(watchOS)
        .watchOS
        #else
        .ios
        #endif
    }
}

enum DemoPointerCursor: Equatable {
    case iBeam
    case pointingHand
    case openHand
    case closedHand

    #if os(macOS)
    var platformCursor: NSCursor {
        switch self {
        case .iBeam:
            .iBeam
        case .pointingHand:
            .pointingHand
        case .openHand:
            .openHand
        case .closedHand:
            .closedHand
        }
    }
    #endif
}

extension Image {
    init(platformImage image: DemoPlatformImage) {
        #if os(macOS)
        self = Image(nsImage: image)
        #elseif os(iOS)
        self = Image(uiImage: image)
        #else
        self = Image(decorative: image, scale: 1)
        #endif
    }
}

private struct DemoHoverStateModifier: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover(perform: onChange)
        #else
        content
        #endif
    }
}

private struct DemoContinuousHoverModifier: ViewModifier {
    let onChange: (CGPoint?) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(location):
                onChange(location)
            case .ended:
                onChange(nil)
            }
        }
        #else
        content
        #endif
    }
}

private struct DemoCursorModifier: ViewModifier {
    let cursor: DemoPointerCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onHover { hovering in
                guard hovering != isHovering else {
                    return
                }

                if hovering {
                    cursor.platformCursor.push()
                } else {
                    NSCursor.pop()
                }
                isHovering = hovering
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
        #else
        content
        #endif
    }
}

private struct DemoConditionalCursorModifier: ViewModifier {
    let isActive: Bool
    let cursor: DemoPointerCursor
    @State private var isApplied = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onAppear {
                syncCursor(shouldApply: isActive)
            }
            .onChange(of: isActive) { _, newValue in
                syncCursor(shouldApply: newValue)
            }
            .onDisappear {
                syncCursor(shouldApply: false)
            }
        #else
        content
        #endif
    }

    private func syncCursor(shouldApply: Bool) {
        #if os(macOS)
        guard shouldApply != isApplied else {
            return
        }

        if shouldApply {
            cursor.platformCursor.push()
        } else {
            NSCursor.pop()
        }
        isApplied = shouldApply
        #endif
    }
}

private struct DemoOptionalCursorModifier: ViewModifier {
    let cursor: DemoPointerCursor?
    @State private var appliedCursor: DemoPointerCursor?

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onAppear {
                syncCursor(to: cursor)
            }
            .onChange(of: cursor, initial: true) { _, newCursor in
                syncCursor(to: newCursor)
            }
            .onDisappear {
                syncCursor(to: nil)
            }
        #else
        content
        #endif
    }

    private func syncCursor(to newCursor: DemoPointerCursor?) {
        #if os(macOS)
        guard newCursor != appliedCursor else {
            return
        }

        if appliedCursor != nil {
            NSCursor.pop()
        }
        if let newCursor {
            newCursor.platformCursor.push()
        }
        appliedCursor = newCursor
        #endif
    }
}

extension View {
    func demoTextSelectionEnabled() -> some View {
        #if os(watchOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }

    func demoHoverState(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(DemoHoverStateModifier(onChange: onChange))
    }

    func demoContinuousHover(_ onChange: @escaping (CGPoint?) -> Void) -> some View {
        modifier(DemoContinuousHoverModifier(onChange: onChange))
    }

    func demoPointerCursor(_ cursor: DemoPointerCursor) -> some View {
        modifier(DemoCursorModifier(cursor: cursor))
    }

    func demoPointerCursor(active: Bool, cursor: DemoPointerCursor) -> some View {
        modifier(DemoConditionalCursorModifier(isActive: active, cursor: cursor))
    }

    func demoPointerCursor(_ cursor: DemoPointerCursor?) -> some View {
        modifier(DemoOptionalCursorModifier(cursor: cursor))
    }
}
