import Foundation

/// Whose speech this is in streaming recognition — the user's or the model's. A PURE type with no network or logging.
///
/// WHY A SEPARATE TYPE. On the streaming path this is the ONLY structural guard against model text
/// reaching the user as their own speech: deltas are typed straight into the field under the cursor
/// (`VoiceToTextManager`), and post-processing with its guard is not invoked at all at the "As spoken"
/// level. So the decision must be verified by tests, not by reading code — otherwise it relies on
/// attentiveness, which is exactly how the hole got in.
///
/// WHERE THE HOLE CAME FROM. The session is opened on the CHAT model `gpt-realtime-2`; the only thing
/// keeping it from generating a reply was the `turn_detection: NSNull()` field, the code didn't read the
/// server's confirmation, and `extractTranscript` took `content[].transcript` without checking whose
/// item it was. Assistant text would have entered the user's field indistinguishable from their speech —
/// exactly the channel through which complaints like "the AI answers my speech" arise.
enum RealtimeItemFilter {

    enum Verdict: Equatable {
        /// User speech — accept.
        case humanSpeech
        /// The item does not belong to the user (`assistant`, `system`) — drop it.
        case foreign(role: String)
        /// No role, and the content type is not recognized as input audio. Accepted, but this is worth
        /// seeing in the log: the Realtime API event shape changes from version to version.
        case unlabelled
    }

    /// Input-audio marker in the content type. We check CONTAINMENT, not equality: the API has
    /// both `input_audio` and `input_audio_transcript` — matching one exact name would cut off
    /// the other. Whisper was once detected by the name `whisper-1` in exactly the same broken way.
    private static let inputAudioMarker = "input_audio"

    static func judge(role: String?, contentType: String?) -> Verdict {
        let isInputAudio = contentType?.contains(inputAudioMarker) ?? false
        guard let role, !role.isEmpty else {
            return isInputAudio ? .humanSpeech : .unlabelled
        }
        // A named role decides FIRST, and only then the content type. The reverse order made
        // the role decorative: on the input audio transcript event the type is hardcoded,
        // `isInputAudio` is always true there, and a foreign role could reject nothing — although
        // this type's contract promises precisely the role's precedence.
        if role == "user" { return .humanSpeech }
        return .foreign(role: role)
    }

}
