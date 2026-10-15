import AppKit
import CoreGraphics
import Foundation

enum SupportedRemoteID: String, CaseIterable, Identifiable, Codable {
    case chromecast
    case x6

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chromecast: "Chromecast Voice Remote"
        case .x6: "X6 Remote"
        }
    }

    var signature: String {
        switch self {
        case .chromecast: "18D1 · 9450"
        case .x6: "1D5A · C081"
        }
    }
}

struct RemoteButtonDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let defaultTarget: RemoteMappingTarget
    let voiceControlled: Bool
    let remappable: Bool

    init(
        id: String,
        title: String,
        symbol: String,
        defaultTarget: RemoteMappingTarget,
        voiceControlled: Bool = false,
        remappable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.defaultTarget = defaultTarget
        self.voiceControlled = voiceControlled
        self.remappable = remappable
    }
}

enum RemoteProfiles {
    static let chromecastButtons: [RemoteButtonDefinition] = [
        .init(id: "03", title: L10n.text("方向上", "Up"), symbol: "arrow.up", defaultTarget: .arrowUp),
        .init(id: "04", title: L10n.text("方向下", "Down"), symbol: "arrow.down", defaultTarget: .arrowDown),
        .init(id: "05", title: L10n.text("方向左", "Left"), symbol: "arrow.left", defaultTarget: .arrowLeft),
        .init(id: "06", title: L10n.text("方向右", "Right"), symbol: "arrow.right", defaultTarget: .arrowRight),
        .init(id: "07", title: L10n.text("确认", "Select"), symbol: "circle.inset.filled", defaultTarget: .returnKey),
        .init(id: "0B", title: L10n.text("返回", "Back"), symbol: "chevron.backward", defaultTarget: .escape),
        .init(id: "0A", title: "Home", symbol: "house", defaultTarget: .showDesktop),
        .init(id: "0E", title: "YouTube", symbol: "play.rectangle", defaultTarget: .disabled),
        .init(id: "voice", title: L10n.text("语音", "Voice"), symbol: "mic", defaultTarget: .voiceInput, voiceControlled: true),
        .init(id: "08", title: L10n.text("静音", "Mute"), symbol: "speaker.slash", defaultTarget: .mute),
        .init(id: "0F", title: "Netflix", symbol: "n.square", defaultTarget: .disabled),
        .init(id: "01", title: L10n.text("电源", "Power"), symbol: "power", defaultTarget: .disabled),
        .init(id: "11", title: L10n.text("信源", "Input"), symbol: "rectangle.on.rectangle", defaultTarget: .disabled),
        .init(id: "0C", title: L10n.text("音量＋", "Volume Up"), symbol: "speaker.plus", defaultTarget: .volumeUp),
        .init(id: "0D", title: L10n.text("音量－", "Volume Down"), symbol: "speaker.minus", defaultTarget: .volumeDown),
    ]

    static func buttons(for remote: SupportedRemoteID) -> [RemoteButtonDefinition] {
        switch remote {
        case .chromecast: chromecastButtons
        case .x6: x6Buttons
        }
    }

    static let x6Buttons: [RemoteButtonDefinition] = [
        .init(id: "mouseMode", title: L10n.text("鼠标模式", "Mouse Mode"), symbol: "cursorarrow.motionlines", defaultTarget: .disabled, remappable: false),
        .init(id: "k2A", title: "Delete", symbol: "delete.left", defaultTarget: .deleteBackward),
        .init(id: "cE2", title: L10n.text("静音", "Mute"), symbol: "speaker.slash", defaultTarget: .mute),
        .init(id: "c224", title: L10n.text("返回", "Back"), symbol: "chevron.backward", defaultTarget: .escape),
        .init(id: "k65", title: L10n.text("菜单", "Menu"), symbol: "line.3.horizontal", defaultTarget: .disabled),
        .init(id: "c196", title: L10n.text("浏览器/搜索", "Browser / Search"), symbol: "magnifyingglass", defaultTarget: .spotlight),
        .init(id: "k52", title: L10n.text("方向上", "Up"), symbol: "arrow.up", defaultTarget: .arrowUp),
        .init(id: "k51", title: L10n.text("方向下", "Down"), symbol: "arrow.down", defaultTarget: .arrowDown),
        .init(id: "k50", title: L10n.text("方向左", "Left"), symbol: "arrow.left", defaultTarget: .arrowLeft),
        .init(id: "k4F", title: L10n.text("方向右", "Right"), symbol: "arrow.right", defaultTarget: .arrowRight),
        .init(id: "k28", title: "OK", symbol: "circle.inset.filled", defaultTarget: .returnKey),
        .init(id: "k4B", title: "PG+", symbol: "arrow.up.to.line", defaultTarget: .pageUp),
        .init(id: "k4E", title: "PG−", symbol: "arrow.down.to.line", defaultTarget: .pageDown),
        .init(id: "voice", title: L10n.text("语音", "Voice"), symbol: "mic", defaultTarget: .voiceInput, voiceControlled: true),
        .init(id: "cE9", title: L10n.text("音量＋", "Volume Up"), symbol: "speaker.plus", defaultTarget: .volumeUp),
        .init(id: "cEA", title: L10n.text("音量－", "Volume Down"), symbol: "speaker.minus", defaultTarget: .volumeDown),
        .init(id: "s01", title: L10n.text("电源", "Power"), symbol: "power", defaultTarget: .disabled),
    ]
}

