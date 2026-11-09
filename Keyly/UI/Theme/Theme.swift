import SwiftUI

/// Keyly's single design system: the **"Mono"** direction, chosen from 12 art
/// directions.
///
/// Register: restrained, professional, dark, MONOCHROME. A work tool:
/// it does not distract or shout. Near-black background, hairline borders, ONE near-white accent,
/// SF Mono for hotkeys, numbers, triggers and utility labels.
///
/// The former LIME accent `#D6FF3A` is DROPPED: color remains only on statuses
/// (warn/ok/danger) and only where it carries state, never as decoration.
///
/// Rule: colors/spacing/radii/fonts come ONLY from here, no ad hoc hardcoded
/// values. This is what keeps the interface consistent.
enum Theme {

    enum Colors {
        // Surfaces (bottom to top by "elevation").
        static let bg            = Color(hex: 0x070707)   // window background
        static let surface       = Color(hex: 0x0D0D0D)   // card / recessed field
        static let surfaceHover  = Color(hex: 0x141414)   // nested / hover / floating plate
        static let border        = Color(hex: 0x1E1E1E)   // hairline border
        static let borderStrong  = Color(hex: 0x2B2B2B)   // emphasized border

        // Text
        static let fg            = Color(hex: 0xEDEDED)   // primary
        static let fgMuted       = Color(hex: 0x8A8A8A)   // secondary
        /// Captions and section labels. The design called for #565656, but the WHOLE skeleton
        /// of the interface rests on it (section labels, step numbers, provider names), and that is 2.65:1 on
        /// a card: the skeleton vanished and had to be hunted for. Raised to 4.5:1: the design sets
        /// the REGISTER, and no register needs unreadable text.
        static let fgDim         = Color(hex: 0x7A7A7A)

        // The accent is the only one, near-white. It has no hue: it is monochrome.
        static let accent        = Color(hex: 0xEAEAEA)
        static let accentText    = Color.black            // text/button ON the accent
        static var accentSoft: Color { Color.white.opacity(0.07) }  // selected item background
        static var accentEdge: Color { Color.white.opacity(0.16) }  // border on the accent
        /// Track of an enabled toggle is the accent itself; the knob on it is BLACK.
        static let toggleOn      = accent

        // Semantics: ONLY state, never decoration.
        static let danger        = Color(hex: 0xFF5C57)
        static let warning       = Color(hex: 0xE6C33A)
        static let success       = Color(hex: 0x3EC46D)
        static let recording     = Color(hex: 0xFF5C57)   // recording dot = danger, one palette
        /// Wave bars on the dictation pill: LIGHTER than `fgMuted`, used for the timer.
        /// The wave is the pill's main element, and sharing a tone with the caption devalued it.
        static let waveform      = Color(hex: 0xC2C2C2)
    }

    /// Radii: keycap 4 · card/table 6 · button 8. The scale is deliberately TIGHT:
    /// "toy rounding" is ruled out by the register. The names sm/md/lg are kept to avoid
    /// rewriting every view; the values follow the design.
    enum Radius {
        static let keycap: CGFloat = 4
        static let card: CGFloat = 6
        static let button: CGFloat = 8

        static let sm: CGFloat = button    // fields, pickers, buttons
        static let md: CGFloat = card      // cards, table rows
        static let lg: CGFloat = card      // floating plates: same register, not a pill
        static let xl: CGFloat = card
    }

    /// One height for interactive controls (pickers, hotkey field), so they are not
    /// mismatched sizes within one row.
    enum Size {
        static let control: CGFloat = 38

        /// Dropdown picker width: ONE for the whole product.
        ///
        /// There used to be four: 200 for the key, 220 for the processing model, 200 for the second key, 260 for
        /// the recognition model. Two adjacent pickers of the same kind on the Voice screen
        /// differed by 84pt: the most visible vertical alignment on that screen, and it
        /// fell apart. The value is chosen from the longest real content
        /// ("gpt-4o-mini-transcribe"): cutting to 200 would truncate the model name.
        static let picker: CGFloat = 200
    }

    /// 4/8 spacing scale: no ad hoc "magic" numbers.
    enum Space {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Typography {
        static func display(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold) }
        static func title(_ size: CGFloat = 17)   -> Font { .system(size: size, weight: .semibold) }
        static let body    = Font.system(size: 13)
        static let bodyEmphasis = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .medium)
        /// SF Mono for counters, snippet triggers and utility caps labels.
        static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// KEY COMBINATIONS (`⌥⌘4`, `⌃⌥⇧⌘F12`) use the system font, NOT monospaced.
        ///
        /// This is a measurement, not taste. Modifier glyphs are wider than the monospace advance, and SF Mono
        /// draws them overlapping: "⌥⌘4" takes 24.1pt vs 33.2pt in the system font; ⌥ runs
        /// into ⌘ and the pair reads as one blot (checked by rendering both fonts). For
        /// "⌃⌥⇧⌘F12" the gap is larger: 56.3pt vs 70.6pt.
        ///
        /// Mono was used here "so keys do not jump" in the list, but it gave no alignment
        /// anyway (`~` and `F12` differ in length) and cost readability.
        static func keys(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight)
        }
    }
}

