import SwiftUI
import AppKit

/// Why a key was rejected. One failure contract for all three consumers: previously ANY
/// error collapsed into `.failure` and was drawn as "Key rejected" — no network, exhausted
/// quota, provider outage and a wrong model were indistinguishable, and people went to
/// replace a working key.
enum KeyFailure: Equatable {
    case rejected      // 401 — the key really is rejected
    case quota         // 429 or exhausted quota
    case provider      // 5xx — provider-side failure
    case offline       // no network
    case badModel      // key works, but the selected model is unavailable
    case unknown(String)
    /// Rejected by FORMAT, before any network call. Carries the catalog key and the substitution.
    case badFormat(String, String)

    var short: String {
        switch self {
        case .rejected:  return "keys.status.rejected".loc
        case .quota:     return "keys.status.quota".loc
        case .provider:  return "keys.status.provider".loc
        case .offline:   return "keys.status.offline".loc
        case .badModel:  return "keys.status.badModel".loc
        case .unknown:   return "keys.status.unknown".loc
        case .badFormat: return "keys.status.badFormat".loc
        }
    }

    var full: String {
        switch self {
        case .rejected:  return "keys.status.rejected.hint".loc
        case .quota:     return "keys.status.quota.hint".loc
        case .provider:  return "keys.status.provider.hint".loc
        case .offline:   return "keys.status.offline.hint".loc
        case .badModel:  return "keys.status.badModel.hint".loc
        // The provider's response body is NOT shown on screen: it is raw English JSON
        // that tells the user nothing. Details stay in the log, where they are actually read.
        case .unknown: return "keys.status.unknown.hint".loc
        case .badFormat(let key, let argument):
            return argument.isEmpty ? key.loc : key.loc(argument)
        }
    }
}

enum ValidationState: Equatable {
    case unknown
    case checking
    case success
    case failure(KeyFailure)

    /// Compatibility for places that only care about the fact of failure.
    static let failureGeneric = ValidationState.failure(.unknown(""))
    var isFailure: Bool { if case .failure = self { return true }; return false }
}

/// Maps an error to a reason. One place for the whole app — otherwise three consumers
/// write three different texts for the same HTTP code.
func classifyKeyFailure(_ error: Error) -> KeyFailure {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
            return .offline
        default: break
        }
    }
    // Status code FIRST: it is unambiguous, while the provider may change the body any day.
    // Classification used to rely on body text only, and any unfamiliar error format
    // became a bare "error" with no hint of what to do.
    if ns.domain.hasSuffix("Validate") {
        switch ns.code {
        case 401, 403: return .rejected
        case 429:      return .quota
        case 404:      return .badModel
        case 500...599: return .provider
        default:       break
        }
    }
    let text = error.localizedDescription.lowercased()
    if text.contains("401") || text.contains("unauthorized") || text.contains("invalid_api_key") {
        return .rejected
    }
    if text.contains("429") || text.contains("quota") || text.contains("rate limit") {
        return .quota
    }
    if text.contains("500") || text.contains("502") || text.contains("503") || text.contains("overloaded") {
        return .provider
    }
    if text.contains("model") && (text.contains("not found") || text.contains("does not exist") || text.contains("404")) {
        return .badModel
    }
    return .unknown(error.localizedDescription)
}