enum RemoteMappingTarget: String, CaseIterable, Identifiable, Codable, Hashable {
    case disabled
    case voiceInput
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case returnKey
    case escape
    case deleteBackward
    case tab
    case space
    case home
    case end
    case pageUp
    case pageDown
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case nextTrack
    case previousTrack
    case fastForward
    case rewind
    case launchPanel
    case eject
    case mediaMenu
    case forwardDelete
    case contextKey
    case showDesktop
    case spotlight
    case commandC
    case commandV
    case commandZ
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: L10n.text("禁用", "Disabled")
        case .voiceInput: L10n.text("语音输入", "Voice Input")
        case .arrowUp: L10n.text("方向上", "Up Arrow")
        case .arrowDown: L10n.text("方向下", "Down Arrow")
        case .arrowLeft: L10n.text("方向左", "Left Arrow")
        case .arrowRight: L10n.text("方向右", "Right Arrow")
        case .returnKey: "Return"
        case .escape: "Escape"
        case .deleteBackward: "Delete"
        case .tab: "Tab"
        case .space: L10n.text("空格", "Space")
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .volumeUp: L10n.text("系统音量＋", "System Volume Up")
        case .volumeDown: L10n.text("系统音量－", "System Volume Down")
        case .mute: L10n.text("系统静音", "System Mute")
        case .playPause: L10n.text("播放/暂停", "Play / Pause")
        case .nextTrack: L10n.text("下一曲", "Next Track")
        case .previousTrack: L10n.text("上一曲", "Previous Track")
        case .fastForward: L10n.text("快进", "Fast Forward")
        case .rewind: L10n.text("快退", "Rewind")
        case .launchPanel: L10n.text("调度中心", "Launchpad")
        case .eject: L10n.text("推出", "Eject")
        case .mediaMenu: L10n.text("菜单", "Menu")
        case .forwardDelete: L10n.text("前进删除", "Forward Delete")
        case .contextKey: L10n.text("菜单键", "Context Menu Key")
        case .showDesktop: L10n.text("显示桌面", "Show Desktop")
        case .spotlight: "Spotlight (⌘Space)"
        case .commandC: L10n.text("复制 (⌘C)", "Copy (⌘C)")
        case .commandV: L10n.text("粘贴 (⌘V)", "Paste (⌘V)")
        case .commandZ: L10n.text("撤销 (⌘Z)", "Undo (⌘Z)")
        case .custom: L10n.text("录制任意按键…", "Record a key…")
        }
    }

    /// The actions that keep firing while a button is held.
    ///
    /// Delete and the four arrows are the ones a person holds rather than taps:
    /// holding Backspace eats text a character at a time, and holding an arrow
    /// scrolls. Everything else is a switch — you press it or you do not — and
    /// repeating it would be noise.
    ///
    /// Forward delete is deliberately absent: it removes a word per press, so
    /// repeating it shreds text instead of clearing it.
    static let repeating: Set<RemoteMappingTarget> = [
        .deleteBackward,
        .arrowUp,
        .arrowDown,
        .arrowLeft,
        .arrowRight,
    ]

    var keyboard: (keyCode: CGKeyCode, flags: CGEventFlags)? {
        switch self {
        case .arrowUp: (0x7E, [])
        case .arrowDown: (0x7D, [])
        case .arrowLeft: (0x7B, [])
        case .arrowRight: (0x7C, [])
        case .returnKey: (0x24, [])
        case .escape: (0x35, [])
        case .deleteBackward: (0x33, [])
        case .tab: (0x30, [])
        case .space: (0x31, [])
        case .home: (0x73, [])
        case .end: (0x77, [])
        case .pageUp: (0x74, [])
        case .pageDown: (0x79, [])
        case .forwardDelete: (0x75, [])
        case .contextKey: (0x6E, [])
        case .showDesktop: (0x67, [.maskSecondaryFn])
        case .spotlight: (0x31, [.maskCommand])
        case .commandC: (0x08, [.maskCommand])
        case .commandV: (0x09, [.maskCommand])
        case .commandZ: (0x06, [.maskCommand])
        default: nil
        }
    }

    var mediaKey: Int32? {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .nextTrack: 17
        case .previousTrack: 18
        case .fastForward: 19
        case .rewind: 20
        case .launchPanel: 13
        case .eject: 14
        case .mediaMenu: 25
        default: nil
        }
    }

    func post(isDown: Bool) {
        guard self != .disabled, self != .voiceInput else { return }
        if let keyboard {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyboard.keyCode,
                keyDown: isDown
            ) else { return }
            event.flags = keyboard.flags
            event.setIntegerValueField(.eventSourceUserData, value: Key.syntheticMarker)
            event.post(tap: .cghidEventTap)
        } else if let mediaKey, isDown {
            postMediaKey(mediaKey)
        }
    }

    private func postMediaKey(_ key: Int32) {
        func post(state: Int32) {
            let data1 = Int((key << 16) | (state << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )?.cgEvent else { return }
            event.post(tap: .cghidEventTap)
        }
        post(state: 0xA)
        post(state: 0xB)
    }
}

