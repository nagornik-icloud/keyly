#if DEBUG
import SwiftUI

/// One QA catalog entry: file name (=id) + render width + the content itself.
/// The catalog is the EXECUTABLE part of the visual inventory (`docs/qa/visual-inventory.md`):
/// every entry deterministically becomes a PNG for visual checks.
struct QACatalogEntry {
    let id: String
    let title: String
    var width: CGFloat = 560
    var padding: CGFloat = Theme.Space.xl
    let content: AnyView
}

/// Full list of screens/states that must be captured.
/// Pilot: the hero component (API key row) in all states + transient overlays
/// (recording indicator, toasts). Grows as other screens get covered.
@MainActor
enum QACatalog {
    static var entries: [QACatalogEntry] {
        apiKeyRows + voiceIndicators + toasts + badges + wizardSteps + palette
            + disclosureHeaders + bareKeyNotices + launcherRowJump + snippetFooterJump
            + cheatsheets
    }

    // MARK: - Launcher row: the hotkey field must not jump

    /// The same row WITHOUT and WITH the message.
    ///
    /// A class of defect a single frame can never catch: the problem isn't how a state looks,
    /// but that something MOVES between two states that shouldn't. Judged by diffing two
    /// frames, not by looking at one.
    private static var launcherRowJump: [QACatalogEntry] {
        [(false, "quiet"), (true, "notice")].map { withNotice, suffix in
            QACatalogEntry(
                id: "launcher-row-\(suffix)",
                title: "Строка лаунчера — \(withNotice ? "с предупреждением" : "спокойная")",
                width: 620,
                content: AnyView(LauncherRowJumpProbe(withNotice: withNotice))
            )
        }
    }

    /// Snippet editor footer in two states — the second suspected jump.
    private static var snippetFooterJump: [QACatalogEntry] {
        [(false, "quiet"), (true, "notice")].map { withNotice, suffix in
            QACatalogEntry(
                id: "snippet-footer-\(suffix)",
                title: "Подвал сниппета — \(withNotice ? "с предупреждением" : "спокойный")",
                width: 620,
                content: AnyView(SnippetFooterJumpProbe(withNotice: withNotice))
            )
        }
    }

    // MARK: - Hotkey cheatsheet

    /// The cheatsheet popup in all states.
    ///
    /// It used to be captured by NOTHING: neither a product frame (it's an overlay, not a screen)
    /// nor the gallery. So the surface people invoke more often than any screen had never been
    /// checked at all.
    ///
    /// The states differ in MEANING, not in row count: empty (nothing assigned), typical, and
    /// HOSTILE — long user names and wide combos, where the 92pt column and `lineLimit(1)` show
    /// their real cost.
    private static var cheatsheets: [QACatalogEntry] {
        let typical: [CheatsheetView.Row] = [
            // The combo comes from a REAL `KeyCombo`, not typed in as a string.
            //
            // A hand-typed fixture freezes and starts lying: this used to say "Grave" — a word users
            // found meaningless ("it's just a tilde"). The product dropped it long ago
            // (`KeyCombo.lowInkKeyNames` gives "~"), yet the cheatsheet frame still showed it and passed
            // acceptance — while the comment next to it claimed the fixture was "as in the product".
            .init(combo: KeyCombo(keyCode: 50, modifiers: []).description, title: "Раскладка"),
            .init(combo: "F3", title: "Исправление опечаток"),
            .init(combo: "F5", title: "Голос"),
            .init(combo: "⌥⌘Z", title: "Отменить последнее действие"),
            .init(combo: "⌥⌘S", title: "Палитра сниппетов"),
            .init(combo: "⌥⌘/", title: "Шпаргалка по хоткеям"),
            .init(combo: "⌥⌘4", title: "Перевод на русский"),
            .init(combo: "F4", title: "Claude"),
            .init(combo: "F7", title: "Telegram"),
            .init(combo: "⇧3", title: "Новый сниппет"),
        ]
        let hostile: [CheatsheetView.Row] = [
            .init(combo: "⌃⌥⇧⌘F12", title: "Переписать письмо для клиента вежливым тоном"),
            .init(combo: "⌥⌘/", title: "Шпаргалка по хоткеям"),
            .init(combo: "F1", title: "Запуск приложения с очень длинным именем.app"),
            .init(combo: "F5", title: "Голос"),
        ]
        return [
            QACatalogEntry(id: "cheatsheet-1-typical", title: "Шпаргалка — типичная",
                           width: 460, padding: Theme.Space.l,
                           content: AnyView(CheatsheetView(rows: typical, snapshot: true))),
            QACatalogEntry(id: "cheatsheet-2-hostile", title: "Шпаргалка — длинные имена",
                           width: 460, padding: Theme.Space.l,
                           content: AnyView(CheatsheetView(rows: hostile, snapshot: true))),
            QACatalogEntry(id: "cheatsheet-3-empty", title: "Шпаргалка — пусто",
                           width: 460, padding: Theme.Space.l,
                           content: AnyView(CheatsheetView(rows: [], snapshot: true))),
        ]
    }

