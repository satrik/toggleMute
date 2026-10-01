import Foundation
import CoreAudio

/// CoreAudio-backed control for the selected input device (default input,
/// a specific device, or all inputs).
/// Handles Aggregate Devices by dispatching mute/volume to their input sub-devices,
/// since AppleScript `set volume input volume` is a no-op on most aggregates.
enum AudioInputController {

    // MARK: - Public API

    /// `Preferences.inputDeviceSelection` values besides a device UID.
    static let followDefault = ""
    static let allMicrophones = "*"
    static let allInputs = "*+virtual"

    static func isSpecificDevice(_ selection: String) -> Bool {
        return ![followDefault, allMicrophones, allInputs].contains(selection)
    }

    /// With `zeroVolume`, muting also drives the input volume to 0, for
    /// devices that dont fully respect the mute property. Unmuting a device
    /// at volume 0 brings back the last volume it had above zero.
    static func setMuted(_ muted: Bool, zeroVolume: Bool = false) {
        let targets = targetDeviceIDs()
        // Unmute any targets previously muted, but no longer targeted (e.g. input device changed)
        for deviceID in mutedDeviceIDs where !targets.contains(deviceID) {
            setMuted(deviceID, muted: false, zeroVolume: false)
        }
        mutedDeviceIDs = muted ? targets : []
        for deviceID in targets { setMuted(deviceID, muted: muted, zeroVolume: zeroVolume) }
    }

    /// The devices the last mute covered.
    private static var mutedDeviceIDs: [AudioDeviceID] = []

    /// Gives devices at volume 0 their last volume above zero back.
    static func restoreZeroedVolumes() {
        for deviceID in targetDeviceIDs() { restoreZeroedVolume(deviceID) }
    }

    static func isMuted() -> Bool? {
        guard let deviceID = primaryDeviceID() else { return nil }
        return readMute(deviceID: deviceID)
    }

    /// Returns 0.0 ... 1.0, or nil if no readable volume property is present.
    static func volume() -> Float32? {
        guard let deviceID = primaryDeviceID() else { return nil }
        return readVolume(deviceID: deviceID)
    }

    /// The controlled input devices display name (e.g. "MacBook Pro Microphone",
    /// "Jabra Elite 7 Pro"), or nil if it can't be read.
    static func deviceName() -> String? {
        if selection == allMicrophones { return "All microphones" }
        if selection == allInputs { return "All inputs" }
        guard let deviceID = primaryDeviceID() else { return nil }
        return readString(deviceID, selector: kAudioObjectPropertyName)
    }

    /// Every device with at least one input stream, for the device picker.
    static func inputDevices() -> [(uid: String, name: String, isVirtual: Bool)] {
        return allDeviceIDs().filter(hasInputStream).compactMap { id in
            guard let uid = readString(id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
            return (uid, readString(id, selector: kAudioObjectPropertyName) ?? uid, transportType(id) == kAudioDeviceTransportTypeVirtual)
        }
    }

    // MARK: - Change listeners

    private static var onDevicesChanged: (() -> Void)?
    private static var onStateChanged: (() -> Void)?
    private static var watchedDeviceIDs: [AudioDeviceID] = []

    // Stored once so the identical block can be passed to the remove call.
    private static let devicesListener: AudioObjectPropertyListenerBlock = { _, _ in
        refreshWatchedDevices()
        onDevicesChanged?()
    }
    private static var stateSyncScheduled = false
    // One write notifies once per channel and sub-device; one sync covers the burst.
    private static let stateListener: AudioObjectPropertyListenerBlock = { _, _ in
        guard !stateSyncScheduled else { return }
        stateSyncScheduled = true
        DispatchQueue.main.async {
            stateSyncScheduled = false
            recordVolumes()
            onStateChanged?()
        }
    }

    private static let systemAddresses = [
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDevices,
    ].map { AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain) }

