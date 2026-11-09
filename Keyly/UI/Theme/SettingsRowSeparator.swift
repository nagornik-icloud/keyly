import SwiftUI

/// Hairline under a settings list row: the same separation as on Overview.
///
/// A separate modifier rather than a line of code in every row: the separator must appear
/// the same way and DISAPPEAR the same way on the last entry. While it was written ad hoc, General
/// ended up with no separators at all: the only list in the product where neighboring rows
/// were not separated by anything.
///
/// Padding mirrors `KeylyRow`: the line runs edge to edge of the row, not of the card;
/// otherwise it sticks out 14pt on both sides and reads as a section border.
struct SettingsRowSeparator: ViewModifier {
    let isLast: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, Theme.Space.s)
            if !isLast {
                Rectangle()
                    .fill(Theme.Colors.border)
                    .frame(height: 1)
            }
        }
    }
}

extension View {
    func settingsRowSeparator(isLast: Bool) -> some View {
        modifier(SettingsRowSeparator(isLast: isLast))
    }
}
