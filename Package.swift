// swift-tools-version: 6.0
import PackageDescription

// This package exists ONLY for unit tests of pure logic (`swift test`).
// The app is built by the Xcode project; the same files are included here BY PATH,
// so `project.pbxproj` never has to be edited (hand-editing it for a test target risks
// breaking the project, for the same gain).
//
// Add files here only if they pull in no runtime (event tap, AX, audio):
// we test decisions and transformations, not system side effects.
let package = Package(
    name: "KeylyLogic",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "KeylyLogic",
            path: "Keyly",
            sources: [
                "Features/LayoutSwitch/LayoutMapper.swift",
                "Features/LayoutSwitch/KeyboardLayoutPair.swift",
                "Features/LayoutSwitch/TerminalTargets.swift",
                "Features/Snippets/Snippet.swift",
                "Features/CustomModules/CustomAIModule.swift",
                "Features/AppLauncher/AppLaunchShortcut.swift",
                "Stores/SettingsStore.swift",
                "Features/Backup/SettingsBundle.swift",
                "Core/Networking/PromptGuardrails.swift",
                "Features/ErrorFix/ErrorFixPrompt.swift",
                "Features/TextPolish/TextPolishLevel.swift",
                "Features/TextPolish/TextPolishPrompt.swift",
                "Features/TextPolish/TextPolishModel.swift",
                "Features/TextPolish/TextPolishGuard.swift",
                "Features/Snippets/SnippetSearch.swift",
                "Features/Snippets/SnippetPlaceholders.swift",
                "Core/HotKey/KeyCombo.swift",
                "Features/HotKey/BareKeyWarning.swift",
                "Features/HotKey/ModuleAttention.swift",
                "Features/HotKey/SystemHotKeys.swift",
                "Features/HotKey/HotKeyConflict.swift",
                "Features/HotKey/HotKeyFieldID.swift",
                "Features/AppLauncher/LaunchTarget.swift",
                "Features/VoiceToText/SignalWatchdog.swift",
                "Features/VoiceToText/WaveformMath.swift",
                "Features/Pricing/ModelPricing.swift",
                "Features/VoiceToText/InsertSpacing.swift",
                "Core/Logging/LogSanitizer.swift",
                "Core/Logging/Log.swift",
                "Core/Logging/LogExport.swift",
                "Core/Localization/AppLanguage.swift",
                "Features/Statistics/UsageStats.swift",
                "Features/Statistics/Plural.swift",
                "Features/VoiceToText/DiskSpace.swift",
                "Features/VoiceToText/TranscriptionPrompt.swift",
                "Features/VoiceToText/RealtimeItemFilter.swift",
                "Features/VoiceToText/ModelMissingChoice.swift",
                "Features/VoiceToText/LocalModelFiles.swift",
                "Features/Onboarding/WizardFlow.swift",
                "Features/WhatsNew/WhatsNew.swift",
                "Features/UndoAction/UndoPlan.swift",
                "Core/Storage/StoreEnvelope.swift",
                "Stores/APIKeyFormat.swift",
                "Core/System/CaretTier.swift",
                "Core/Clipboard/CopyDetection.swift",
                "Core/App/AppIdentity.swift",
                "Core/App/LegacyDomainMigration.swift",
                "Core/Storage/SecretMigration.swift",
                "Features/VoiceToText/TranscriptionFailure.swift",
            ]
        ),
        .testTarget(
            name: "KeylyLogicTests",
            dependencies: ["KeylyLogic"],
            path: "Tests/KeylyLogicTests"
        ),
    ]
)
