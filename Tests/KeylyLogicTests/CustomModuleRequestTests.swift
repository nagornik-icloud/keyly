import Foundation
import Testing
@testable import KeylyLogic

/// The try-out must send exactly what the real run sends — otherwise it shows the model's
/// answer to the bare sample, not what the module will do.
@Suite("Custom module request")
struct CustomModuleRequestTests {

    @Test("Request carries the instruction and the text")
    func carriesBoth() {
        let r = CustomAIModule.requestText(instruction: "Translate to Greek", text: "Привет")
        #expect(r.contains("Translate to Greek"))
        #expect(r.contains("Привет"))
    }

    @Test("Service wrapper is English, so an English UI doesn't get a mixed-language request")
    func wrapperHasNoCyrillic() {
        let wrapper = CustomAIModule.requestText(instruction: "", text: "")
            + CustomAIModule.systemPrompt
        #expect(!wrapper.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) })
    }
}

/// A module switched off in the UI must stay off after it is saved and loaded again.
@Suite("Custom module persistence")
struct CustomModulePersistenceTests {
    @Test("isEnabled survives encode → decode")
    func disabledStaysDisabled() throws {
        var module = CustomAIModule(name: "Summary", prompt: "Summarize")
        module.isEnabled = false
        let data = try JSONEncoder().encode(module)
        let back = try JSONDecoder().decode(CustomAIModule.self, from: data)
        #expect(back.isEnabled == false)
    }
}
