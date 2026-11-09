import AVFoundation
import CoreAudio
import Foundation

/// Microphone capture via AVAudioEngine, resampled to PCM16 mono 24 kHz —
/// the format the OpenAI Realtime API expects. Also computes the input level
/// for the UI indicator.
@MainActor
final class RealtimeAudioCapture {
    enum CaptureError: Error, LocalizedError {
        case formatUnavailable
        case converterUnavailable

        /// For logs; the user sees `message` (localized, main actor).
        var errorDescription: String? {
            switch self {
            case .formatUnavailable: return "Microphone format unavailable"
            case .converterUnavailable: return "Audio converter unavailable"
            }
        }

        @MainActor var message: String {
            switch self {
            case .formatUnavailable: return "voice.capture.formatUnavailable".loc
            case .converterUnavailable: return "voice.capture.converterUnavailable".loc
            }
        }
    }

    // Callbacks are invoked on the main actor. PCM arrives in ~50–100 ms chunks.
    var onSamples: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isRunning = false

    /// Accumulated PCM16 samples for falling back to file transcription.
    private(set) var capturedPCM: Data = Data()

    var capturedSeconds: Double {
        Double(capturedPCM.count / MemoryLayout<Int16>.size) / 24000.0
    }

    func start() throws {
        guard !isRunning else { return }
        capturedPCM = Data()

        let input = engine.inputNode
        AudioInputDevices.applySelected(to: input)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw CaptureError.formatUnavailable }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else { throw CaptureError.formatUnavailable }
        targetFormat = target

        guard let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw CaptureError.converterUnavailable
        }
        converter = conv

        // The tap runs on an audio thread. It gets its own converter and format here and never
        // reads `self` state, which stop() clears on the main thread — that was a data race.
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let (data, level) = Self.convert(buffer: buffer, inputFormat: inputFormat,
                                                   converter: conv, target: target) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.capturedPCM.append(data)
                self.onSamples?(data)
                self.onLevel?(level)
                // The same level feeds the bar on the "Voice" screen. A second capture just for
                // the indicator is not possible: two open microphones on macOS cause a device
                // failure or silence in one of them.
                InputLevelMeter.shared.report(level: level)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        isRunning = false
        // The level bar must drop to zero: frozen at the last value, it shows a signal
        // that doesn't exist and reads as "the microphone is still listening".
        InputLevelMeter.shared.reset()
    }

    // MARK: - Conversion

    /// Converts one microphone buffer to PCM16 mono 24 kHz and measures its level.
    /// Pure: touches only its arguments, so it is safe on the audio thread.
    nonisolated private static func convert(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat,
                                            converter: AVAudioConverter,
                                            target: AVAudioFormat) -> (Data, Float)? {
        let ratio = inputFormat.sampleRate / target.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) / ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: estimatedFrames) else { return nil }

        var feedOnce = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, statusPtr in
            if feedOnce {
                statusPtr.pointee = .noDataNow
                return nil
            }
            feedOnce = true
            statusPtr.pointee = .haveData
            return buffer
        }

        guard status != .error, status != .endOfStream,
              let channel = outputBuffer.int16ChannelData else { return nil }

        let frames = Int(outputBuffer.frameLength)
        guard frames > 0 else { return nil }

        // PCM16 LE — copied as is, OpenAI expects exactly little-endian int16.
        let data = Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)

        // Level: mean amplitude → roughly 0…1.
        var sum: Int64 = 0
        let ptr = channel[0]
        for i in 0..<frames {
            sum += Int64(abs(Int32(ptr[i])))
        }
        let avg = Float(sum) / Float(frames)
        return (data, min(1.0, avg / 4096.0))
    }

    // MARK: - WAV dump (for falling back to file transcription)

    /// Dumps the accumulated PCM samples to a WAV file. Returns false if there is nothing to save.
    @discardableResult
    func writeWavFile(to url: URL) -> Bool {
        guard !capturedPCM.isEmpty else { return false }
        let header = Self.makeWavHeader(pcmByteCount: UInt32(capturedPCM.count))
        var output = header
        output.append(capturedPCM)
        do {
            try? FileManager.default.removeItem(at: url)
            try output.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func makeWavHeader(pcmByteCount: UInt32) -> Data {
        let sampleRate: UInt32 = 24000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign: UInt16 = channels * bitsPerSample / 8

        var header = Data()
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }
        header.append("RIFF".data(using: .ascii)!)
        appendLE(UInt32(36) &+ pcmByteCount)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        appendLE(UInt32(16))           // subchunk1 size
        appendLE(UInt16(1))            // audio format = PCM
        appendLE(channels)
        appendLE(sampleRate)
        appendLE(byteRate)
        appendLE(blockAlign)
        appendLE(bitsPerSample)
        header.append("data".data(using: .ascii)!)
        appendLE(pcmByteCount)
        return header
    }
}
