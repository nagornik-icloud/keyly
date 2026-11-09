#if DEBUG
import SwiftUI

/// Showcase of transient overlays (recording indicator + toasts) for VISUAL checks.
/// Shown only when launched with env `KEYLY_GALLERY=1`; not part of the real flow.
/// Lets you judge how these pills fit the design system without triggering
/// a real recording or real errors.
struct DesignGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                group("Индикатор записи · состояния") {
                    indicatorRow(.connecting, "connecting → спиннер")
                    indicatorRow(.recording, "recording → точка + живая волна + таймер")
                    indicatorRow(.finalizing, "finalizing → «Обработка…»")
                }
                group("Тосты (поверх любых приложений)") {
                    ToastShell(tint: Theme.Colors.danger, message: "Модель «gpt-5.5» недоступна для этого ключа. Выберите другую в настройках.")
                        .frame(width: 420)
                    ToastShell(tint: Theme.Colors.danger, message: "Текст вставлен в активное поле.")
                        .frame(width: 420)
                }
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionLabel(text: title)
            content()
        }
    }

    private func indicatorRow(_ state: RealtimeVoiceSession.State, _ caption: String) -> some View {
        HStack(spacing: Theme.Space.l) {
            RealtimeIndicatorView(
                session: .previewMock(level: 0.6, state: state),
                elapsedProvider: { 7 },
                showTimer: true,
                state: VoiceOverlayState()
            )
            Text(caption)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.fgMuted)
        }
    }
}
#endif
