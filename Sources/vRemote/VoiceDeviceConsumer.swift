import CoreAudio
import Foundation

/// Answers "is another application still reading the virtual input device?".
///
/// This exists to close one failure mode: if the user's voice app swallows the
/// second press of a toggle, vRemoter closes the remote microphone while the app
/// is still recording, and the user talks into a closed microphone.
///
/// The decision is split in two. `holders` is pure and decides, given the raw
/// process/device picture. `probe` collects that picture from CoreAudio. Only the
/// first half is worth asserting, and only it may be free of framework types.
enum VoiceDeviceConsumer {
    static let deviceName = "vRemoteDr 2ch"

    enum Answer: Equatable {
        /// Something other than this app is holding the device.
        case held(by: [Consumer])

        case none

        /// The picture could not be collected, so nothing can be claimed.
        case unknown

        var isHeld: Bool {
            if case .held = self { return true }
            return false
        }
    }

    struct Consumer: Equatable {
        let pid: pid_t
        let deviceNames: [String]
    }

    /// Which of these processes are holding `targetDeviceName`.
    ///
    /// - Parameter excludedPids: processes that must never count, in practice
    ///   this app: it holds the device itself and would otherwise always be the
    ///   answer.
    static func holders(
        among processes: [(pid: pid_t, deviceNames: [String])],
        targetDeviceName: String,
        excludedPids: Set<pid_t>
    ) -> [Consumer] {
        processes
            .filter { !excludedPids.contains($0.pid) }
            .filter { candidate in
                candidate.deviceNames.contains { name in
                    name.caseInsensitiveCompare(targetDeviceName) == .orderedSame
                }
            }
            .map { Consumer(pid: $0.pid, deviceNames: $0.deviceNames) }
    }

    /// Collects the current picture from CoreAudio. A single read; nothing here
    /// listens or polls.
    static func probe(excludingSelf: Bool = true) -> Answer {
        let processes = processesHoldingInputDevices()
        guard !processes.isEmpty else { return .none }
        let excluded: Set<pid_t> = excludingSelf ? [ProcessInfo.processInfo.processIdentifier] : []
        let found = holders(
            among: processes,
            targetDeviceName: deviceName,
            excludedPids: excluded
        )
        return found.isEmpty ? .none : .held(by: found)
    }

    // MARK: - CoreAudio collection

    private static func processesHoldingInputDevices() -> [(pid: pid_t, deviceNames: [String])] {
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var list = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &list, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &list, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects.compactMap { object in
            guard let pid = pid(of: object) else { return nil }
            let names = inputDeviceNames(of: object)
            guard !names.isEmpty else { return nil }
            return (pid, names)
        }
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            object, &address, 0, nil, &size, &value
        ) == noErr else { return nil }
        return value
    }

    private static func inputDeviceNames(of object: AudioObjectID) -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyDevices,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        var devices = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            object, &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices.compactMap { name(of: $0) }
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(
                device, &address, 0, nil, &size, pointer
            )
        }
        guard status == noErr else { return nil }
        return unmanaged?.takeRetainedValue() as String?
    }
}
