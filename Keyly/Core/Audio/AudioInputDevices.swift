import CoreAudio
import AVFoundation
import Foundation

/// List of audio input devices.
///
/// Originally needed only by the "as you speak" mode: recording there goes through
/// `AVAudioEngine`, which can be assigned a device. `AVAudioRecorder` has no input
/// selection at all, so with it the picker was not "forgotten" but physically inapplicable.
enum AudioInputDevices {

    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    /// All devices that have input channels.
    static func available() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    /// The system default input — used when the selected device has disappeared.
    static func systemDefault() -> Device? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0,
              let uid = string(deviceID, kAudioDevicePropertyDeviceUID),
              let name = string(deviceID, kAudioObjectPropertyName) else { return nil }
        return Device(id: deviceID, uid: uid, name: name)
    }

    /// What "System input" resolves to RIGHT NOW.
    ///
    /// A picker showing just "system" didn't answer the one question it is opened for: what is
    /// recording right now — the built-in mic or a headset. The user stood in front of the only
    /// relevant control and had to guess.
    static func systemDefaultName() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return string(deviceID, kAudioObjectPropertyName)
    }

    /// Device by its saved UID. UID, not `AudioDeviceID`: the numeric id is reassigned on every
    /// connection, so after reconnecting a headset a saved one would point to another device —
    /// or to nothing.
    static func device(uid: String?) -> Device? {
        guard let uid else { return nil }
        return available().first { $0.uid == uid }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    /// Assigns the user-selected input to the engine.
    ///
    /// This used to live inside `RealtimeAudioCapture`, so the mic choice worked only in
    /// "Type as you speak" mode: batch recording went through `AVAudioRecorder`, which can't be
    /// assigned an input, and the picker there was hidden as a phantom. Now all recording goes
    /// through the engine, and the assignment is shared.
    ///
    /// Call BEFORE the first access to `outputFormat`: the engine caches the input format, and
    /// changing the device afterwards yields the old device's format — a squeal goes into the
    /// stream instead of speech.
    ///
    /// A vanished device (headset unplugged) is not an error: we stay on the system input —
    /// recording matters more than honoring the setting exactly.
    @discardableResult
    static func applySelected(to input: AVAudioInputNode) -> String? {
        let uid = UserDefaults.standard.string(forKey: SettingsKeys.voiceInputDeviceUID)
        guard let uid, !uid.isEmpty else { return nil }
        guard let device = Self.device(uid: uid) else {
            Log.warn(.voice, "Аудиовход: выбранный микрофон недоступен, берём системный")
            return nil
        }
        guard let unit = input.audioUnit else { return nil }
        var deviceID = device.id
        let status = AudioUnitSetProperty(unit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &deviceID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            Log.warn(.voice, "Аудиовход: не удалось назначить микрофон \(device.name), status=\(status)")
            return nil
        }
        Log.info(.voice, "Аудиовход: \(device.name)")
        return device.name
    }
}
