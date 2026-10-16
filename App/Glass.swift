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
    /// Runs `action` when the scroll view inside starts moving (iOS 18+ / macOS 15+); no-op earlier.
    @ViewBuilder
    func collapseOnScroll(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting || newPhase == .decelerating { action() }
            }
        } else {
            self
        }
    }
}
