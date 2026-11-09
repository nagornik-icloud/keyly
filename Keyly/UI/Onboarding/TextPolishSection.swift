import SwiftUI

/// The "Text processing" block — ONE for the whole app.
///
/// Replaces the pair of toggles "Split into paragraphs" and "More accurate but slower", whose
/// labels did not match the prompts: the first promised "doesn't touch words and punctuation"
/// but actually fixed spelling and brand names; the second promised brand names but invoked a
/// prompt that never mentioned them and rewrote the text entirely. Three levels = three
/// prompts, nothing to lie about.
///
/// Shown both on "Voice → text" and on "Typo fixing": they do the same thing to text, and two
/// different vocabularies for one concept is exactly the mess we are moving away from.
struct TextPolishSection: View {

    @AppStorage(SettingsKeys.textPolishLevel) private var levelRaw: String = TextPolishLevel.default.rawValue

    /// Whether a key exists. Without it the levels that call the model don't work, and by the
    /// screen rule they must say so instead of silently doing nothing.
    var hasKey: Bool = true

    /// Why the upper levels need a key. The text differs by mode: on the on-device model the
    /// user may well be surprised — transcription runs offline after all — so they must be told
    /// that it is the PROCESSING that goes to the cloud, not the recording.
    var needsKeyReason: String = "polish.needsKey".loc

    /// Note under the block: where processing goes and what it will do to already shown
    /// text. Shown ONLY on levels that actually call the model — on "As spoken" it would
    /// describe work that does not happen.
    var footnote: String?

    private var level: TextPolishLevel { TextPolishLevel(rawValue: levelRaw) ?? .default }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "polish.title".loc)
            KeylyOptionGroup(
                selection: Binding(
                    get: { TextPolishLevel(rawValue: levelRaw) ?? .default },
                    set: { levelRaw = $0.rawValue }
                ),
                options: [
                    KeylyOption(value: .verbatim,
                                title: "polish.verbatim".loc,
                                subtitle: "polish.verbatim.hint".loc),
                    KeylyOption(value: .tidy,
                                title: "polish.tidy".loc,
                                subtitle: "polish.tidy.hint".loc,
                                disabledReason: hasKey ? nil : needsKeyReason),
                    KeylyOption(value: .rewrite,
                                title: "polish.rewrite".loc,
                                subtitle: "polish.rewrite.hint".loc,
                                disabledReason: hasKey ? nil : needsKeyReason),
                ]
            )
            if let footnote, level.requiresLLM {
                Text(footnote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
