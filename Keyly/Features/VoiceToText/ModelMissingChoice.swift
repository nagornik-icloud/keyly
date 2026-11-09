import Foundation

/// The choice when there is no local model but there is an API key.
///
/// Offered ONCE and remembered. Asking on every press would turn the hotkey into a dialog: people
/// press it ten times a day and don't want to answer the same question each time. Silently
/// switching to the cloud is not allowed either: it changes where the data goes without the user knowing.
enum ModelMissingChoice: String, Codable {
    /// Download the model, don't go to the cloud.
    case download
    /// Cloud recognition is allowed while the model is missing.
    case useCloud

    /// Storage key. NOT private: the settings screen must show this answer and let the user revoke
    /// it — while it was hidden here, the product recognized in the cloud while the screen showed
    /// "Local model" selected with the caption "no network, no key". A person who chose local
    /// mode for privacy had no way to learn that their speech was leaving the machine.
    static let storageKey = "voiceToText.modelMissingChoice"

    static var stored: ModelMissingChoice? {
        get {
            UserDefaults.standard.string(forKey: storageKey).flatMap(ModelMissingChoice.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
    }

    /// What to do right now. Pure function: three inputs — model state, key presence
    /// and the previous answer — and exactly one outcome.
    enum Action: Equatable {
        /// Ask once and remember.
        case ask
        /// Silently go to the cloud — the user has already allowed it.
        case cloud
        /// Refuse: no model, and the cloud is not allowed or not possible.
        case refuse
        /// The model is in place, nothing to ask.
        case useLocal
    }

    static func action(modelReady: Bool, hasKey: Bool, stored: ModelMissingChoice?) -> Action {
        if modelReady { return .useLocal }
        guard hasKey else { return .refuse }   // without a key the cloud is no option, nothing to ask
        switch stored {
        case .useCloud: return .cloud
        case .download: return .refuse         // the user chose to download — don't route to the cloud
        case nil:       return .ask
        }
    }
}
