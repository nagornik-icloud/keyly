import SwiftUI

/// Soft fade at the TOP and BOTTOM edges of the content area.
///
/// Goal: the top and bottom of the window had black lines cutting off content — a smooth
/// gradient was wanted instead of a hard border.
///
/// HISTORY MATTERS. A fade was tried before and rejected as "a foreign black bar covering
/// content". The difference now is fundamental — that bar was SOLID and always present,
/// while this gradient goes from transparent to the background and occupies a narrow edge.
/// So this does not reverse the earlier decision but refines it: "a hard cut is bad, a solid
/// bar is bad too, what's needed is a smooth transition".
///
/// The gradient is drawn ON TOP of content and does not catch the mouse: clickable rows live under it.
struct ContentEdgeFade: ViewModifier {
    /// Fade height.
    ///
    /// It was 20pt, and the gradient was reported as invisible. Measuring a real window
    /// confirmed it: over 20pt the background (#070707) and card surface (#0d0d0d) differ
    /// by 6 values out of 255 — the transition exists in pixels but not for the eye.
    /// Over such a distance the fade only eats the edge of a row.
    ///
    /// The color stays THE BACKGROUND COLOR, not darker: a band darker than the background was
    /// already rejected ("a foreign black bar"). Visibility comes from length, not
    /// darkening — over empty space the band is still not visible at all.
    private let fade: CGFloat = 44

    /// Whether we have scrolled away from the very top. The top fade is needed ONLY then.
    ///
    /// While it was always on, on an unscrolled screen it lay over the header, which nothing
    /// obstructed: the header looked smudged, and that read as a rendering defect, not as a
    /// hint of continuation. The bottom edge looked fine precisely because content really
    /// continued below it.
    @State private var scrolledFromTop = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                // At REST `contentOffset.y` equals MINUS the top inset, not zero: the inset comes
                // from the window safe area and `contentMargins` (24pt). Comparing with
                // "+ insets.top" required scrolling TWO insets (~100pt) before the top fade
                // turned on — exactly the observed bug: the header already cut off by the edge,
                // and no gradient yet. Zero is offset + inset.
                //
                // 2pt margin: a fractional offset when scrolling stopped caused flicker.
                geo.contentOffset.y + geo.contentInsets.top > 2
            } action: { _, isAway in
                scrolledFromTop = isAway
            }
            .overlay(alignment: .top) {
                band(top: true)
                    .opacity(scrolledFromTop ? 1 : 0)
                    .animation(KeylyMotion.standard, value: scrolledFromTop)
            }
            .overlay(alignment: .bottom) { band(top: false) }
    }

    private func band(top: Bool) -> some View {
        LinearGradient(
            colors: [Theme.Colors.bg, Theme.Colors.bg.opacity(0)],
            startPoint: top ? .top : .bottom,
            endPoint: top ? .bottom : .top
        )
        .frame(height: fade)
        // The WINDOW EDGE, not the safe area — otherwise the gradient fades the wrong border.
        //
        // The app window uses `.fullSizeContentView`: scroll content reaches the very top of the
        // window, but the overlay lays out INSIDE the safe area and sat ~28pt lower — under the
        // title bar strip. The result: the top ~28pt of content were sharp and unfaded, a LINE
        // was visible at the border, and the gradient started "in the wrong place" — mid-text.
        //
        // The same class was already caught on the close cross (`OnboardingView.closeButton`):
        // insets match only when measured from the same edge.
        .ignoresSafeArea(edges: top ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

extension View {
    func contentEdgeFade() -> some View { modifier(ContentEdgeFade()) }
}