    // MARK: - Bare key warning

    /// A TRANSIENT state: lives from assignment until leaving the screen.
    ///
    /// This entry exists because of it. A first fix removed the warning entirely — the complaint
    /// was about the REPEATED yellow line, but the fact itself got removed, and users stopped
    /// learning that "]" no longer types anywhere. The defect survived until a later gate because
    /// no static frame captured this state: it wasn't in the catalog.
    ///
    /// Three texts are three DIFFERENT rules, not three examples: a regular printable character,
    /// a system key with a macOS action name, and a key that prints nothing (F-row). All three
    /// used to get "will stop typing" — which is untrue for F3.
    private static var bareKeyNotices: [QACatalogEntry] {
        // The substitution is REQUIRED: the product passes either a macOS action name or a key
        // name here (`reason.actionKey?.loc ?? combo.description`). The first frame of this entry
        // printed a raw "%@" — the catalog called `.loc` without an argument and diverged from the
        // real call. A transient state is useful precisely because such divergences show only in
        // the frame.
        //
        // The fourth entry is NOT for completeness: F3 used to be the example of the generic branch,
        // but now it names Mission Control — and the frame must show exactly that, otherwise the
        // gallery illustrates behavior that no longer exists. The generic-branch example is one that
        // really has no macOS action.
        let cases: [(String, String)] = [
            ("character", "hotkey.bare.character".loc("]")),
            ("system", "hotkey.bare.system".loc("key.action.volume".loc)),
            ("mission-control", "hotkey.bare.system".loc("key.action.missionControl".loc)),
            ("action", "hotkey.bare.action".loc("⎋")),
        ]
        return cases.map { suffix, message in
            QACatalogEntry(
                id: "bare-key-notice-\(suffix)",
                title: "Голая клавиша — \(suffix)",
                width: 420,
                content: AnyView(BareKeyNoticeView(message: message))
            )
        }
    }

    // MARK: - Disclosure section headers