extension OnboardingView {
    var settingsSectionAPIKeys: some View {
        settingsCard(title: "keys.section.title".loc) {
            // Privacy is a QUIET note (lime only on the shield icon), not a loud banner.
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text("keys.section.privacy".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.bottom, Theme.Space.xs)

            SectionLabel(text: "keys.section.saved".loc)
            // One row per provider: header + inline "+ key" (not an orphan button below),
            // and a quiet empty line when there are no keys — OpenAI and Gemini stay symmetric.
            ForEach(APIProvider.allCases, id: \.self) { provider in
                let providerKeys = apiKeyStore.keys.filter { $0.provider == provider }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Text(provider.title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgDim)
                        Spacer()
                        Button {
                            newKeyProvider = provider
                            newKeyName = ""
                            newKeyValue = ""
                            showAddKeySheet = true
                        } label: {
                            Label("keys.add.short".loc, systemImage: "plus")
                                .font(Theme.Typography.caption)
                        }
                        .buttonStyle(.borderless)
                        .tint(Theme.Colors.fgMuted)
                    }
                    if providerKeys.isEmpty {
                        Text("keys.empty".loc)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.fgDim)
                    } else {
                        ForEach(providerKeys) { key in
                            apiKeyRow(provider: provider, key: key)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// One saved key entry as a compact mini-card: name header + check status + actions
    /// on top, the key field in dark style + "Select" below. It used to be 6 controls
    /// crammed into one row with native light fields.
    func apiKeyRow(provider: APIProvider, key: APIKeyEntry) -> some View {
        let isSelectedEverywhere = apiKeyStore.selectedErrorFix.keyId == key.id &&
            apiKeyStore.selectedErrorFix.provider == provider &&
            apiKeyStore.selectedVoiceToText.keyId == key.id &&
            apiKeyStore.selectedVoiceToText.provider == provider
        return APIKeyRowView(
            name: Binding(
                get: { key.name },
                set: { apiKeyStore.updateKey(id: key.id, name: $0, value: key.value, model: key.model) }
            ),
            keyValue: Binding(
                get: { key.value },
                set: { apiKeyStore.updateKey(id: key.id, name: key.name, value: $0, model: key.model) }
            ),
            validation: validationStatus[key.id] ?? .unknown,
            keyId: key.id,
            isSelected: isSelectedEverywhere,
            onValidate: { validateKey(entry: key) },
            onDelete: { confirmDeleteKey(id: key.id, name: key.name) },
            onSelect: {
                let selection = APIKeySelection(provider: provider, keyId: key.id, model: key.model ?? defaultModel(for: provider))
                apiKeyStore.select(context: .errorFix, selection: selection)
                apiKeyStore.select(context: .voiceToText, selection: selection)
            },
            onSelectFor: { context in
                let selection = APIKeySelection(provider: provider, keyId: key.id, model: key.model ?? defaultModel(for: provider))
                apiKeyStore.select(context: context, selection: selection)
            },
            onOpenModuleForModel: {
                // Navigate to the FIRST consumer of the key — that is where the model picker is.
                // No consumers — go to "Voice" as the most common case.
                let targets = apiKeyStore.consumerTargets(of: key.id)
                switch targets.first {
                case .module(let kind)?: selection = .module(kind)
                case .custom(let id)?:   selection = .custom(id)
                case nil:                selection = .module(.voiceToText)
                }
            },
            onRotate: { rotatingKeyId = key.id; rotatedValue = "" },
            usedIn: apiKeyStore.consumers(of: key.id,
                                          customModuleNames: Dictionary(uniqueKeysWithValues:
                                              customModules.map { ($0.id, $0.name) })),
            // Clicking a name opens the consumer's screen. Both lists have the same order —
            // they are built by the same traversal, so the index addresses reliably.
            onOpenConsumer: { index in
                let targets = apiKeyStore.consumerTargets(of: key.id)
                guard targets.indices.contains(index) else { return }
                switch targets[index] {
                case .module(let kind): selection = .module(kind)
                case .custom(let id):   selection = .custom(id)
                }
            }
        )
    }

    /// Sheet for replacing a key's VALUE. Only the value: id, name and all module references
    /// stay the same. There used to be no rotation at all, and an expired key had to be deleted
    /// and re-added — which silently reset the selection in every module that referenced it.
    var rotateKeySheet: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("keys.rotate.title".loc)
                .font(Theme.Typography.title())
                .foregroundStyle(Theme.Colors.fg)
            if let id = rotatingKeyId, let key = apiKeyStore.keys.first(where: { $0.id == id }) {
                Text("keys.rotate.body".loc(key.name, key.provider.title))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("keys.rotate.field".loc, text: $rotatedValue)
                    .textFieldStyle(KeylyTextFieldStyle())
            }
            HStack {
                Spacer()
                Button("common.cancel".loc) { rotatingKeyId = nil }
                    .buttonStyle(KeylySecondaryButtonStyle())
                Button("common.replace".loc) {
                    if let id = rotatingKeyId, let key = apiKeyStore.keys.first(where: { $0.id == id }) {
                        apiKeyStore.updateKey(id: id, name: key.name,
                                              value: rotatedValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                              model: key.model)
                        // The value changed — the previous verdict no longer applies.
                        // Take the UPDATED entry from the store: a snapshot taken BEFORE the edit used
                        // to be passed here, so the old key was checked instead of the new one.
                        validationStatus[id] = .unknown
                        if let fresh = apiKeyStore.keys.first(where: { $0.id == id }) {
                            validateKey(entry: fresh)
                        }
                    }
                    rotatingKeyId = nil
                }
                .buttonStyle(KeylyPrimaryButtonStyle())
                .disabled(rotatedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(minWidth: 420)
    }

    var addKeySheet: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("keys.add.title".loc)
                .font(Theme.Typography.title(16))
                .foregroundStyle(Theme.Colors.fg)
            // Segments instead of a native Picker: there are two providers, and a dropdown
            // for choosing one of two is an extra click and foreign typography on a screen
            // built from our own components.
            KeylySegmented(selection: $newKeyProvider,
                           options: APIProvider.allCases.map { ($0, $0.title) })
            TextField("keys.add.name".loc, text: $newKeyName)
                .textFieldStyle(KeylyTextFieldStyle())
            // prompt with Text(verbatim:), NOT a string literal: SwiftUI treats a literal as a
            // LocalizedStringKey and pulls it into the catalog, where it lands as an untranslated
            // key and fails the localization test. The provider key format is the same in all
            // languages and is not translatable at all.
            SecureField("", text: $newKeyValue,
                        prompt: Text(verbatim: newKeyProvider == .openai ? "sk-..." : "AIza..."))
                .textFieldStyle(KeylyTextFieldStyle())
            // Where to get a key. Without this line someone seeing the word "API" for the first
            // time hits a dead end in the first minute — and without a key three of seven modules
            // stay silent. The field placeholder shows the expected key shape: a truncated or
            // foreign format is visible immediately, before the network check.
            Link(newKeyProvider == .openai
                 ? "keys.add.whereOpenAI".loc
                 : "keys.add.whereGemini".loc,
                 destination: URL(string: newKeyProvider == .openai
                                   ? "https://platform.openai.com/api-keys"
                                   : "https://aistudio.google.com/apikey")!)
                .font(Theme.Typography.caption)
                .tint(Theme.Colors.fgMuted)
            HStack(spacing: Theme.Space.s) {
                Spacer()
                Button("common.cancel".loc) { showAddKeySheet = false }
                    .buttonStyle(KeylySecondaryButtonStyle())
                Button("common.save".loc) {
                    let entry = apiKeyStore.addKey(provider: newKeyProvider, name: newKeyName, value: newKeyValue, model: nil)
                    validationStatus[entry.id] = .unknown
                    showAddKeySheet = false
                    validateKey(entry: entry)
                }
                .buttonStyle(KeylyPrimaryButtonStyle())
                .disabled(newKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(minWidth: 420)
        .background(Theme.Colors.bg)
    }

    func confirmDeleteKey(id: UUID, name: String) {
        let alert = NSAlert()
        alert.messageText = "keys.delete.title".loc
        // List of what will stop working. "Cannot be restored" is about the key itself, but the
        // user cares more about which modules go silent. Without names the cost cannot be judged.
        let names = apiKeyStore.consumers(of: id,
                                          customModuleNames: Dictionary(uniqueKeysWithValues:
                                              customModules.map { ($0.id, $0.name) }))
        alert.informativeText = names.isEmpty
            ? "keys.delete.unused".loc(name)
            : "keys.delete.used".loc(name, names.joined(separator: ", "))
        // "Cancel" FIRST — it becomes the default button, so Enter cancels rather than
        // deletes. Previously in all three alerts of the app Enter meant "Delete": a habit
        // of clicking through dialogs would cost the user a configured snippet, module
        // or key.
        alert.addButton(withTitle: "common.cancel".loc)
        alert.addButton(withTitle: "common.delete".loc)
        if alert.runModal() == .alertSecondButtonReturn {
            apiKeyStore.deleteKey(id: id)
        }
    }

    func defaultModel(for provider: APIProvider) -> String {
        provider.defaultModel
    }

    func modelOptions(for provider: APIProvider, context: APIKeyContext, current: String? = nil) -> [String] {
        var base: [String]
        switch provider {
        case .openai:
            switch context {
            case .voiceToText:
                // The voice picker selects the text PROCESSING model, not the transcription one.
                // It used to offer transcription models — and the chosen one went into the
                // processing chat request, which it does not accept: the user saw a
                // "Processing failed" badge and text without paragraphs. The app picks the
                // transcription model itself.
                fallthrough
            case .errorFix, .customModule:
                // From most capable to lightest. Names verified with real API requests
                // (2026-06): the non-existent gpt-5.5-mini (404) was removed.
                // Note: gpt-5* are reasoning models (2-5s slower); for fast typo fixing
                // gpt-4o-mini / gpt-4.1-nano are better.
                base = ["gpt-5.5", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1", "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini", "gpt-4.1-nano"]
            }
        case .gemini:
            base = [
                "gemini-flash-latest",
                "gemini-flash-lite-latest",
                // gemini-2.5-flash removed: the API returned 404
                // "no longer available to new users" — the model in the list was dead, and
                // whoever picked it hit a rejection with no explanation.
                "gemini-2.5-flash-lite",
                "gemini-3-flash-preview",
                "gemini-3-pro-preview",
                "gemini-3.1-flash",
                "gemini-3.1-flash-lite-preview"
            ]
        }
        if let current, !current.isEmpty, !base.contains(current) {
            base.append(current)
        }
        return base
    }

    func normalizeModelSelectionIfNeeded(context: APIKeyContext, provider: APIProvider) {
        let current = apiKeyStore.model(for: context)
        let options = modelOptions(for: provider, context: context, current: nil)
        guard !options.isEmpty else { return }
        guard !options.contains(current) else { return }
        // The replacement is not "first in the list": the list is sorted from most capable,
        // and reasoning models come first — they are seconds slower and more expensive. For
        // polishing transcripts and fixing typos that is the worst possible choice.
        let preferred = provider.defaultModel
        apiKeyStore.updateModel(for: context,
                                model: options.contains(preferred) ? preferred : (options.first ?? preferred))
    }

    func modelBinding(for context: APIKeyContext) -> Binding<String> {
        Binding<String>(
            get: { apiKeyStore.model(for: context) },
            set: { apiKeyStore.updateModel(for: context, model: $0) }
        )
    }

    func syncValidationStatus(resetExisting: Bool = false) {
        let existingIds = Set(apiKeyStore.keys.map { $0.id })
        validationStatus = validationStatus.filter { existingIds.contains($0.key) }
        for id in existingIds where resetExisting || validationStatus[id] == nil {
            validationStatus[id] = .unknown
        }
    }

    func validateAllStoredKeys(forceReset: Bool) {
        syncValidationStatus(resetExisting: forceReset)
        for entry in apiKeyStore.keys {
            if forceReset || validationStatus[entry.id] == .unknown {
                validateKey(entry: entry)
            }
        }
    }

    func validateKey(entry: APIKeyEntry) {
        #if DEBUG
        // Demo keys are placeholders: never send them to a provider.
        if DemoContent.isActive {
            validationStatus[entry.id] = .success
            return
        }
        #endif
        // Format BEFORE the network. A truncated tail yields the same 401 as a foreign key,
        // and the user goes off fixing the wrong thing. A request with a known-broken key is pointless.
        let verdict = APIKeyFormat.check(entry.value, provider: entry.provider == .openai ? .openai : .gemini)
        if APIKeyFormat.blocksNetworkCheck(verdict), let message = APIKeyFormat.messageKey(for: verdict) {
            validationStatus[entry.id] = .failure(.badFormat(message.key, message.argument))
            Log.warn(.network, "Ключ отвергнут по формату: \(verdict)")
            return
        }
        // A mismatched prefix does NOT cancel the network check: providers introduce new
        // formats, and declaring a working key invalid costs more than showing an extra hint.
        if case .wrongPrefix = verdict {
            Log.warn(.network, "Префикс ключа непривычен для провайдера — проверяем по сети как обычно")
        }
        validationStatus[entry.id] = .checking
        Task {
            do {
                switch entry.provider {
                case .openai: try await validateOpenAIKey(entry)
                case .gemini: try await validateGeminiKey(entry)
                }
                await MainActor.run {
                    validationStatus[entry.id] = .success
                    // The check time is stored so that "ok" does not look like an eternal truth:
                    // the key may have been revoked yesterday while the mark dates from last month.
                    KeyCheckLog.record(keyId: entry.id, at: Date())
                }
            } catch {
                // Response body goes to the LOG, not the screen: the developer reads it there, while
                // the user needs a verdict and a next step.
                Log.warn(.network, "Проверка ключа не прошла: \(LogSanitizer.sanitize(error.localizedDescription))")
                await MainActor.run {
                    validationStatus[entry.id] = .failure(classifyKeyFailure(error))
                    KeyCheckLog.record(keyId: entry.id, at: Date())
                }
            }
        }
    }

    func validateOpenAIKey(_ entry: APIKeyEntry) async throws {
        let modelToUse = entry.model?.isEmpty == false ? entry.model! : entry.provider.defaultModel
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        // max_completion_tokens, NOT max_tokens: reasoning models (gpt-5*) reject
        // max_tokens with 400 unsupported_parameter — otherwise a valid key was marked "Error".
        let body: [String: Any] = [
            "model": modelToUse,
            "messages": [["role": "user", "content": "ping"]],
            "max_completion_tokens": 16
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(entry.value)", forHTTPHeaderField: "Authorization")
        // Shared session with the app's timeout: on the default shared session the key
        // check would hang up to the system ceiling of 60+ seconds with no clear failure.
        let (data, response) = try await LLMSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "OpenAIValidate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }

    func validateGeminiKey(_ entry: APIKeyEntry) async throws {
        let modelToUse = entry.model?.isEmpty == false ? entry.model! : entry.provider.defaultModel
        var request: URLRequest
        do {
            request = try GeminiClient.generateContentRequest(model: modelToUse, apiKey: entry.value)
        } catch {
            throw NSError(domain: "GeminiValidate", code: -1, userInfo: [NSLocalizedDescriptionKey: "keys.validate.badURL".loc])
        }
        let body: [String: Any] = [
            "contents": [["parts": [["text": "ping"]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        // Shared session with the app's timeout: on the default shared session the key
        // check would hang up to the system ceiling of 60+ seconds with no clear failure.
        let (data, response) = try await LLMSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "GeminiValidate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
