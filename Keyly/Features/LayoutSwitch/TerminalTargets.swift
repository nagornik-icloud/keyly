import AppKit

/// Terminals need a SEPARATE text replacement strategy.
///
/// Observed in Terminal: pressing the layout hotkey wrote `;2D` into the command line instead
/// of converting the word. Not a permissions or AX issue: the terminal doesn't treat
/// `Cmd+Shift+Left` as a selection — it passes the combo to the shell as an escape sequence,
/// and readline prints its tail as plain characters. Any "select → copy → paste" will do the
/// same: there's simply no selection there.
///
/// So in a terminal we don't select at all and act like a person: erase what was typed with
/// backspaces and type it again. The `InputMonitor` buffer knows WHAT was typed — that's
/// enough, and the clipboard isn't involved.
enum TerminalTargets {

    /// Terminal bundle ids. A list, not an AX role heuristic: in Terminal and iTerm the input
    /// field is a plain `AXTextArea`, indistinguishable from a text editor via AX.
    private static let bundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.mitchellh.ghostty",
    ]

    static func isFrontmostTerminal() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return bundleIds.contains(id)
    }

    /// The last typed word — the one left of the cursor.
    /// `nil` if the input buffer has no word: refusing is better than backspacing over
    /// something we don't know.
    static func lastTypedWord(in typed: String) -> String? {
        // The tail after the last separator. Space and newline are word boundaries; everything
        // else (dots, slashes, hyphens) may be part of a path or command, and splitting on them
        // would convert half a word.
        let word = typed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last
        guard let word, !word.isEmpty else { return nil }
        return String(word)
    }
}
