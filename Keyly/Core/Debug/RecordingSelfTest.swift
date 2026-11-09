#if DEBUG
import AVFoundation
import Foundation

/// Recording self-test: records two seconds from the selected input and prints the result.
///
/// Added when file recording moved from `AVAudioRecorder` to `AVAudioEngine` for microphone
/// selection. This is the product CORE, and there was nothing to check it with: frames show
/// the UI, unit tests don't touch audio, and a manual run needs a person at the keyboard.
/// Shipping the rewritten recording silently would mean learning about breakage from users.
///
/// Run: `KEYLY_QA_RECORD_TEST=1 Keyly` (plus `-voiceToText.inputDeviceUID <uid>` to check a
/// specific input). Prints duration, file size and level range — they reveal both "the file
/// is empty" and "the input is dead".
@MainActor
enum RecordingSelfTest {

    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["KEYLY_QA_RECORD_TEST"] == "1" else { return false }
        Task { await run() }
        return true
    }

    private static func run() async {
        // Print the input list: without it there's no way to check the MAIN point — that recording
        // comes from the SELECTED device, not the system one.
        for device in AudioInputDevices.available() {
            print("RECORD-TEST: вход «\(device.name)» uid=\(device.uid)")
        }
        let selected = UserDefaults.standard.string(forKey: SettingsKeys.voiceInputDeviceUID) ?? ""
        print("RECORD-TEST: выбран \(selected.isEmpty ? "системный" : selected)")
        let recorder = VoiceRecorder(fileName: "keyly-selftest-recording.m4a")
        print("RECORD-TEST: старт")
        do {
            try recorder.start()
        } catch {
            print("RECORD-TEST: ПРОВАЛ старта — \(error)")
            recorder.deleteFile()
            exit(1)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        recorder.stop()
        let url = recorder.tempAudioURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        guard let size, size > 0 else {
            print("RECORD-TEST: ПРОВАЛ — файла нет или он пуст")
            recorder.deleteFile()
            exit(1)
        }
        // The file must READ as audio: a non-zero size also happens with a truncated m4a without
        // a header — recognition would get garbage.
        guard let asset = try? AVAudioFile(forReading: url) else {
            print("RECORD-TEST: ПРОВАЛ — файл не читается как аудио (\(size) байт)")
            recorder.deleteFile()
            exit(1)
        }
        let seconds = Double(asset.length) / asset.fileFormat.sampleRate
        // Print "ok" ONLY when sound was actually recorded. The first version printed "ok — 0.00 s,
        // 0 KB" and signalled failure only by the exit code: by eye it read as success — a check
        // declaring success without checking.
        guard seconds > 1.0 else {
            print(String(format: "RECORD-TEST: ПРОВАЛ — записано %.2f с (%d КБ): звук не пишется",
                         seconds, size / 1024))
            recorder.deleteFile()
            exit(1)
        }
        print(String(format: "RECORD-TEST: ок — %.2f с, %d КБ, %.0f Гц",
                     seconds, size / 1024, asset.fileFormat.sampleRate))
        recorder.deleteFile()
        exit(0)
    }
}
#endif
