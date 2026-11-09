import Foundation

/// First-launch wizard steps.
enum WizardStep: String, CaseIterable, Codable {
    case hello        // what Keyly does, briefly
    case permissions  // Accessibility + microphone
    case model        // local speech recognition model
    case hotkeys      // the 3 main hotkeys with defaults
    case done         // try-out: switch the layout of a word
    case more         // what else it does: snippets, custom modules, launcher, undo
}

/// Wizard navigation logic — PURE, no UI or system calls.
///
/// It's easy to get this wrong silently: "Next" on the permissions step must stay blocked until
/// the required permission is granted, and such a bug doesn't crash — it just lets the user
/// through, and the app then stays silent because it lacks permissions. So the rules live here
/// and are covered by tests.
enum WizardFlow {

    /// Step order. The local model step is excluded while the feature isn't in the build:
    /// showing a "download the model" screen with no way to download it would be lying to the
    /// user. Once the recognition engine ships, the step comes back by itself, no wizard edits.
    static func steps(localModelAvailable: Bool) -> [WizardStep] {
        WizardStep.allCases.filter { $0 != .model || localModelAvailable }
    }

    /// Whether the user can move forward from the step.
    ///
    /// ONLY Accessibility blocks. Without it no text feature works — the app would be dead
    /// entirely. The microphone must not block: only one module of five needs it, and someone
    /// who doesn't need dictation would be stuck in the wizard forever. A skipped microphone
    /// leaves a line on the readiness card.
    static func canAdvance(from step: WizardStep,
                           accessibilityGranted: Bool,
                           microphoneGranted: Bool) -> Bool {
        switch step {
        case .permissions: return accessibilityGranted
        case .hello, .model, .hotkeys, .done, .more: return true
        }
    }

    /// Next step in the current set. `nil` — the wizard is finished.
    static func next(after step: WizardStep, in steps: [WizardStep]) -> WizardStep? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    static func previous(before step: WizardStep, in steps: [WizardStep]) -> WizardStep? {
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// Step number for the "3 of 4" indicator — based on the CURRENT set, not all possible
    /// steps: otherwise with the model step hidden the user would see "4 of 5" and wait for a
    /// fifth screen.
    static func position(of step: WizardStep, in steps: [WizardStep]) -> (index: Int, total: Int) {
        (index: (steps.firstIndex(of: step) ?? 0) + 1, total: steps.count)
    }
}