    private static let stateAddresses = [
        kAudioDevicePropertyMute,
        kAudioDevicePropertyVolumeScalar,
    ].map { AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementWildcard) }

    /// Calls `devicesChanged` when the set of controlled devices may have
    /// changed (default input switched, device plugged in or removed) and
    /// `stateChanged` when mute or input volume of a controlled device
    /// changes, e.g. from a headsets hardware mute button. Both run on main.
    static func startMonitoring(devicesChanged: @escaping () -> Void, stateChanged: @escaping () -> Void) {
        onDevicesChanged = devicesChanged
        onStateChanged = stateChanged
        for var address in systemAddresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, devicesListener)
        }
        refreshWatchedDevices()
    }

    /// Moves the state listeners to the current target devices; called on
    /// device changes and when the device selection changes.
    static func refreshWatchedDevices() {
        for deviceID in watchedDeviceIDs {
            for var address in stateAddresses {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, stateListener)
            }
        }
        watchedDeviceIDs = targetDeviceIDs().flatMap(expandedTargets)
        for deviceID in watchedDeviceIDs {
            for var address in stateAddresses {
                AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, stateListener)
            }
        }
        recordVolumes()
    }

    // MARK: - Device lookup

    private static var selection: String {
        return UserDefaults.standard.string(forKey: "inputDeviceSelection") ?? followDefault
    }

    /// The selected device, falling back to the default input when the
    /// selected one is not connected.
    private static func primaryDeviceID() -> AudioDeviceID? {
        let selection = self.selection
        if isSpecificDevice(selection),
           let id = allDeviceIDs().first(where: { readString($0, selector: kAudioDevicePropertyDeviceUID) == selection }) {
            return id
        }
        return defaultInputDeviceID()
    }

    private static func targetDeviceIDs() -> [AudioDeviceID] {
        // Aggregates only repeat their sub-devices, which are listed anyway.
        // Virtual inputs (Teams/Zoom audio, BlackHole, Loopback) carry app or
        // system audio rather than a microphone, so only allInputs has them.
        let selection = self.selection
        if selection == allMicrophones || selection == allInputs {
            let excluded = selection == allInputs
                ? [kAudioDeviceTransportTypeAggregate]
                : [kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual]
            return allDeviceIDs().filter { hasInputStream($0) && !excluded.contains(transportType($0)) }
        }
        return primaryDeviceID().map { [$0] } ?? []
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func transportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return transport
    }

    /// The devices that actually carry mute/volume: the input sub-devices of
    /// an aggregate, or the device itself.
    private static func expandedTargets(_ deviceID: AudioDeviceID) -> [AudioDeviceID] {
        let subs = subDeviceIDs(of: deviceID)
        return subs.isEmpty ? [deviceID] : subs.filter(hasInputStream)
    }

    private static func subDeviceIDs(of aggregate: AudioDeviceID) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(aggregate, &address) else { return [] }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregate, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func hasInputStream(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let abl = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        var total: UInt32 = 0
        for buffer in abl { total += buffer.mNumberChannels }
        return total
    }

    // MARK: - Mute

    private static func setMuted(_ deviceID: AudioDeviceID, muted: Bool, zeroVolume: Bool) {
        applyMute(deviceID: deviceID, muted: muted)
        if muted {
            if zeroVolume { applyVolume(deviceID: deviceID, volume: 0) }
            return
        }
        // An unmuted mic at volume 0 stays silent.
        restoreZeroedVolume(deviceID)
    }

    private static func restoreZeroedVolume(_ deviceID: AudioDeviceID) {
        guard let volume = readVolume(deviceID: deviceID), volume < 0.05 else { return }
        let last = UserDefaults.standard.dictionary(forKey: lastVolumesKey) as? [String: Double] ?? [:]
        let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID)
        // 0.8 for devices we havent stored a last volume for yet.
        applyVolume(deviceID: deviceID, volume: Float32(uid.flatMap { last[$0] } ?? 0.8))
    }

    // MARK: - Volume memory

    private static let lastVolumesKey = "lastVolumes"

    /// Keeps the last volume above zero of each controlled device, so that
    /// unmuting can undo a zeroed volume (by this app, a headsets hardware
    /// mute, or by hand).
    private static func recordVolumes() {
        var last = UserDefaults.standard.dictionary(forKey: lastVolumesKey) as? [String: Double] ?? [:]
        for deviceID in targetDeviceIDs() {
            guard let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let volume = readVolume(deviceID: deviceID), volume >= 0.05 else { continue }
            last[uid] = Double(volume)
        }
        UserDefaults.standard.set(last, forKey: lastVolumesKey)
    }

    private static func applyMute(deviceID: AudioDeviceID, muted: Bool) {
        let targets = expandedTargets(deviceID)
        for target in targets {
            if !setMuteProperty(target, muted: muted) {
                // Fallback when the device exposes no writable mute: drive volume to 0/1.
                _ = setVolumeProperty(target, volume: muted ? 0 : 1)
            }
        }
    }

    private static func setMuteProperty(_ deviceID: AudioDeviceID, muted: Bool) -> Bool {
        if writeMute(deviceID, channel: kAudioObjectPropertyElementMain, muted: muted) {
            return true
        }
        let channels = inputChannelCount(deviceID)
        guard channels > 0 else { return false }
        var anyOK = false
        for ch in 1...channels {
            if writeMute(deviceID, channel: ch, muted: muted) { anyOK = true }
        }
        return anyOK
    }

    private static func writeMute(_ deviceID: AudioDeviceID, channel: UInt32, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private static func readMute(deviceID: AudioDeviceID) -> Bool? {
        let targets = expandedTargets(deviceID)

        var mutePropertyResult: Bool?
        for target in targets {
            if let m = readMuteOnDevice(target) {
                mutePropertyResult = m
                break
            }
        }

        if mutePropertyResult == true {
            return true
        }

        // Some devices (many USB/Bluetooth headsets, e.g. Jabra) implement
        // their hardware mute button by zeroing the input gain rather than
        // flipping CoreAudio's mute property. A genuine hardware mute press
        // can therefore leave the mute property reporting a definite
        // false — not absent — so the fallback below has to run even when
        // mutePropertyResult is a known false, not just when it's nil.
        for target in targets {
            if let v = readVolumeOnDevice(target), v < 0.05 {
                return true
            }
        }

        return mutePropertyResult
    }

    private static func readMuteOnDevice(_ deviceID: AudioDeviceID) -> Bool? {
        if let v = queryMute(deviceID, channel: kAudioObjectPropertyElementMain) { return v }
        let channels = inputChannelCount(deviceID)
        guard channels > 0 else { return nil }
        for ch in 1...channels {
            if let v = queryMute(deviceID, channel: ch) { return v }
        }
        return nil
    }

    private static func queryMute(_ deviceID: AudioDeviceID, channel: UInt32) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    // MARK: - Volume

    private static func applyVolume(deviceID: AudioDeviceID, volume: Float32) {
        let clamped = max(0, min(1, volume))
        let targets = expandedTargets(deviceID)
        for target in targets {
            _ = setVolumeProperty(target, volume: clamped)
        }
    }

    private static func setVolumeProperty(_ deviceID: AudioDeviceID, volume: Float32) -> Bool {
        if writeVolume(deviceID, channel: kAudioObjectPropertyElementMain, volume: volume) {
            return true
        }
        let channels = inputChannelCount(deviceID)
        guard channels > 0 else { return false }
        var anyOK = false
        for ch in 1...channels {
            if writeVolume(deviceID, channel: ch, volume: volume) { anyOK = true }
        }
        return anyOK
    }

    private static func writeVolume(_ deviceID: AudioDeviceID, channel: UInt32, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private static func readVolume(deviceID: AudioDeviceID) -> Float32? {
        let targets = expandedTargets(deviceID)
        for target in targets {
            if let v = readVolumeOnDevice(target) { return v }
        }
        return nil
    }

    private static func readVolumeOnDevice(_ deviceID: AudioDeviceID) -> Float32? {
        if let v = queryVolume(deviceID, channel: kAudioObjectPropertyElementMain) { return v }
        let channels = inputChannelCount(deviceID)
        guard channels > 0 else { return nil }
        for ch in 1...channels {
            if let v = queryVolume(deviceID, channel: ch) { return v }
        }
        return nil
    }

    private static func queryVolume(_ deviceID: AudioDeviceID, channel: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    // MARK: - String properties

    private static func readString(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        // CFString properties hand back an already-retained CFStringRef.
        // A plain `var name: CFString` target doesn't reliably line up with
        // what CoreAudio writes into that memory (Swift's CFString bridging
        // isn't guaranteed to match a raw pointer-sized C write) — Unmanaged
        // is the correct, documented way to receive CF "Get" properties.
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName = unmanagedName else { return nil }
        return unmanagedName.takeRetainedValue() as String
    }
}