extension Theme {
    /// Recipe for a FLOATING plate, shared by all transient overlays (badge, toast, indicator).
    ///
    /// One home, because each overlay used to reinvent elevation: four different
    /// shadow recipes and radii from different families (`Radius.sm` is the FIELD and picker token, which
    /// made the pill read as a form control rather than a HUD over someone else's window).
    ///
    /// The surface is one step above a card: the overlay hangs over ANOTHER app (dark
    /// editor, white document), and `surface` against a dark editor gives ~1.08:1, so the shape
    /// vanishes. `surfaceHover` + `borderStrong` read both there and on white.
    enum Elevation {
        static let fill = Colors.surfaceHover
        /// The plate edge is LIGHTER than the in-window `borderStrong`; a measurement, not taste.
        ///
        /// The plate hangs over ANOTHER app's window, and its edge must read on any host. With
        /// `borderStrong` #2B2B2B the edge gave 1.16:1 against a dark editor #1E1E1E and
        /// 1.48:1 against a black terminal (measured on pixels of `badge-on-editor.png`:
        /// the border resolved to a single transition pixel, and only the shadow held the shape).
        /// The fill cannot fix this at all: #141414 against #1E1E1E is 1.10:1.
        ///
        /// #686868 gives >= 3:1 (WCAG 1.4.11) against ALL real backdrops at once:
        /// white document 5.6:1 · dark editor 3.0:1 · black terminal 3.8:1 ·
        /// the plate's own fill 3.3:1.
        static let stroke = Color(hex: 0x686868)
        static let radius = Radius.lg
        static let shadowColor = Color.black.opacity(0.4)
        static let shadowRadius: CGFloat = 16
        static let shadowY: CGFloat = 8

        /// Shadow of the DICTATION PILL, denser than the shared one: the capsule has no border,
        /// so the shadow alone holds its shape. Two layers: a wide halo and a short
        /// contact shadow.
        static let pillShadowRadius: CGFloat = 24
        static let pillShadowY: CGFloat = 8
        static let pillShadowOpacity: Double = 0.55
        static let pillContactRadius: CGFloat = 6
        static let pillContactY: CGFloat = 2
        static let pillContactOpacity: Double = 0.35

        /// Margin around the plate for the shadow. The shadow is not part of the layout size, so without margin
        /// the window edge clips it (a borderless window has no system shadow).
        ///
        /// DERIVED from the shadow parameters, not set as a number. These used to be two
        /// independent numbers in different files: the radius went from 16 to 24 while the margin stayed
        /// 22, and the shadow hit the window edge, drawing a SHARP RECTANGLE around the capsule
        /// (the box the shadow was confined to became visible). As long as the numbers are not linked,
        /// this bug class returns with every shadow tweak.
        ///
        /// The blur tail extends FURTHER than the nominal radius, roughly threefold.
        ///
        /// The first formula used `radius + |offsetY| + 4` and still clipped the shadow:
        /// measuring alpha along the live window edge gave 21/255 at the very edge, i.e. the visible
        /// tail hit the border and drew a rectangle. SwiftUI's `radius` is a blur
        /// parameter, not its full extent: the Gaussian tail fades noticeably further out.
        /// A 2.5 multiplier brings the edge to zero with margin (verified by the same measurement).
        static func margin(radius: CGFloat, offsetY: CGFloat) -> CGFloat {
            ceil(radius * 2.5 + abs(offsetY) + 4)
        }

        /// Margin for the SHARED plate shadow (badge, toast).
        static var shadowMargin: CGFloat { margin(radius: shadowRadius, offsetY: shadowY) }

        /// Margin for the DICTATION PILL shadow: it is wider, so the margin is larger.
        static var pillShadowMargin: CGFloat { margin(radius: pillShadowRadius, offsetY: pillShadowY) }
    }
}

extension View {
    /// Floating overlay shell: background + hairline + shadow + shadow margin.
    /// `insetForShadow: false` when the caller already provides the margin (e.g. the QA exporter).
    func keylyOverlayPlate(insetForShadow: Bool = true) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.Elevation.radius, style: .continuous)
                    .fill(Theme.Elevation.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Elevation.radius, style: .continuous)
                            .strokeBorder(Theme.Elevation.stroke, lineWidth: 1)
                    )
            )
            .shadow(color: Theme.Elevation.shadowColor,
                    radius: Theme.Elevation.shadowRadius,
                    y: Theme.Elevation.shadowY)
            .padding(insetForShadow ? Theme.Elevation.shadowMargin : 0)
    }
}

extension Color {
    /// `Color(hex: 0xD6FF3A)`: compact initializer from an RGB hex value.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
