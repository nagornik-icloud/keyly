import SwiftUI

/// Try-out field on a module screen.
///
/// Previously the only way to check what a module does and how it is set up was to go to
/// another app and risk real text. Here the action runs INSIDE the Keyly window: nothing
/// outside is touched, the clipboard is not involved, nothing needs undoing.
struct ModuleTryOutSection: View {
    enum Kind {
        case layout
        case errorFix
        /// Custom module: the user wrote the prompt, so checking it before the first run on
        /// real text matters most here.
        case custom(CustomAIModule)
    }

    let kind: Kind
    /// Whether the module is ready. A button on a non-ready module is a decoy: it would send
    /// a request that is bound to fail.
    let isReady: Bool
    /// Why it is not ready. Empty when ready.
    var notReadyReason: String = ""

    @State private var input: String = ""
    @State private var output: String = ""
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(text: "module.tryOut".loc)
            HStack(spacing: Theme.Space.s) {
                TextField(placeholder, text: $input)
                    .textFieldStyle(KeylyTextFieldStyle())
                Button(isRunning ? "module.tryOut.running".loc : "module.tryOut.run".loc) {
                    run()
                }
                .buttonStyle(KeylySecondaryButtonStyle())
                .disabled(!isReady || isRunning || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !isReady, !notReadyReason.isEmpty {
                Text(notReadyReason)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
            }
            if !output.isEmpty {
                Text(output)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.fg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Colors.surfaceHover)
                    )
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .layout:   return "module.tryOut.layout.placeholder".loc
        case .errorFix: return "module.tryOut.errorFix.placeholder".loc
        case .custom:   return "module.tryOut.custom.placeholder".loc
        }
    }

    private func run() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch kind {
        case .layout:
            // Local and instant: conversion is a pure function, no network needed.
            // `convert(_:)` detects the source layout itself — the same function that runs in
            // other apps' fields, so the try-out shows the REAL result.
            output = LayoutMapper.convert(text)
        case .errorFix:
            isRunning = true
            output = ""
            Task {
                let result = await ErrorFixer.shared.previewFix(text)
                await MainActor.run {
                    output = result ?? "module.tryOut.failed".loc
                    isRunning = false
                }
            }
        case .custom(let module):
            isRunning = true
            output = ""
            Task {
                let result = await CustomModuleRunner.shared.preview(module: module, sample: text)
                await MainActor.run {
                    output = result ?? "module.tryOut.failed".loc
                    isRunning = false
                }
            }
        }
    }
}
