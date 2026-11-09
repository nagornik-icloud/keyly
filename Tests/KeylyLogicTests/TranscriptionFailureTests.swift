import Testing
import Foundation
@testable import KeylyLogic

/// A failed transcription must not resend the user's audio pointlessly: a bad request
/// (format, size, model) fails the same way on every key, so it must stop.
@Suite("Transcription failure policy")
struct TranscriptionFailureTests {
    @Test("Network and server trouble: retry and try other keys")
    func transient() {
        #expect(TranscriptionFailure.classify(URLError(.timedOut)) == .transient)
        for code in [408, 429, 500, 503] {
            #expect(TranscriptionFailure.classify(NSError(domain: "x", code: code)) == .transient, "\(code)")
        }
    }

    @Test("Key problems: move to the next key, no repeat on the same one")
    func keySpecific() {
        for code in [401, 403] {
            #expect(TranscriptionFailure.classify(NSError(domain: "x", code: code)) == .keySpecific, "\(code)")
        }
    }

    @Test("Bad request: stop, do not send the audio to other keys")
    func request() {
        for code in [400, 404, 413] {
            #expect(TranscriptionFailure.classify(NSError(domain: "x", code: code)) == .badRequest, "\(code)")
        }
    }
}
