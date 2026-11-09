import SwiftUI
import AppKit

/// Product motion in one place.
///
/// Two things at once. First, one shared duration and curve: animations typed ad hoc
/// drift apart, and the product starts moving at three different tempos.
///
/// Second, and more important: the system "Reduce motion" setting. People turn it on not
/// out of taste: animation makes them nauseous or dizzy. The product used to ignore this
/// flag entirely, so the accessibility setting simply did not work here.
enum KeylyMotion {

    /// Whether the system "Reduce motion" setting is on.
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Standard state transition: 180 ms, ease-out. With reduce motion it is
    /// `nil`, i.e. the change is applied IMMEDIATELY as the final frame, not cancelled.
    static var standard: Animation? {
        isReduced ? nil : .easeOut(duration: 0.18)
    }

    /// A more noticeable appear/disappear (popovers, expanding sections): 220 ms.
    static var emphasis: Animation? {
        isReduced ? nil : .easeInOut(duration: 0.22)
    }

    /// Press feedback. The spring is soft and short: it is feedback, not an effect.
    static var press: Animation? {
        isReduced ? nil : .spring(response: 0.3, dampingFraction: 0.6)
    }
}


/// Highlight of the row under the pointer.
///
/// On desktop, hover is half of the answer to "is this clickable at all". The product
/// is made of lists, and before this no row reacted to the pointer: a clickable
/// row looked exactly like the label next to it.
private struct KeylyHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.sm
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? Theme.Colors.surfaceHover.opacity(0.6) : Color.clear)
            )
            .animation(KeylyMotion.standard, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func keylyHoverHighlight(cornerRadius: CGFloat = Theme.Radius.sm) -> some View {
        modifier(KeylyHoverHighlight(cornerRadius: cornerRadius))
    }
}

/// Hover highlight only where the row is NOT selected.
struct HoverIfNotSelected: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
        } else {
            content.keylyHoverHighlight(cornerRadius: 0)
        }
    }
}
