import SwiftUI
import AppKit

/// A generic view for recording a custom hotkey.
/// Saves nothing itself and writes nothing to UserDefaults — only through @Binding.
struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var keyCombo: KeyCombo?

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        applyBinding(to: nsView)
    }

    /// Test identifier and screen reader name. Set ON THE NSView ITSELF, not via a SwiftUI
    /// modifier: `.accessibilityIdentifier` on an `NSViewRepresentable` doesn't reach the AX tree —
    /// a real tree walk showed the field as a nameless `AXStaticText` without an identifier, so
    /// the identifier didn't work, and a blind user heard text instead of a button.
    var fieldID: String?

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        applyBinding(to: view)
        return view
    }

    private func applyBinding(to view: HotKeyRecorderNSView) {
        view.keyCombo = keyCombo
        view.onKeyComboChanged = { combo in
            keyCombo = combo
        }
        view.setAccessibilityIdentifier(fieldID.map { "keyly.hotkey.\($0)" } ?? "keyly.hotkey")
    }
}

// MARK: - HotKeyRecorderNSView

class HotKeyRecorderNSView: NSView {
    var keyCombo: KeyCombo? {
        didSet { updateLabel() }
    }

    private var isRecording: Bool = false {
        didSet {
            if oldValue != isRecording {
                HotKeyManager.shared.setRecordingMode(isRecording)
                updateSystemKeyTap(isRecording: isRecording)
            }
            updateLabel()
            needsDisplay = true
        }
    }

    var onKeyComboChanged: ((KeyCombo?) -> Void)?

    private let label = NSTextField(labelWithString: "hotkey.recorder.set".loc)
    private var systemKeyTap: CFMachPort?
    private var systemKeyTapSource: CFRunLoopSource?
    private var shouldIgnoreNextKeyDown = false

    /// Theme accent for the NSView layer. Keep in sync with `Theme.Colors.accent` (#EAEAEA):
    /// the SwiftUI token doesn't reach here, so the value is duplicated — and that is exactly why
    /// the old lime accent, invisible in screenshots, survived here the longest.
    private static let accent = NSColor(srgbRed: 0.918, green: 0.918, blue: 0.918, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        // 13pt is the size of the neighbors in the row (`Theme.Typography.bodyEmphasis`, 13). The
        // hotkey field sits IN THE SAME ROW as the key picker and the model picker, and a font size
        // of its own makes it look foreign: 18pt next to 13pt reads as a layout bug, not as
        // emphasis. Small punctuation marks ("`") aren't fixed by this — the warning line under
        // the field names them.
        // SYSTEM font, not monospaced: in SF Mono the modifier glyphs overlap
        // ("⌥⌘4" is 24.1pt vs 33.2pt, ⌥ runs into ⌘). The decision and measurements live in
        // `Theme.Typography.keys`; the value is duplicated here because the SwiftUI token doesn't
        // reach NSView.
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        // For a screen reader this is a BUTTON, not a label: it is clicked to record a shortcut.
        // By default `NSView` reports the role `AXUnknown`/`AXStaticText`, and the control was
        // unreachable by voice.
        setAccessibilityRole(.button)
        setAccessibilityLabel("hotkey.label".loc)
        setAccessibilityElement(true)
        wantsLayer = true
        layer?.cornerRadius = 8
        // Transparent — the frame/background is drawn by the themed SwiftUI background under the NSView.
        layer?.backgroundColor = NSColor.clear.cgColor
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `KEYLY_QA_RECORDING=1` starts recording immediately when the view appears in a window.
    ///
    /// The recording state (dashed frame, accent, "Press a hotkey…") is created only by a real
    /// mouse click, which the capture doesn't do — so it never appeared in any frame. Half of
    /// the remarks about the field concern exactly this state, so the capture must include it.
    #if DEBUG
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil,
              ProcessInfo.processInfo.environment["KEYLY_QA_RECORDING"] == "1" else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.window?.makeFirstResponder(self)
        }
    }
    #endif

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isRecording = false
            shouldIgnoreNextKeyDown = false
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            isRecording = true
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !isRecording {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Esc
            keyCombo = nil
            onKeyComboChanged?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        keyCombo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
        onKeyComboChanged?(keyCombo)
        window?.makeFirstResponder(nil)
    }

    private func updateSystemKeyTap(isRecording: Bool) {
        if isRecording { installSystemKeyTap() } else { teardownSystemKeyTap() }
    }

    private func installSystemKeyTap() {
        guard systemKeyTap == nil else { return }
        let systemDefinedMask = CGEventMask(1) << CGEventMask(kNXSystemDefined)
        let keyDownMask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let mask = systemDefinedMask | keyDownMask
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let recorder = Unmanaged<HotKeyRecorderNSView>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = recorder.systemKeyTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type.rawValue == kNXSystemDefined || type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }
            let recorder = Unmanaged<HotKeyRecorderNSView>.fromOpaque(userInfo).takeUnretainedValue()
            if type.rawValue == kNXSystemDefined {
                return recorder.handleSystemDefinedEvent(event)
            } else {
                return recorder.handleKeyDownEvent(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        else {
            Log.error(.ui, "HotKeyRecorder: не удалось установить EventTap — нет прав?")
            return
        }
        systemKeyTap = tap
        systemKeyTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = systemKeyTapSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func teardownSystemKeyTap() {
        if let source = systemKeyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            systemKeyTapSource = nil
        }
        if let tap = systemKeyTap {
            CFMachPortInvalidate(tap)
            systemKeyTap = nil
        }
    }

    private func handleSystemDefinedEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isRecording, let nsEvent = NSEvent(cgEvent: event),
              let combo = KeyCombo.fromSystemDefined(event: nsEvent) else {
            return Unmanaged.passUnretained(event)
        }
        shouldIgnoreNextKeyDown = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.keyCombo = combo
            self.onKeyComboChanged?(combo)
            self.window?.makeFirstResponder(nil)
        }
        return nil
    }

    private func handleKeyDownEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isRecording else { return Unmanaged.passUnretained(event) }
        if shouldIgnoreNextKeyDown {
            shouldIgnoreNextKeyDown = false
            return nil
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection([.command, .option, .control, .shift])
        let combo = KeyCombo(keyCode: keyCode, modifiers: mods, isSystemKey: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.keyCombo = combo
            self.onKeyComboChanged?(combo)
            self.window?.makeFirstResponder(nil)
        }
        return nil
    }

    private func updateLabel() {
        if isRecording {
            label.stringValue = "hotkey.recorder.listening".loc
            label.textColor = Self.accent
            setAccessibilityValue("hotkey.recorder.listening".loc)
        } else if let combo = keyCombo {
            label.stringValue = combo.description
            label.textColor = NSColor.white.withAlphaComponent(0.92)
            setAccessibilityValue(combo.description)
        } else {
            // Placeholder: dimmed so the field reads as "empty and clickable".
            label.stringValue = "hotkey.recorder.set".loc
            label.textColor = NSColor.white.withAlphaComponent(0.40)
            setAccessibilityValue("hotkey.recorder.set".loc)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layer = layer else { return }
        if isRecording {
            layer.backgroundColor = Self.accent.withAlphaComponent(0.16).cgColor
            Self.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }

    deinit { teardownSystemKeyTap() }
}
