import SwiftUI

/// Gallery of TOAST and RECORDING PILL variants — a DEBUG tool for choosing the style.
///
/// Both surfaces live over other apps' windows for a few seconds, and judging them by
/// description is pointless: "nice or not" is decided by eye. The current look was deemed
/// unsuccessful, and the variants are needed at different content volumes — so each variant
/// is drawn with a short line, a long one, with an action and without.
///
/// Rendered with `KEYLY_SURFACE_VARIANTS=1` into a separate PNG; not part of the product path.

// MARK: - Toasts

// Gallery strings are `verbatim` on purpose: this is a DEBUG tool, and its labels must not
// end up in the localization catalog — Xcode extracts bare literals and creates stub entries
// for them, which then fail the "no untranslated entries in the catalog" gate.
enum ToastVariant: String, CaseIterable {
    /// Current look: icon square on the left, title, text, action label.
    case current
    /// Single-line pill: icon and text in a row, action as a link on the right.
    /// Grows downward ONLY when the text doesn't fit.
    case pill
    /// Colored left edge instead of the icon square, no title — larger text.
    case edge
    /// Dark card without an icon: status in small caps, large text, action as a button.
    case card

    var title: String {
        switch self {
        case .current: return "1 · сейчас"
        case .pill:    return "2 · пилюля"
        case .edge:    return "3 · цветная кромка"
        case .card:    return "4 · карточка"
        }
    }
}

struct ToastVariantPreview: View {
    let variant: ToastVariant
    let message: String
    let action: String?
    let isError: Bool

    private var tint: Color { isError ? Theme.Colors.danger : Theme.Colors.accent }
    private var icon: String { isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }
    private var statusTitle: String { isError ? "Не получилось" : "Keyly" }

    var body: some View {
        switch variant {
        case .current: currentToast
        case .pill:    pillToast
        case .edge:    edgeToast
        case .card:    cardToast
        }
    }

    private var currentToast: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.fg)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Text(action)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(width: 420, alignment: .leading)
        .keylyOverlayPlate(insetForShadow: false)
    }

    private var pillToast: some View {
        // The action moves BELOW the text when the text is long: beside it, it eats width and the
        // message is truncated with an ellipsis — losing exactly the refusal reason the toast is
        // shown for.
        let isLong = message.count > 40
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: isLong ? 6 : 0) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if isLong, let action {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            Spacer(minLength: Theme.Space.m)
            if !isLong, let action {
                Text(action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1))
        )
    }

    private var edgeToast: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.fg)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.Colors.border, lineWidth: 1))
    }

    private var cardToast: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusTitle.uppercased())
                .font(Theme.Typography.mono(9, .semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.fg)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Text(action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Colors.surfaceHover)
                    )
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Colors.bg)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.Colors.borderStrong, lineWidth: 1))
        )
    }
}

// MARK: - Recording pill

enum PlateVariant: String, CaseIterable {
    /// Current look: title, large timer, cancel button.
    case current
    /// Row: dot, timer, esc label. The smallest footprint on screen.
    case line
    /// Row with a live wave between the dot and the timer.
    case wave
    /// "Drop" pill with a large timer and a wave, no words.
    case drop

    var title: String {
        switch self {
        case .current: return "1 · сейчас"
        case .line:    return "2 · строка"
        case .wave:    return "3 · строка с волной"
        case .drop:    return "4 · капля"
        }
    }
}

struct PlateVariantPreview: View {
    let variant: PlateVariant
    /// Levels for the wave. Static — the frame shows the look, not motion.
    private let levels: [CGFloat] = [0.25, 0.55, 0.35, 0.8, 0.45, 0.65, 0.3, 0.7, 0.4, 0.5]

    var body: some View {
        switch variant {
        case .current: currentPlate
        case .line:    linePlate
        case .wave:    wavePlate
        case .drop:    dropPlate
        }
    }

    private var currentPlate: some View {
        VStack(spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                Circle().fill(Theme.Colors.recording).frame(width: 8, height: 8)
                Text(verbatim: "Записываю")
                    .font(Theme.Typography.title(15))
                    .foregroundStyle(Theme.Colors.fg)
            }
            Text(verbatim: "0:07")
                .font(Theme.Typography.mono(30, .semibold))
                .foregroundStyle(Theme.Colors.fg)
            Text(verbatim: "Отмена")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fg)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Colors.surfaceHover)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1))
                )
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .frame(width: 280)
        .keylyOverlayPlate(insetForShadow: false)
    }

    private var linePlate: some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(Theme.Colors.recording).frame(width: 7, height: 7)
            Text(verbatim: "0:07")
                .font(Theme.Typography.mono(12, .semibold))
                .foregroundStyle(Theme.Colors.fg)
            Text(verbatim: "esc")
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 7)
        .keylyOverlayPlate(insetForShadow: false)
    }

    private var wavePlate: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.Colors.recording).frame(width: 7, height: 7)
            waveform(height: 14, barWidth: 2)
            Text(verbatim: "0:07")
                .font(Theme.Typography.mono(12, .semibold))
                .foregroundStyle(Theme.Colors.fg)
                .monospacedDigit()
            Text(verbatim: "esc")
                .font(Theme.Typography.mono(10))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .keylyOverlayPlate(insetForShadow: false)
    }

    private var dropPlate: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.Colors.recording).frame(width: 9, height: 9)
            waveform(height: 20, barWidth: 3)
            Text(verbatim: "0:07")
                .font(Theme.Typography.mono(17, .semibold))
                .foregroundStyle(Theme.Colors.fg)
                .monospacedDigit()
                // Without this the text wraps per character and the timer stacks into a column, and the
                // capsule collapses into a circle: the pill has no set width and takes whatever its
                // neighbours offer.
                .fixedSize()
        }
        .fixedSize()
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Theme.Colors.bg)
                .overlay(Capsule().stroke(Theme.Colors.borderStrong, lineWidth: 1))
        )
    }

    private func waveform(height: CGFloat, barWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.Colors.fgMuted)
                    .frame(width: barWidth, height: max(3, height * level))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Gallery sheet

struct SurfaceVariantsSheet: View {
    /// Three content volumes: that's where the variants diverge. A short message makes the big
    /// card empty, a long one breaks the single-line pill — this can only be seen side by side.
    private let cases: [(String, String?, Bool)] = [
        ("Текст в буфере", nil, false),
        ("Нет подключения к интернету", "Открыть настройки", true),
        ("Микрофон не отдаёт звук: он занят другой программой или выбран не тот вход.",
         "Открыть настройки звука", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header("ТОСТЫ — четыре варианта на трёх объёмах текста")
            ForEach(ToastVariant.allCases, id: \.rawValue) { variant in
                VStack(alignment: .leading, spacing: 10) {
                    Text(variant.title)
                        .font(Theme.Typography.mono(11, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
                        ToastVariantPreview(variant: variant, message: item.0,
                                            action: item.1, isError: item.2)
                    }
                }
            }

            header("ПЛАШКА ЗАПИСИ — четыре варианта, реальный размер")
            HStack(alignment: .top, spacing: 24) {
                ForEach(PlateVariant.allCases, id: \.rawValue) { variant in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(variant.title)
                            .font(Theme.Typography.mono(11, .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                        PlateVariantPreview(variant: variant)
                    }
                }
            }
        }
        .padding(36)
        .background(Theme.Colors.bg)
        .environment(\.colorScheme, .dark)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.mono(12, .semibold))
            .foregroundStyle(Theme.Colors.fgMuted)
    }
}
