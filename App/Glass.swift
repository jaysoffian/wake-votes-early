import SwiftUI

/// Liquid Glass on iOS 26 / macOS 26, a plain material on earlier systems.
struct AdaptiveGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(shape.fill(.regularMaterial))
        }
    }
}

extension View {
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        modifier(AdaptiveGlass(shape: shape))
    }

    /// Lets scrolling content fade softly as it passes under floating glass (iOS 26+).
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

extension View {
    /// iOS 26's bottom search pill that shrinks to an icon while scrolling; plain searchable earlier.
    @ViewBuilder
    func minimizingSearchToolbar() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
