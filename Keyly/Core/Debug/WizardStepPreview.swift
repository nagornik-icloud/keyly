import SwiftUI

/// Which wizard step to capture and in which permission state.
///
/// The enum ITSELF is available in every configuration; only its renderer is under `#if DEBUG`.
/// While it was entirely behind the flag, `WizardView` referenced a type that doesn't exist in
/// Release, and the Release build failed to compile. It went unnoticed for a long time because
/// only Debug was built.
enum WizardStepPreview {
    case hello
    case permissionsDenied
    case permissionsGranted
    case hotkeys
    case done
}

#if DEBUG
/// Renders individual wizard steps for the QA catalog.
///
/// The steps live inside `WizardView` and depend on the REAL system permissions, so they can't
/// be captured "as is": on a machine with granted permissions the "not granted" state simply
/// can't be reproduced, yet that's exactly what a new user sees. Here the states are set explicitly.
extension WizardStepPreview {
    @MainActor
    static func view(_ preview: WizardStepPreview) -> some View {
        WizardView(onFinish: {}, previewState: preview)
            // Matches the real wizard window (AppDelegate) — otherwise the frame shows the wrong size,
            // and the dead space in the snapshot doesn't match the product.
            .frame(width: 620, height: 480)
    }
}
#endif
