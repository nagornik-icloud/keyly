import Foundation

/// Speech recognition method.
///
/// Replaces the pair "engine: cloud/local" + the "type immediately" toggle: they described ONE axis
/// but were two independent controls that silently overrode each other — after choosing "local",
/// the user still got the cloud if the live typing toggle stayed on.
/// Three mutually exclusive options make such a state impossible.
enum VoiceRecognitionMode: String, CaseIterable, Codable {
    /// On the computer, with the Parakeet model. No network, no key.
    case onDevice
    /// In the cloud, text is inserted in full after stopping.
    case cloudBatch
    /// In the cloud, text is typed as you speak. OpenAI only, and only a model that supports realtime.
    case cloudLive

    /// Local — because it works without network, key or money: the product must be able to do
    /// something right after installation, not after setting up a key.
    static let `default`: VoiceRecognitionMode = .onDevice

    var needsAPIKey: Bool { self != .onDevice }
    var isLive: Bool { self == .cloudLive }

    /// Models physically incapable of streaming recognition. `whisper-1` is the only one in our
    /// catalog, and it used to SILENTLY disable live typing: the user saw the setting on, while
    /// the product behaved as if it were off.
    static let modelsWithoutLive: Set<String> = ["whisper-1"]
}

/// Placement of the recording indicator.
enum VoiceIndicatorPlacement: String, CaseIterable, Codable {
    /// Top center — the default. Covers neither text nor the Dock.
    case topCenter
    /// Bottom center: for those without a Dock there, it is the freest spot.
    case bottomCenter
    /// Top right — next to the menu bar icon.
    case topTrailing

    /// The "at the cursor" and "don't show" options are gone by design: at the caret the badge
    /// always covered something, and a hidden badge left the user without the only sign that
    /// recording is in progress.
    static let `default`: VoiceIndicatorPlacement = .topCenter

    var titleKey: String {
        switch self {
        case .topCenter:    return "voice.indicator.topCenter"
        case .bottomCenter: return "voice.indicator.bottomCenter"
        case .topTrailing:  return "voice.indicator.topTrailing"
        }
    }
}

/// Dictation language. It used to be hardcoded to `"ru"`, and English speech was recognized
/// noticeably worse without a single explanation on screen.
enum VoiceLanguage: String, CaseIterable, Codable {
    case auto
    case ru
    case en

    static let `default`: VoiceLanguage = .auto

    /// Code for the API. `nil` means don't send the parameter at all: models detect the language
    /// themselves, and a forced code on mixed ru/en speech hurts the result more than it helps.
    var apiCode: String? {
        switch self {
        case .auto: return nil
        case .ru:   return "ru"
        case .en:   return "en"
        }
    }
}
