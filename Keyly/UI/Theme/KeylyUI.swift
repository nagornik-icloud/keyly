import SwiftUI

// MARK: - Card

/// Dark card surface with a hairline border. The basic building block
/// of every screen (instead of assorted `.ultraThinMaterial` glass).
struct KeylyCard: ViewModifier {
    var padding: CGFloat = Theme.Space.l
    var radius: CGFloat = Theme.Radius.lg
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Colors.surface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            )
    }
}

extension View {
    func keylyCard(padding: CGFloat = Theme.Space.l, radius: CGFloat = Theme.Radius.lg) -> some View {
        modifier(KeylyCard(padding: padding, radius: radius))
    }

    /// The setting does NOT APPLY in the current mode: dim it and say WHY.
    ///
    /// General product rule: if the selected mode makes some settings irrelevant,
    /// those settings turn gray and get a caption with the reason. We do not hide
    /// them: users should learn the option exists, and a jumping
    /// screen is a defect in itself.
    ///
    /// A control that toggles and saves but changes nothing in the current mode
    /// is a phantom: the product lies about what it can do, and the user thinks
    /// they configured something.
    func keylyInapplicable(when condition: Bool, reason: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            self
                .disabled(condition)
                .opacity(condition ? 0.4 : 1)
            if condition {
                Text(reason)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Expandable section header, ONE for the whole product.
    ///
    /// The WHOLE ROW WIDTH is clickable, not just the chevron. The system `DisclosureGroup`
    /// only accepts clicks on a ~10pt triangle: people click the label and get nothing,
    /// and nothing in the look tells them the target is a tiny glyph on the side.
    ///
    /// The chevron is separated from the text by a full gap: placed tight it read as part
    /// of the first word.
    func keylyDisclosureHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(KeylyMotion.emphasis) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.fgDim)
                    .frame(width: 12, alignment: .leading)
                SectionLabel(text: title)
                Spacer(minLength: 0)
            }
            // Row height sized for the POINTER, not the glyph. A comment once promised 44pt while
            // the code had 28. 36pt: a full-size click target, yet a section header
            // inside a card does not swell into a banner.
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keylyHoverHighlight()
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded.wrappedValue ? "common.expanded".loc : "common.collapsed".loc)
    }

    /// Icon button: hit area >= 26px + VoiceOver label (otherwise a ~16px glyph with no label,
    /// and missing it hits the neighbor, which is especially dangerous for destructive "trash" buttons).
    func iconHitArea(_ label: String) -> some View {
        self.frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

// MARK: - Status badge



/// Small capsule counter (e.g. number of snippets) in accent style.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(Theme.Typography.mono(10, .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Colors.accentSoft))
            .fixedSize()
    }
}

// MARK: - Hotkey chip

/// Keycap (`⌘⇧Space`, `;sig`): an outline around what the user presses.
struct HotkeyChip: View {
    /// What is inside the capsule; the font depends on it.
    enum Kind {
        /// A key combination: system font, otherwise modifier glyphs run together
        /// (see `Theme.Typography.keys`).
        case keys
        /// Literal text the user TYPES (snippet trigger): monospaced, so the exact spelling
        /// is visible, including spaces and case.
        case literal
    }

    let text: String
    var kind: Kind = .keys

    var body: some View {
        Text(text)
            .font(kind == .keys ? Theme.Typography.keys(12, .medium)
                                : Theme.Typography.mono(12, .medium))
            .foregroundStyle(Theme.Colors.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Keycap: mono, TRANSPARENT background, hairline border, radius 4. A fill turned it
            // into a chip control; a key reads as an outline.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                    .stroke(Theme.Colors.borderStrong, lineWidth: 1)
            )
            .fixedSize()
    }
}

// MARK: - Section header

/// Small mono section label. Use SPARINGLY (not an "eyebrow over every block").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.mono(11, .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.Colors.fgDim)
    }
}

// MARK: - Buttons

/// Light press feedback (scale + spring) for any clickable wrapper.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(KeylyMotion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Primary action button: accent fill (near-white), black text.
///
/// The DISABLED look is a different fill, not transparency. A first attempt used
/// `opacity 0.4`, and it was worse: 40% of accent #EAEAEA over near-black
/// gives #626262, i.e. 3.30:1 against the background, while a WORKING secondary button sits at 1.09:1,
/// so the dead button became louder than a live one. In a dark theme, transparency
/// on a light fill does not dim it, it only shifts it to mid-gray.
struct KeylyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// A separate view because `isEnabled` only lives in the environment;
    /// `ButtonStyleConfiguration` does not know about it.
    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(isEnabled ? Theme.Colors.accentText : Theme.Colors.fgDim)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .background(isEnabled ? Theme.Colors.accent : Theme.Colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                // The highlight border is the product's only signature detail, and it sits
                // on ONE element: the screen's primary action. A disabled button does not get it:
                // the highlight promises a primary action, and there is none.
                .overlay {
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    if isEnabled {
                        shape.strokeBorder(
                            AngularGradient(
                                colors: [
                                    Theme.Colors.accentText.opacity(0.55),
                                    Theme.Colors.accentText.opacity(0.05),
                                    Theme.Colors.accentText.opacity(0.30),
                                    Theme.Colors.accentText.opacity(0.05),
                                    Theme.Colors.accentText.opacity(0.55),
                                ],
                                center: .center
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)
                    } else {
                        shape.stroke(Theme.Colors.border, lineWidth: 1)
                    }
                }
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(KeylyMotion.press, value: configuration.isPressed)
        }
    }
}

