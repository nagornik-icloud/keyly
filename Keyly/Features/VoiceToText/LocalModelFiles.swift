import Foundation

/// The set of local model files — a PURE type with no file system access.
///
/// Exists because readiness used to be checked by an indirect sign — "the folder is not
/// empty" — and on that basis the product said "Model ready", showed "Show in Finder", and then
/// refused to record: "local model not downloaded". The folder held TWO versions from different
/// package releases, and only one of them worked.
///
/// Rule of this type: **readiness is checked against what is actually needed to work, not
/// against whatever happens to be lying nearby.**
enum LocalModelFiles {

    /// Model folder name for the CURRENT package version (`FluidAudio.Repo.parakeet`).
    /// It changes when the package is updated — the old folder stays on disk as garbage.
    static let currentFolder = "parakeet-tdt-0.6b-v3-coreml"

    /// Without these files the package won't load the model (`ModelNames.ASR.requiredModels`).
    /// Four models plus the vocabulary: the package itself requires it in `AsrModels.modelsExist`,
    /// and without the vocabulary loading wipes the folder and downloads everything again — mid-dictation.
    static let required = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc",
        "parakeet_vocab.json",
    ]

    /// The set is complete. `present` is what actually lies in the model folder.
    ///
    /// ALL files are required: a set without the decoder is not "almost ready", it is a failure on
    /// the very first dictation, and the user learns about it only after speaking the phrase.
    static func isComplete(present: Set<String>) -> Bool {
        required.allSatisfy(present.contains)
    }
}
