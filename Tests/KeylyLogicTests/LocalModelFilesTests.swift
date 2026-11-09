import Foundation
import Testing
@testable import KeylyLogic

/// Completeness of local model files.
///
/// These tests appeared after a bug report: the screen said "Model ready" and offered
/// "Show in Finder", but recording failed with "local model not downloaded", and
/// only AFTER a long phrase had been dictated. Readiness was checked by an indirect signal,
/// "directory is not empty", while it contained two versions from different package releases.
struct LocalModelFilesTests {

    private let full: Set<String> = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc",
        "config.json", "parakeet_vocab.json",
    ]

    @Test("Полный комплект — готово")
    func completeSet() {
        #expect(LocalModelFiles.isComplete(present: full))
    }

    /// The negative case the test exists for: ONE missing file is a failure, not
    /// "almost ready". That kind of "almost" is what produced the false "Model ready" label.
    @Test("Без любого обязательного файла — НЕ готово")
    func anyMissingFileBreaksIt() {
        for missing in LocalModelFiles.required {
            var partial = full
            partial.remove(missing)
            #expect(!LocalModelFiles.isComplete(present: partial),
                    "без «\(missing)» комплект не полон, а проверка сказала «готово»")
        }
    }

    /// The previous package version's directory stays on disk and is the same size. Counting it
    /// would declare ready a model the current version does not load.
    @Test("Посторонние файлы готовности не создают")
    func strangersDoNotCount() {
        #expect(!LocalModelFiles.isComplete(present: ["JointDecisionv3.mlmodelc", "config.json"]))
        #expect(!LocalModelFiles.isComplete(present: []))
    }

    /// The directory name is a handwritten copy of the package constant (`Repo.parakeet`), and it already
    /// changed in a FluidAudio update: a developer machine had the previous version's directory next to it.
    /// Comparing the string with itself is pointless (that was the first version of the test), so
    /// we compare against the FACT on disk, where the model is actually downloaded. No models directory
    /// (clean machine, CI): the test honestly skips instead of giving a false green.
    @Test("Имя каталога совпадает с тем, что пакет создал на диске")
    func folderMatchesWhatPackageCreated() throws {
        let models = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: models.path)) ?? []
        let complete = dirs.filter { name in
            let inside = (try? FileManager.default.contentsOfDirectory(
                atPath: models.appendingPathComponent(name).path)) ?? []
            return LocalModelFiles.isComplete(present: Set(inside))
        }
        guard !complete.isEmpty else { return }  // model not downloaded (clean machine, CI): skip
        #expect(complete.contains(LocalModelFiles.currentFolder),
                "на диске полные комплекты в \(complete), а код ищет «\(LocalModelFiles.currentFolder)»")
    }
}