/// Secondary button: neutral surface with a border.
struct KeylySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.bodyEmphasis)
                // A secondary button's fill is already neutral, so the TEXT carries the disabled
                // state: fg -> fgDim. Transparency is not needed here and would only eat the border.
                .foregroundStyle(isEnabled ? Theme.Colors.fg : Theme.Colors.fgDim)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.Colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(KeylyMotion.press, value: configuration.isPressed)
        }
    }
}

/// "Mono" toggle: 34x20; when on, an `accent` track and a BLACK knob.
///
/// The stock `Toggle` only tints the track and leaves the knob white, which vanishes on a near-white
/// accent. Hence a custom style: in a monochrome system contrast comes from inversion, not color.
struct KeylyToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Theme.Space.m) {
                // We draw the label OURSELVES: the first version of this style dropped it, and toggles
                // created as `Toggle("text", isOn:)` simply lost their text, leaving
                // a bare switch with no explanation on the "My modules" screen.
                // An empty title (`Toggle("", …)`) takes zero width and does no harm.
                configuration.label
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fg)
                    .fixedSize(horizontal: false, vertical: true)
                switchTrack(on: on)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func switchTrack(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? Theme.Colors.accent : Theme.Colors.surfaceHover)
                    .overlay(Capsule().stroke(on ? Color.clear : Theme.Colors.borderStrong, lineWidth: 1))
                Circle()
                    .fill(on ? Theme.Colors.accentText : Theme.Colors.fgMuted)
                    .padding(3)
            }
        .frame(width: 34, height: 20)
        // Smooth and on our timing: an instant jump reads as a redraw.
        .animation(KeylyMotion.standard, value: on)
    }
}

/// "Mono" list row: geometry from the approved mockup (height 44, hairline separators).
///
/// Why a component and not ad hoc padding: measurements showed row pitch of 36.5–62.5pt across
/// screens, with height driven by the TRAILING content (keycap vs. a text label), and the key row
/// jumped 6pt on selection. List rhythm must not depend on what ends up on the right.
/// ONE list row recipe for the whole product.
///
/// Four had piled up: hairline separators on Overview, separate cards with
/// gaps in the launcher, neither in Settings, borders around keys. The same
/// structure, "name on the left, control on the right", looked different on every screen, and
/// Settings and Overview read like two different apps.
///
/// The RULE for choosing the style:
/// - **Hairline separator inside a section card**: the default. Overview and
///   Settings work this way: single-line rows, fixed order, the border only keeps the eye
///   from merging neighbors.
/// - **A separate card per row**: ONLY when the row can be DRAGGED. The card
///   is not decoration here: it shows the object has an edge to grab it by
///   (launcher, snippet list).
/// - **A border around the row**: when the entry is multi-line and carries its own state
///   (API keys: name, mask, consumers, health badge). A hairline cannot hold such an entry
///   together: neighboring rows blur into a mess.
///
/// Do not add another variant: if a new surface fits none of the three,
/// the problem is the data structure, not the styling.
struct KeylyRow<Leading: View, Trailing: View>: View {
    var height: CGFloat = 44
    /// The trailing slot has a fixed width, so the right edge of all rows is even, not ragged.
    var trailingWidth: CGFloat = 120
    var showsSeparator: Bool = true
    var isDimmed: Bool = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            leading()
                // min-width:0 in SwiftUI terms: without it a long name stretches the row and
                // pushes the trailing content past the edge.
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            trailing()
                .frame(width: trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        // Dim the CONTENT, not the container: a semi-transparent row lost its shape against #070707.
        .opacity(isDimmed ? 0.45 : 1)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle().fill(Theme.Colors.border).frame(height: 1)
            }
        }
    }
}

/// Screen header: ONE for all screens.
///
/// Before this, headers had diverged into four variants: a hero card with a toggle (modules), a hero with
/// a RED trash button in the same slot (my modules), a bare large title with an accent button
/// (snippets), and no header at all (settings). Screens looked like they came from different apps, and
/// muscle memory for the toggle slot led the finger to "delete".
///
/// The trailing slot may be empty: a deliberate price; consistency beats density.
struct KeylyScreenHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.fg)
                .frame(width: 38, height: 38)
                .background(Theme.Colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.title(17))
                    .foregroundStyle(Theme.Colors.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.m)
            trailing()
        }
    }
}

extension KeylyScreenHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// "Mono" segmented control. Replaces `.pickerStyle(.segmented)`.
///
/// The stock one draws segments #1f1f1f/#3b3b3b: both off-palette and LIGHTER than the card, so
/// they read as four buttons rather than one switch; selected vs. unselected differed
/// by only +28 brightness, and from a distance you could not tell which was selected. Here the selected segment
/// takes the accent with black text, distinguishable without color, in monochrome.
struct KeylySegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(isOn ? Theme.Colors.accentText : Theme.Colors.fgMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                                .fill(isOn ? Theme.Colors.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// "Mono" text field. Replaces `.textFieldStyle(KeylyTextFieldStyle())`, a system bezel field
/// in a system where every field is a recessed surface + hairline.
struct KeylyTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Colors.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )
    }
}