struct RemoteCustomShortcut: Codable, Hashable {
    let keyCode: UInt16
    let flags: UInt64
    let label: String

    func post(isDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: isDown
        ) else { return }
        event.flags = CGEventFlags(rawValue: flags)
        event.setIntegerValueField(.eventSourceUserData, value: Key.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}

final class RemoteMappingStore: ObservableObject {
    static let shared = RemoteMappingStore()

    @Published private(set) var revision = 0
    private let defaults = UserDefaults.standard
    private let prefix = "remoteMapping."
    private let enabledPrefix = "remoteMappingEnabled."
    private let customPrefix = "remoteCustomMapping."

    private init() {}

    func isEnabled(_ remote: SupportedRemoteID) -> Bool {
        defaults.bool(forKey: enabledPrefix + remote.rawValue)
    }

    func setEnabled(_ enabled: Bool, for remote: SupportedRemoteID) {
        defaults.set(enabled, forKey: enabledPrefix + remote.rawValue)
        revision += 1
    }

    /// The key one button's mapping is stored under.
    ///
    /// Single-tap keeps the pre-gesture unsuffixed key so mappings written by an
    /// earlier build keep working untouched; the other gestures get a suffix.
    private func mappingKey(
        _ gesture: RemoteGesture,
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) -> String {
        let base = prefix + remote.rawValue + "." + button.id
        guard gesture != .tap else { return base }
        return base + "." + gesture.rawValue
    }

    private func customKey(
        _ gesture: RemoteGesture,
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) -> String {
        let base = customPrefix + remote.rawValue + "." + button.id
        guard gesture != .tap else { return base }
        return base + "." + gesture.rawValue
    }

    /// The target explicitly stored for one gesture, or nil when the user has
    /// assigned nothing to it.
    ///
    /// Single tap falls back to the button's own default so an untouched button
    /// still does what the remote says on the box.
    func explicitTarget(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture
    ) -> RemoteMappingTarget? {
        guard !button.voiceControlled, button.remappable else { return nil }
        let key = mappingKey(gesture, for: button, remote: remote)
        guard let raw = defaults.string(forKey: key),
              let target = RemoteMappingTarget(rawValue: raw)
        else {
            return gesture == .tap ? button.defaultTarget : nil
        }
        return target
    }

    /// What one gesture actually fires.
    ///
    /// A double tap or long press that was never assigned falls back to the
    /// single-tap mapping rather than doing nothing, so adding a long press
    /// cannot silently cost the user their short press.
    func target(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture
    ) -> RemoteMappingTarget {
        if let explicit = explicitTarget(for: button, remote: remote, gesture: gesture) {
            return explicit
        }
        return target(for: button, remote: remote)
    }

    /// Which gestures the user has armed for a button.
    ///
    /// Single tap is never listed: it is the fallback, not an extra the user
    /// opts into. A long press that lands on the same action as the single tap
    /// is not armed either — that pairing means "hold to repeat", and treating
    /// it as armed would switch the button off from repeating, which is the
    /// opposite of what the user set up.
    func armedGestures(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) -> Set<RemoteGesture> {
        let tap = target(for: button, remote: remote)
        var assigned: [RemoteGesture: RemoteMappingTarget?] = [:]
        for gesture in RemoteGesture.allCases where gesture != .tap {
            assigned[gesture] = explicitTarget(
                for: button,
                remote: remote,
                gesture: gesture
            )
        }
        return RemoteGesture.armed(tap: tap, assigned: assigned)
    }

