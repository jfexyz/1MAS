import CoreAudio
import Observation

/// The Mac's sound output devices and which one is the default, kept current by CoreAudio's
/// property listeners. Being connected over Bluetooth (and having the control channel open) is
/// separate from being the sound output: with dual device connection, say, the headphones can be
/// connected while the Mac plays through its speakers.
///
/// A Bluetooth audio device's UID starts with the device's address ("A4-05-6E-6C-DE-BE:output"),
/// which is how the headphones are matched to their output. Neither reading nor changing the
/// default output needs a permission.
@MainActor @Observable
final class AudioOutput {
    enum State {
        /// No output device for these headphones: only the control channel is connected, or not
        /// even that.
        case unavailable
        /// An output device, but not the default one.
        case available
        /// The default output device.
        case current
    }

    private var outputs: [(id: AudioObjectID, uid: String)] = []
    private var defaultOutput = AudioObjectID(kAudioObjectUnknown)

    /// Listens for the rest of the app's life; there is one instance and it is never released.
    init() {
        reload()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    func state(bluetoothAddress: String) -> State {
        guard let id = output(bluetoothAddress: bluetoothAddress) else { return .unavailable }
        return id == defaultOutput ? .current : .available
    }

    /// Makes the headphones the default output. Only the output: their microphone would switch
    /// them to the hands-free profile, whose sound is far worse.
    func makeDefault(bluetoothAddress: String) throws {
        guard var id = output(bluetoothAddress: bluetoothAddress) else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id
        )
        guard status == noErr else { throw AudioOutputError(status: status) }
    }

    private func output(bluetoothAddress: String) -> AudioObjectID? {
        // IOBluetooth writes the address in lower case, CoreAudio's UIDs in upper case.
        let prefix = bluetoothAddress.uppercased().replacingOccurrences(of: ":", with: "-")
        return outputs.first { $0.uid.uppercased().hasPrefix(prefix) }?.id
    }

    private func reload() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var ids: [AudioObjectID] = []
        if AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr {
            ids = Array(repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) != noErr { ids = [] }
        }
        outputs = ids.compactMap { id in
            guard Self.hasOutput(id), let uid = Self.uid(of: id) else { return nil }
            return (id, uid)
        }

        var id = AudioObjectID(kAudioObjectUnknown)
        size = UInt32(MemoryLayout<AudioObjectID>.size)
        address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        defaultOutput = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uid(of id: AudioObjectID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

struct AudioOutputError: Error, CustomStringConvertible {
    var status: OSStatus
    var description: String { "Could not change the sound output (error \(status))" }
}
