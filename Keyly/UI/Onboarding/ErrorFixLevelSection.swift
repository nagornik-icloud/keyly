import SwiftUI

/// Typo-fix strictness — the module's OWN block.
///
/// Deliberately separate from `TextPolishSection`. The typo screen used to draw the voice
/// ladder from a shared key, which caused two defects at once: the switch did not affect
/// typo fixing (the module never read it) and silently changed voice behavior. The labels
/// also talked about speech on a screen for TYPED text.
struct ErrorFixLevelSection: View {

    @AppStorage(SettingsKeys.errorFixLevel) private var levelRaw: String = ErrorFixLevel.default.rawValue

    /// Whether a key exists. All three levels call the model, so without a key all of them are
    /// disabled — and say so, instead of silently doing nothing.
    var hasKey: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "errorfix.strictness".loc)
            KeylyOptionGroup(
                selection: Binding(
                    get: { ErrorFixLevel(rawValue: levelRaw) ?? .default },
                    set: { levelRaw = $0.rawValue }
                ),
                options: ErrorFixLevel.allCases.map { level in
                    KeylyOption(value: level,
                                title: level.title,
                                subtitle: level.subtitle,
                                disabledReason: hasKey ? nil : "errorfix.needsKey".loc)
                }
            )
        }
    }
}
