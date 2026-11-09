import SwiftUI

/// Badge variants gallery — a DEBUG tool for choosing the badge style.
///
/// The badge is the only carrier of a refusal reason: it lives five seconds near the screen
/// edge, and the user either reads it or never learns why the operation didn't happen. The
/// current look was deemed poor, and a visual choice like this is judged by eye, not by
/// description.
///
/// Rendered with `KEYLY_BADGE_VARIANTS=1` into separate PNGs; not part of the product path.
enum BadgeVariant: String, CaseIterable {
    /// Current look: 14pt, thin plate, dot indicator on the left.
    case current
    /// Bigger and denser: 15pt semibold, more padding, a noticeable shadow.
    case bold
    /// A state icon instead of the dot and a status title above the text.
    case titled
    /// Compact "pill" with a colored left edge by state type.
    case pill

    var title: String {
        switch self {
        case .current: return "1 · сейчас"
        case .bold:    return "2 · крупнее"
        case .titled:  return "3 · с заголовком"
        case .pill:    return "4 · пилюля"
        }
    }
}

struct BadgeVariantPreview: View {
    let variant: BadgeVariant
    let text: String
    let kind: BadgeView.Kind

    var body: some View {
        switch variant {
        case .current: currentBadge
        case .bold:    boldBadge
        case .titled:  titledBadge
        case .pill:    pillBadge
        }
    }

    private var tint: Color {
        switch kind {
        case .warning:  return Theme.Colors.warning
        case .info:     return Theme.Colors.accent
        case .progress: return Theme.Colors.fgMuted
        }
    }

    private var symbol: String {
        switch kind {
        case .warning:  return "exclamationmark.triangle.fill"
        case .info:     return "checkmark.circle.fill"
        case .progress: return "hourglass"
        }
    }

    private var currentBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.Colors.fg)
        }
        .padding(.leading, 10)
        .padding(.trailing, Theme.Space.m)
        .padding(.vertical, Theme.Space.m)
        .background(plate)
    }

    private var boldBadge: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.Colors.fg)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(plate)
    }

    private var titledBadge: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Text(text).font(.system(size: 14)).foregroundStyle(Theme.Colors.fg)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(plate)
    }

    private var pillBadge: some View {
        HStack(spacing: 10) {
            Rectangle().fill(tint).frame(width: 3)
            Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.Colors.fg)
                .padding(.trailing, 18)
                .padding(.vertical, 13)
        }
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var kindTitle: String {
        switch kind {
        case .warning:  return "не вышло"
        case .info:     return "готово"
        case .progress: return "работаю"
        }
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .fill(Theme.Colors.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Colors.border, lineWidth: 1))
    }
}

/// Sheet with all variants on one background — that's how they are compared.
struct BadgeVariantsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(BadgeVariant.allCases, id: \.self) { variant in
                VStack(alignment: .leading, spacing: 9) {
                    Text(variant.title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.fgDim)
                    HStack(alignment: .top, spacing: 14) {
                        BadgeVariantPreview(variant: variant,
                                            text: "Нет текстового поля", kind: .warning)
                        BadgeVariantPreview(variant: variant,
                                            text: "Исправляю…", kind: .progress)
                        BadgeVariantPreview(variant: variant,
                                            text: "Ошибок не найдено", kind: .info)
                    }
                }
            }
        }
        .padding(34)
        .background(Color.black)
    }
}