    /// Buttons in ALL states, including NESTED dimming.
    ///
    /// A disabled button is dimmed to 0.4; an "inapplicable setting" block is dimmed by the same.
    /// A button inside such a block gets 0.4 × 0.4 = 0.16 — exactly the live case ("Download"
    /// inside the local model block when the mode is cloud). This can't be judged by numbers,
    /// it needs a frame — otherwise a style fix repairs one case and breaks the neighbour.
    /// The wave at DIFFERENT input levels — from silence to shouting.
    ///
    /// Key requirement: on background noise the wave must be a FLAT LINE, and move only on
    /// voice. A single "recording" frame can't check this at all: the fixture is always captured
    /// at one level, and the difference between silence and speech never gets into it. So the
    /// levels are captured side by side in one frame.
    private static var waveLevels: [QACatalogEntry] {
        let levels: [(String, Float)] = [
            ("тишина / шум комнаты", 0),
            ("тихая речь", 0.27),
            ("обычная речь", 0.6),
            ("громко", 1.0),
        ]
        return [QACatalogEntry(id: "wave-levels", title: "wave-levels", width: 460, content: AnyView(
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(levels, id: \.0) { name, level in
                    HStack(spacing: Theme.Space.l) {
                        Text(name)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                            .frame(width: 150, alignment: .leading)
                        VoiceWave(mode: .live(level))
                    }
                }
            }
        ))]
    }

    private static var buttonStates: [QACatalogEntry] {
        func row(_ id: String, _ content: AnyView) -> QACatalogEntry {
            QACatalogEntry(id: id, title: id, width: 520, content: content)
        }
        return [
            row("button-1-enabled", AnyView(
                HStack(spacing: Theme.Space.m) {
                    Button("Далее") {}.buttonStyle(KeylyPrimaryButtonStyle())
                    Button("Назад") {}.buttonStyle(KeylySecondaryButtonStyle())
                }
            )),
            row("button-2-disabled", AnyView(
                HStack(spacing: Theme.Space.m) {
                    Button("Далее") {}.buttonStyle(KeylyPrimaryButtonStyle()).disabled(true)
                    Button("Проверить") {}.buttonStyle(KeylySecondaryButtonStyle()).disabled(true)
                }
            )),
            row("button-3-disabled-in-inapplicable", AnyView(
                HStack(spacing: Theme.Space.m) {
                    Text("Модель не скачана")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgMuted)
                    Spacer(minLength: Theme.Space.m)
                    Button("Скачать") {}.buttonStyle(KeylySecondaryButtonStyle())
                }
                .keylyInapplicable(when: true, reason: "Управление моделью — только в локальном режиме")
            )),
        ]
    }

    /// The "Advanced" and "Microphone, pill, language" headers live BELOW the window fold and
    /// never get into screen frames — yet they were the ones reported (only the chevron was
    /// clickable, and it sat right against the text). Since the surface isn't visible in screen
    /// frames, it must be in the component catalog: otherwise a fix ships blind.
    private static var disclosureHeaders: [QACatalogEntry] {
        [(id: "disclosure-1-collapsed", title: "Дополнительно", expanded: false),
         (id: "disclosure-2-expanded",  title: "Дополнительно", expanded: true),
         (id: "disclosure-3-voice",     title: "МИКРОФОН, ПЛАШКА, ЯЗЫК", expanded: false)]
            .map { spec in
                QACatalogEntry(id: spec.id, title: spec.id, width: 560, content: AnyView(
                    // Card-colored backing: the FULL row width is clickable, and the frame must show that
                    // the target is the row, not the icon.
                    Color.clear
                        .frame(height: 0)
                        .keylyDisclosureHeader(title: spec.title,
                                               isExpanded: .constant(spec.expanded))
                        .background(Theme.Colors.surface)
                ))
            } + buttonStates + waveLevels
    }

    // MARK: - API key row (hero) — all states on edge-case fixtures

    private static let sampleKey = "sk-proj-AbCdEf0123456789AbCdEf0123456789AbCdEf01xyz"

    private static func keyRow(
        _ id: String,
        name: String,
        value: String,
        validation: ValidationState,
        selected: Bool
    ) -> QACatalogEntry {
        QACatalogEntry(
            id: id,
            title: id,
            content: AnyView(
                APIKeyRowView(
                    name: .constant(name),
                    keyValue: .constant(value),
                    validation: validation,
                    isSelected: selected,
                    snapshot: true,
                    // The selected key MUST have consumers: "Active" means it is assigned to modules.
                    // `usedIn` used to stay empty by default, and the happy-path frame showed an IMPOSSIBLE
                    // state — "Active" on the right and "not used" under the key mask, two mutually exclusive
                    // answers about one entity. It was taken for a product defect and a whole pass was spent
                    // chasing a ghost.
                    usedIn: selected ? ["Опечатки", "Голос"] : []
                )
            )
        )
    }

    private static var apiKeyRows: [QACatalogEntry] {
        [
            keyRow("apikey-01-selected-ok",        name: "my openai",  value: sampleKey, validation: .success,  selected: true),
            keyRow("apikey-02-unselected-unknown", name: "work key",   value: sampleKey, validation: .unknown,  selected: false),
            keyRow("apikey-03-checking",           name: "personal",   value: sampleKey, validation: .checking, selected: false),
            keyRow("apikey-04-failure",            name: "old key",    value: sampleKey, validation: .failure(.rejected),  selected: false),
            keyRow("apikey-05-longname",           name: "Мой основной рабочий ключ для исправления опечаток и диктовки голосом", value: sampleKey, validation: .success, selected: true),
            keyRow("apikey-06-empty-value",        name: "новый ключ", value: "",        validation: .unknown,  selected: false),
            keyRow("apikey-07-gemini-selected-ok", name: "gemini main", value: sampleKey, validation: .success, selected: true),
        ]
    }

    // MARK: - Recording indicator (transient overlay)

    private static func indicator(_ id: String, _ state: RealtimeVoiceSession.State,
                                  phase: VoiceOverlayPhase = .recording) -> QACatalogEntry {
        let overlay = VoiceOverlayState()
        overlay.phase = phase
        return QACatalogEntry(
            id: id,
            title: id,
            width: 440,
            content: AnyView(
                RealtimeIndicatorView(
                    session: .previewMock(level: 0.6, state: state),
                    elapsedProvider: { 7 },
                    showTimer: true,
                    state: overlay
                )
            )
        )
    }

    private static var voiceIndicators: [QACatalogEntry] {
        let batch = VoiceOverlayState()
        let batchProcessing = VoiceOverlayState()
        batchProcessing.phase = .processing
        let batchCopied = VoiceOverlayState()
        batchCopied.phase = .copied
        return [
            indicator("voice-01-connecting", .connecting),
            indicator("voice-02-recording",  .recording),
            indicator("voice-03-finalizing", .finalizing),
            // The "processing" phase after stop — the reason the pill now outlives the recording.
            // Capture BOTH modes: batch and streaming.
            indicator("voice-04-processing-live", .recording, phase: .processing),
            QACatalogEntry(
                id: "voice-05-batch-recording", title: "voice-05-batch-recording", width: 440,
                content: AnyView(VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {},
                                                    state: batch))
            ),
            QACatalogEntry(
                id: "voice-06-batch-processing", title: "voice-06-batch-processing", width: 440,
                content: AnyView(VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {},
                                                    state: batchProcessing))
            ),
            // Final beat after paste when "copy to clipboard" is on.
            QACatalogEntry(
                id: "voice-07-batch-copied", title: "voice-07-batch-copied", width: 440,
                content: AnyView(VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {},
                                                    state: batchCopied))
            ),
        ] + pillOverBackdrops
    }

    /// The pill over REAL backdrops — same discipline as the badge.
    ///
    /// A blind spot: all pill frames were captured on synthetic #070707, where a black shadow is
    /// physically invisible and the #141414 fill almost merges with the background. Yet the pill
    /// LIVES over other apps' windows — a white document, a dark editor, a colored window — and
    /// nobody had seen how it reads on a white page. A plate's contrast can't be judged from a
    /// frame on its own background.
    private static var pillOverBackdrops: [QACatalogEntry] {
        let backdrops: [(String, Color)] = [
            ("on-white",  Color.white),
            ("on-editor", Color(hex: 0x1E1E1E)),
            ("on-color",  Color(hex: 0x2D4A7C)),
        ]
        return backdrops.flatMap { suffix, backdrop -> [QACatalogEntry] in
            let recording = VoiceOverlayState()
            let processing = VoiceOverlayState()
            processing.phase = .processing
            let copied = VoiceOverlayState()
            copied.phase = .copied
            return [("recording", recording), ("processing", processing), ("copied", copied)].map { phase, state in
                QACatalogEntry(
                    id: "pill-\(suffix)-\(phase)", title: "pill-\(suffix)-\(phase)",
                    width: 480, padding: 0,
                    content: AnyView(
                        ZStack {
                            backdrop
                            VoiceRecordingView(elapsedProvider: { 7 }, onCancel: {}, state: state)
                        }
                        .frame(height: 120)
                    )
                )
            }
        }
    }

    // MARK: - Toasts (above any apps)

    private static var toasts: [QACatalogEntry] {
        [
            QACatalogEntry(
                id: "toast-01-error",
                title: "toast-error",
                width: 480,
                content: AnyView(
                    ToastShell(tint: Theme.Colors.danger, message: "Сервер отклонил запрос — проверьте ключ и доступ к выбранной модели.")
                )
            ),
            QACatalogEntry(
                id: "toast-02-info",
                title: "toast-info",
                width: 480,
                content: AnyView(
                    ToastShell(tint: Theme.Colors.accent, message: "Пробуем другой ключ OpenAI…")
                )
            ),
        ]
    }

    // MARK: - Caret badges

    private static var badges: [QACatalogEntry] {
        // The texts are REAL, the same the product shows (contract: ≤40 characters, one line).
        // Texts come FROM THE PRODUCT (`BadgeText`), not retyped here as strings: a copy would
        // silently drift from the screen, and the frame being judged would not be what users see.
        let states: [(String, String, BadgeView.Kind)] = [
            ("badge-info",        "Ошибок не найдено",             .info),
            ("badge-warning",     "Нет поля ввода — текст в буфере", .warning),
            ("badge-progress",    "Исправляю…",                    .progress),
            ("badge-short",       "Готово",                        .info),
            // Recording refusals. They used to be missing from the catalog — the states where users
            // most often get stuck were never captured.
            ("badge-mic-denied",  BadgeText.micDenied,             .warning),
            ("badge-mic-unavail", BadgeText.micUnavailable,        .warning),
            ("badge-rec-failed",  BadgeText.recordFailed,          .warning),
            ("badge-nothing",     BadgeText.nothingHeard,          .warning),
            // The model answered instead of editing; the guard returned the user's text.
            // Required in the catalog: users see this state exactly when the product saved their
            // text, and it must tell them nothing was lost.
            ("badge-answered",    BadgeText.polishAnswered,        .warning),
        ]
        let plain = states.map { id, text, kind in
            QACatalogEntry(
                id: id, title: id, width: 400, padding: 0,
                content: AnyView(BadgeView(text: text, kind: kind, snapshot: true))
            )
        }
        // The badge NEVER sits over the app's own background — it is over another window. Judging
        // its weight, shadow and contrast from a frame on #0E0E10 is not a check but a missing
        // artifact. Three real backdrops: a white document, a dark editor, a colored window.
        let backdrops: [(String, Color)] = [
            ("on-white",  Color.white),
            ("on-editor", Color(hex: 0x1E1E1E)),
            ("on-color",  Color(hex: 0x2D4A7C)),
        ]
        let overBackdrops = backdrops.map { suffix, backdrop in
            QACatalogEntry(
                id: "badge-\(suffix)", title: "badge-\(suffix)", width: 400, padding: 0,
                content: AnyView(
                    ZStack {
                        backdrop
                        BadgeView(text: "Нет поля ввода — текст в буфере", kind: .warning, snapshot: true)
                    }
                    .frame(height: 120)
                )
            )
        }
        return plain + overBackdrops
    }


    // `stats-*` entries were REMOVED. They drew their own layout — big numbers with
    // "layouts" / "snippets" labels — while the product keeps stats in one quiet line, and those
    // labels are marked in `OnboardingView+Overview` as MISLEADING and replaced. The frame showed
    // a rollback the product doesn't have.
    //
    // Class: a catalog entry outlived the component it captured. Such a frame is not just
    // useless — it poisons every later check, because it gets judged as if it were the product.
    // Stats are captured by the live frame `screen-01-overview`.

    // MARK: - Wizard steps

    private static var wizardSteps: [QACatalogEntry] {
        // The wizard is the FIRST thing a new user sees, so its steps must be in the frames.
        // Permissions are captured in BOTH states: "not granted" (with a disabled button and an
        // explanation) — what people actually see — and "granted", which checks that the screen
        // doesn't fall apart when the "Open Settings" buttons disappear.
        [
            ("wizard-1-hello", WizardStepPreview.hello),
            ("wizard-2-permissions-empty", WizardStepPreview.permissionsDenied),
            ("wizard-2-permissions-granted", WizardStepPreview.permissionsGranted),
            ("wizard-4-hotkeys", WizardStepPreview.hotkeys),
            ("wizard-5-done", WizardStepPreview.done),
        ].map { id, preview in
            QACatalogEntry(id: id, title: id, width: 620, padding: 0,
                           content: AnyView(WizardStepPreview.view(preview)))
        }
    }


    // MARK: - Snippet palette

    private static var palette: [QACatalogEntry] {
        let sample = [
            Snippet(name: "Почта", content: "user@example.com", triggers: ["@@", "почта"]),
            Snippet(name: "", content: "С уважением,\nАнтон", triggers: ["подпись"]),
            Snippet(name: "Адрес офиса", content: "Москва, ул. Ленина, 1, офис 42, 3-й этаж, вход со двора", triggers: ["адр"]),
            Snippet(name: "Реквизиты", content: "ИНН 1234567890 · КПП 987654321 · р/с 40702810…", triggers: []),
        ]
        // Hostile fixtures: empty query (what's visible at once), a narrowing query, a miss, and no
        // snippets at all — four states where the palette looks different.
        let cases: [(String, [Snippet], String)] = [
            ("palette-1-all", sample, ""),
            ("palette-2-query", sample, "адр"),
            ("palette-3-nothing", sample, "телефон"),
            ("palette-4-empty", [], ""),
        ]
        return cases.map { id, list, query in
            QACatalogEntry(id: id, title: id, width: 800, padding: Theme.Space.l,
                           content: AnyView(
                               SnippetPaletteView(snippets: list, onPick: { _ in }, onCancel: {},
                                                  snapshot: true, snapshotQuery: query)
                                   // Size is the same as the live palette window (see the controller):
                                   // a frame of a different width judges a layout that doesn't exist.
                                   .frame(width: 760, height: 400)
                           ))
        }
    }

}
#endif
