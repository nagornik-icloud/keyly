import SwiftUI

/// A short message at the caret: "No input field", "No errors found", "Fixing…".
/// Quiet and minimal — not a dialog but a hint for a couple of seconds.
///
/// **Contract:** one short line (≤ `maxCharacters`; the limit matches the width ceiling), no action.
/// Longer or with a button — that's a toast (`VoiceErrorToastController`), which has room and a click.
/// Otherwise the two surfaces grow toward each other, and a status cut mid-word reads like debug output.
///
/// Non-interactive on purpose: the badge window ignores the mouse (`ignoresMouseEvents`), otherwise the
/// click with which the user returns to work is eaten by the badge (so there is no "click to close").
struct BadgeView: View {

    /// The contract limit lives in `BadgeText` — next to the strings themselves and where the
    /// unit test checks it. Duplicating the number in the view is not allowed: it would drift.
    static let maxCharacters = BadgeText.maxCharacters

    enum Kind: Equatable {
        case info       // normal message
        case warning    // didn't do what was asked
        case progress   // working, please wait

        /// The kind is encoded by SHAPE, not only by color: info and progress differed by just a
        /// pulse, and with "reduce motion" the animation is off — so the difference literally
        /// disappeared in the real product.
        var symbol: String {
            switch self {
            case .info:     return "checkmark"
            case .warning:  return "exclamationmark.triangle.fill"
            case .progress: return "hourglass"
            }
        }

        var tint: Color {
            switch self {
            case .info:     return Theme.Colors.success
            case .warning:  return Theme.Colors.warning
            case .progress: return Theme.Colors.fgMuted
            }
        }

        /// Status line above the text: answers "did it work or not" before the reason is read.
        /// A catalog key — the title is translated along with everything else.
        var titleKey: String {
            switch self {
            case .info:     return "badge.kind.done"
            case .warning:  return "badge.kind.failed"
            case .progress: return "badge.kind.working"
            }
        }
    }

    let text: String
    let kind: Kind
    /// `true` in snapshot mode: `ImageRenderer` doesn't capture live animations, the spinner would
    /// come out as a random frame — so a static symbol is drawn.
    var snapshot: Bool = false
    /// `false` when the caller provides the shadow margin (the QA exporter adds its own padding).
    var insetForShadow: Bool = true

    var body: some View {
        // A CAPSULE in the style of the dictation badge — the same look as the toast.
        //
        // This is the surface that users perceive as a toast: "No speech heard" comes as a badge
        // (`showBadge(BadgeText.nothingHeard)`), not a toast. The old look had a 17pt icon, an
        // all-caps "FAILED" title and text — three levels of styling for one phrase.
        //
        // There is NO title anymore, and not only for quietness: "FAILED" also appeared above
        // normal outcomes like "text on clipboard" — i.e. it shouted failure where everything
        // worked. The state is now carried by a colored dot, like the toast's.
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Circle()
                .fill(kind.tint)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.fg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(
            Capsule()
                .fill(Theme.Elevation.fill)
                .shadow(color: .black.opacity(Theme.Elevation.pillShadowOpacity),
                        radius: Theme.Elevation.pillShadowRadius,
                        y: Theme.Elevation.pillShadowY)
                .shadow(color: .black.opacity(Theme.Elevation.pillContactOpacity),
                        radius: Theme.Elevation.pillContactRadius,
                        y: Theme.Elevation.pillContactY)
        )
        .fixedSize()
        .padding(insetForShadow ? Theme.Elevation.pillShadowMargin : 0)
    }

    /// Fixed-width slot: otherwise the plate jitters horizontally when the kind changes
    /// (symbols of different widths), while the "Fixing… → No errors found" transition should happen in place.
    @ViewBuilder
    private var indicator: some View {
        Group {
            if kind == .progress && !snapshot {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: kind.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 14, height: 14)
            }
        }
        // Align to the first line of text, not the plate center, and to the middle of the x-height,
        // not under the baseline — otherwise the indicator reads as a "dropped" punctuation mark.
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
    }
}

// gate probe