    func target(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) -> RemoteMappingTarget {
        guard !button.voiceControlled else { return .voiceInput }
        guard button.remappable else { return .disabled }
        guard let raw = defaults.string(forKey: mappingKey(.tap, for: button, remote: remote)),
              let target = RemoteMappingTarget(rawValue: raw)
        else { return button.defaultTarget }
        return target
    }

    func setTarget(
        _ target: RemoteMappingTarget,
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture = .tap
    ) {
        guard !button.voiceControlled, button.remappable else { return }
        defaults.set(
            target.rawValue,
            forKey: mappingKey(gesture, for: button, remote: remote)
        )
        revision += 1
    }

    /// Disarms one gesture, so the button goes back to behaving as if it were
    /// the only kind of press.
    func clearGesture(
        _ gesture: RemoteGesture,
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) {
        guard gesture != .tap else { return }
        defaults.removeObject(forKey: mappingKey(gesture, for: button, remote: remote))
        defaults.removeObject(forKey: customKey(gesture, for: button, remote: remote))
        revision += 1
    }

    func customShortcut(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture = .tap
    ) -> RemoteCustomShortcut? {
        guard let data = defaults.data(forKey: customKey(gesture, for: button, remote: remote))
        else { return nil }
        return try? JSONDecoder().decode(RemoteCustomShortcut.self, from: data)
    }

    func setCustomShortcut(
        _ shortcut: RemoteCustomShortcut,
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture = .tap
    ) {
        let key = customKey(gesture, for: button, remote: remote)
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
            setTarget(.custom, for: button, remote: remote, gesture: gesture)
        }
    }

    /// Which gesture slot supplies the action a held button repeats.
    ///
    /// A repeating action repeats when either slot says so: the single tap
    /// mapped to it, or the long press mapped to it. The long press is the slot
    /// someone reaches for when they want "hold to do this" and the single tap
    /// has to stay something else — holding the button to delete while a tap
    /// still goes back. Reporting the slot rather than the target lets the
    /// caller post that slot's action, so the other slot keeps its own meaning.
    ///
    /// Nil means the button keeps ordinary gesture behaviour.
    func repeatingGesture(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID
    ) -> RemoteGesture? {
        guard button.remappable, !button.voiceControlled else { return nil }

        let longPress = explicitTarget(
            for: button,
            remote: remote,
            gesture: .longPress
        )
        if let longPress, RemoteMappingTarget.repeating.contains(longPress) {
            return .longPress
        }

        // A long press on some other action is a gesture of its own, so it wins
        // over repeating whatever the single tap happens to be.
        if longPress != nil { return nil }

        // A double tap has to wait out its window, which a held key never
        // reaches, so an armed one keeps the gesture path.
        if explicitTarget(for: button, remote: remote, gesture: .doubleTap) != nil {
            return nil
        }
        let tap = target(for: button, remote: remote)
        guard RemoteMappingTarget.repeating.contains(tap) else { return nil }
        return .tap
    }

    func targetTitle(
        for button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture = .tap
    ) -> String {
        let value = target(for: button, remote: remote, gesture: gesture)
        if value == .custom,
           let shortcut = customShortcut(for: button, remote: remote, gesture: gesture) {
            return shortcut.label
        }
        return value.title
    }

    /// Emits one half of a mapped key press.
    ///
    /// A held key is one `isDown: true` followed by one `isDown: false`; extra
    /// `isDown: true` calls in between are what the target app reads as an
    /// auto-repeat, because no key-up separates them. A media target already
    /// posts its whole press-and-release on `isDown: true`, so repeating it is
    /// just calling this again.
    func post(
        button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture = .tap,
        isDown: Bool
    ) {
        let value = target(for: button, remote: remote, gesture: gesture)
        if value == .custom {
            customShortcut(for: button, remote: remote, gesture: gesture)?
                .post(isDown: isDown)
        } else {
            value.post(isDown: isDown)
        }
    }

    /// Emits one complete press of the button's mapped action.
    ///
    /// A gesture is decided at an instant rather than spanning the physical
    /// press — a long press fires while the button is still down — so the down
    /// and the up are emitted together here instead of on the remote's edges.
    func fire(
        button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        gesture: RemoteGesture
    ) {
        post(button: button, remote: remote, gesture: gesture, isDown: true)
        post(button: button, remote: remote, gesture: gesture, isDown: false)
    }

    func reset(_ remote: SupportedRemoteID) {
        for button in RemoteProfiles.buttons(for: remote) {
            for gesture in RemoteGesture.allCases {
                defaults.removeObject(
                    forKey: mappingKey(gesture, for: button, remote: remote)
                )
                defaults.removeObject(
                    forKey: customKey(gesture, for: button, remote: remote)
                )
            }
        }
        revision += 1
    }
}
