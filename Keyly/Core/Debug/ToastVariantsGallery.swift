#if DEBUG
import SwiftUI

/// Toast variants gallery: the toast design needed a redo, in the style of the dictation pill.
///
/// A design choice is judged BY EYE, not by description, so the variants are drawn on a REAL
/// backdrop — the toast hangs over another window, and judging it on its own background is
/// pointless.
///
/// Run: `KEYLY_TOAST_VARIANTS=1` → `.qa-shots/toast-variants.png`.
struct ToastVariantsSheet: View {
    private let sample = "Не слышно речи — говорите громче"
    private let long = "Сервер отклонил запрос — проверьте ключ и доступ к выбранной модели"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("Варианты тоста — в стиле пилюли: тёмная заливка, без светлой обводки, мягкая тень")
                .font(Theme.Typography.title(15))
                .foregroundStyle(Theme.Colors.fg)
            Text("Каждый вариант показан на СВЕТЛОМ документе и на ТЁМНОМ редакторе — тост висит над чужим окном.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)

            variant("A · Капсула", "Ровно пилюля: точка состояния, одна строка, ширина по тексту. Без действия.") {
                AnyView(ToastVariantA(message: sample, tint: Theme.Colors.warning))
            }
            variant("B · Капсула с действием", "Та же капсула, действие — отдельным чипом справа.") {
                AnyView(ToastVariantB(message: sample, tint: Theme.Colors.danger, action: "Настройки"))
            }
            variant("C · Капсула с иконкой", "Иконка вместо точки: тип отказа виден до чтения текста.") {
                AnyView(ToastVariantC(message: sample, icon: "mic.slash.fill", tint: Theme.Colors.warning))
            }
            variant("D · Плита на две строки", "Для длинных причин: тот же язык, но текст не жмётся в одну строку.") {
                AnyView(ToastVariantD(message: long, tint: Theme.Colors.danger, action: "Открыть настройки"))
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 1000)
        .background(Theme.Colors.bg)
    }

    /// One variant on TWO backdrops side by side: a light document on the left, a dark editor on the right.
    @ViewBuilder
    private func variant(_ title: String, _ note: String,
                         @ViewBuilder content: @escaping () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(Theme.Typography.mono(13, .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text(note)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.fgMuted)
            HStack(spacing: 0) {
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xl)
                    .background(Color(hex: 0xF2F2F2))
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xl)
                    .background(Color(hex: 0x1E1E1E))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}

// MARK: - Variants

/// Shared shell: the same capsule as the dictation pill — fill, no stroke, soft shadow.
private struct PillPlate<Content: View>: View {
    var radius: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background {
                let fill = Theme.Elevation.fill
                if let radius {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                } else {
                    Capsule().fill(fill)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(Theme.Elevation.pillShadowOpacity),
                    radius: Theme.Elevation.pillShadowRadius,
                    y: Theme.Elevation.pillShadowY)
            .shadow(color: .black.opacity(Theme.Elevation.pillContactOpacity),
                    radius: Theme.Elevation.pillContactRadius,
                    y: Theme.Elevation.pillContactY)
    }
}

struct ToastVariantA: View {
    let message: String
    let tint: Color
    var body: some View {
        PillPlate {
            HStack(spacing: Theme.Space.m) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize()
            }
        }
    }
}

struct ToastVariantB: View {
    let message: String
    let tint: Color
    let action: String
    var body: some View {
        PillPlate {
            HStack(spacing: Theme.Space.m) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize()
                Text(action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .fixedSize()
            }
        }
    }
}

struct ToastVariantC: View {
    let message: String
    let icon: String
    let tint: Color
    var body: some View {
        PillPlate {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize()
            }
        }
    }
}

struct ToastVariantD: View {
    let message: String
    let tint: Color
    let action: String
    var body: some View {
        PillPlate(radius: 18) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .frame(width: 320, alignment: .leading)
        }
    }
}
#endif
