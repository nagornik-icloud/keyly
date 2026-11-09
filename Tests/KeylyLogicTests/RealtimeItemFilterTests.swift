import Testing
@testable import KeylyLogic

/// Filter for foreign items in streaming recognition.
///
/// On this path the filter is the ONLY
/// structural protection: deltas are typed straight into the field under the cursor, and processing with its guard
/// is not called at all at the "As spoken" level. Meanwhile the session is opened on a CHAT model
/// (`gpt-realtime-2`), and before this fix `extractTranscript` took the transcript without checking
/// whose item it was: assistant text would have been entered as the user's own speech.
///
/// The failure this guards against: instead of transcribing speech verbatim, the model
/// answered it, while the user wanted the text of their own question back.
struct RealtimeItemFilterTests {

    @Test("Речь человека принимается")
    func humanSpeechAccepted() {
        #expect(RealtimeItemFilter.judge(role: "user", contentType: "input_audio") == .humanSpeech)
        #expect(RealtimeItemFilter.judge(role: "user", contentType: nil) == .humanSpeech)
        #expect(RealtimeItemFilter.judge(role: "user", contentType: "text") == .humanSpeech)
    }

    /// The core of the protection: whatever the chat model generates, it does not reach the user's field.
    @Test("Ответ модели отбрасывается")
    func assistantRejected() {
        #expect(RealtimeItemFilter.judge(role: "assistant", contentType: "output_audio")
                == .foreign(role: "assistant"))
        #expect(RealtimeItemFilter.judge(role: "assistant", contentType: "output_audio") == .foreign(role: "assistant"))
        #expect(RealtimeItemFilter.judge(role: "assistant", contentType: "text") == .foreign(role: "assistant"))
        #expect(RealtimeItemFilter.judge(role: "system", contentType: nil) == .foreign(role: "system"))
    }

    /// The content type decides even without a role: an input audio event is the user's speech by definition.
    @Test("Входное аудио принимается даже без роли")
    func inputAudioAcceptedWithoutRole() {
        #expect(RealtimeItemFilter.judge(role: nil, contentType: "input_audio") == .humanSpeech)
        #expect(RealtimeItemFilter.judge(role: "", contentType: "input_audio_transcript") == .humanSpeech)
    }

    /// Substring, not equality: the API uses both `input_audio` and `input_audio_transcript`.
    /// An exact name for one variant would cut off the other; whisper was once detected
    /// by the name `whisper-1`, and the check broke on `gpt-realtime-whisper`.
    @Test("Разные написания входного аудио опознаются все")
    func inputAudioVariantsRecognised() {
        for type in ["input_audio", "input_audio_transcript", "input_audio_buffer"] {
            #expect(RealtimeItemFilter.judge(role: nil, contentType: type) == .humanSpeech,
                    "тип «\(type)» не опознан как речь человека")
        }
    }

    /// No role and unrecognized type: accept, but flag it. The bias toward the user
    /// is deliberate: we must not silently lose their speech, and there is nothing to recover it from.
    @Test("Неопознанный item принимается, но помечается")
    func unlabelledAcceptedButFlagged() {
        #expect(RealtimeItemFilter.judge(role: nil, contentType: nil) == .unlabelled)
        #expect(RealtimeItemFilter.judge(role: nil, contentType: "text") == .unlabelled)
        #expect(RealtimeItemFilter.judge(role: nil, contentType: nil) == .unlabelled,
                "речь человека потеряна из-за отсутствия роли")
    }

    /// A foreign item is recognized by a DIRECT signal (a named role), not by a missing signal;
    /// otherwise an empty event would silently count as foreign and speech would be lost.
    @Test("Чужим считается только названная чужая роль")
    func onlyNamedForeignRoleRejected() {
        #expect(RealtimeItemFilter.judge(role: nil, contentType: nil) == .unlabelled)
        #expect(RealtimeItemFilter.judge(role: "", contentType: nil) == .unlabelled)
        #expect(RealtimeItemFilter.judge(role: "assistant", contentType: nil) == .foreign(role: "assistant"))
    }

    /// The role OUTRANKS the content type: an assistant item does not pass even if its type is marked as
    /// input audio. The type used to override the role, and the role decided nothing.
    @Test("Чужая роль отклоняет item даже при типе входного аудио")
    func foreignRoleWinsOverContentType() {
        #expect(RealtimeItemFilter.judge(role: "assistant", contentType: "input_audio")
                == .foreign(role: "assistant"))
    }
}
