import Foundation
import Carbon

/// System keyboard layouts via TIS. A thin adapter: all pair and direction logic lives in
/// `KeyboardLayoutPair` / `LayoutMapper` and is covered by tests.
///
/// Replaces the old "switch to the NEXT one in the cycle": with three or more layouts
/// installed, cycling sent the system to an unrelated source (Ukrainian, emoji, a second
/// English variant) — the text was converted, but the layout ended up wrong.
@MainActor
enum KeyboardLayoutService {

    /// The chosen pair survives restarts: auto-detection runs only the first time; after that
    /// it's the user's choice (module screen) and must not be silently overridden.
    private static let pairKey = "layoutSwitchPair"

    // MARK: - Pair

    static var pair: KeyboardLayoutPair? {
        get {
            if let data = UserDefaults.standard.data(forKey: pairKey),
               let stored = try? JSONDecoder().decode(KeyboardLayoutPair.self, from: data) {
                return stored
            }
            // First launch: detect and remember, so the choice stays stable afterwards.
            guard let detected = KeyboardLayoutPair.autoDetect(from: availableSourceIDs()) else {
                Log.warn(.layout, "Пара раскладок не определена — нет RU или EN среди установленных")
                return nil
            }
            if let data = try? JSONEncoder().encode(detected) {
                UserDefaults.standard.set(data, forKey: pairKey)
            }
            Log.info(.layout, "Пара раскладок определена: en=\(detected.enSourceID) ru=\(detected.ruSourceID)")
            return detected
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: pairKey); return
            }
            UserDefaults.standard.set(data, forKey: pairKey)
        }
    }

    // MARK: - Reading system state

    /// Id of the layout active RIGHT NOW. Used to determine conversion direction.
    static func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return sourceID(of: current)
    }

    static func availableSourceIDs() -> [String] {
        selectableSources().compactMap(sourceID(of:))
    }

    /// Installed layouts with human-readable names — for the pair picker.
    /// The name comes from the SYSTEM: the user picks by the same name they see in the macOS
    /// input menu, not by an id like `com.apple.keylayout.RussianWin`.
    static func availableLayouts() -> [(id: String, name: String)] {
        selectableSources().compactMap { source in
            guard let id = sourceID(of: source) else { return nil }
            let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
                .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
            return (id: id, name: name ?? id)
        }
    }

    /// The layout the user TYPED in — if it's in our pair.
    /// `nil` means "a third layout is active": converting by guesswork is not allowed.
    static func currentLayout() -> LayoutMapper.Layout? {
        guard let pair, let id = currentSourceID() else { return nil }
        return pair.layout(for: id)
    }

    // MARK: - Switching

    /// Switches the system to the other side of the pair. Targeted, not cycling.
    static func switchToOpposite(of layout: LayoutMapper.Layout) {
        guard let pair else { return }
        select(sourceID: pair.opposite(of: layout))
    }

    private static func select(sourceID target: String) {
        guard let source = selectableSources().first(where: { sourceID(of: $0) == target }) else {
            Log.warn(.layout, "Раскладка \(target) не найдена среди установленных — переключение пропущено")
            return
        }
        TISSelectInputSource(source)
    }

    // MARK: - TIS helpers

    private static func selectableSources() -> [TISInputSource] {
        let props: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        guard let listRef = TISCreateInputSourceList(props as CFDictionary, false)?.takeRetainedValue(),
              let list = listRef as? [TISInputSource] else { return [] }
        return list
    }

    private static func sourceID(of source: TISInputSource) -> String? {
        TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }
}
