import AVFoundation
import AppKit

/// Checks and requests microphone access.
public struct MicrophonePermission {
    /// Current microphone authorization, without prompting.
    public static var isAuthorized: Bool {
        #if DEBUG
        // Demo screenshots show the app as a set-up user sees it, without TCC grants for a
        // freshly built binary.
        if DemoContent.isActive { return true }
        #endif
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Checks and, if needed, requests microphone access.
    /// Returns the current status; the completion gets the final value (on the main thread).
    @discardableResult
    public static func ensurePermission(prompt: Bool = true, completion: ((Bool) -> Void)? = nil) -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            DispatchQueue.main.async { completion?(true) }
            return true
        case .notDetermined:
            guard prompt else {
                DispatchQueue.main.async { completion?(false) }
                return false
            }
            requestAccess(completion: completion)
            return false
        case .denied, .restricted:
            if prompt {
                openMicrophoneSettings()
            }
            DispatchQueue.main.async { completion?(false) }
            return false
        @unknown default:
            DispatchQueue.main.async { completion?(false) }
            return false
        }
    }

    /// Opens the Microphone pane in System Settings.
    public static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// SOUND settings (input), not privacy: a busy or wrongly selected microphone is fixed
    /// there — in the list of input devices.
    public static func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func requestAccess(completion: ((Bool) -> Void)?) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }
}
