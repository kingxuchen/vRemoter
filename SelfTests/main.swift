import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

do {
    let protocolHandler = ATVVProtocol()
    try protocolHandler.acceptCapabilities(
        ATVVCapabilities(
            version: .v10,
            codecs: ATVVCodec.adpcm16k.rawValue,
            interactionModel: 0,
            frameSize: 120
        )
    )

    let packet = Data([0x12, 0x34, 0xAB, 0xCD, 0x56, 0x78])
    protocolHandler.beginAudioStream(codec: .adpcm16k)
    let first = protocolHandler.decodeAudio(packet)
    require(first != nil, "first stream did not decode")

    _ = protocolHandler.decodeAudio(Data(repeating: 0x77, count: 24))
    protocolHandler.endAudioStream()
    protocolHandler.beginAudioStream(codec: .adpcm16k)
    let second = protocolHandler.decodeAudio(packet)

    require(second != nil, "second stream did not decode")
    require(first?.samples == second?.samples, "ADPCM state was not reset")
    require(first?.sequence == 0, "first stream sequence did not start at zero")
    require(second?.sequence == 0, "second stream sequence did not restart")

    // AUDIO_SYNC is allowed on either side of AUDIO_START. Verify that START
    // no longer erases a sync received during MIC_OPEN.
    protocolHandler.prepareForAudioStream()
    protocolHandler.applyAudioSync(
        codec: .adpcm16k,
        sequence: 42,
        predictor: 1_234,
        stepIndex: 20
    )
    protocolHandler.beginAudioStream(codec: .adpcm16k)
    let synced = protocolHandler.decodeAudio(Data([0x12, 0x34]))
    require(synced?.sequence == 42, "AUDIO_START erased AUDIO_SYNC sequence")
    require(
        synced?.samples.first != first?.samples.first,
        "AUDIO_START erased AUDIO_SYNC decoder state"
    )

    // A sync applied during one active stream must not become the initializer
    // for the next stream.
    protocolHandler.applyAudioSync(
        codec: .adpcm16k,
        sequence: 70,
        predictor: -2_000,
        stepIndex: 30
    )
    _ = protocolHandler.decodeAudio(Data([0x77, 0x77]))
    protocolHandler.endAudioStream()
    protocolHandler.beginAudioStream(codec: .adpcm16k)
    let afterActiveSync = protocolHandler.decodeAudio(packet)
    require(
        afterActiveSync?.samples == first?.samples,
        "active-stream AUDIO_SYNC leaked into the next stream"
    )
    require(
        afterActiveSync?.sequence == 0,
        "new unsynchronized stream sequence did not reset"
    )

    print("PASS: repeated AUDIO_START resets unsynchronized streams")
    print("PASS: AUDIO_START preserves a fresh AUDIO_SYNC")
    print("PASS: active-stream AUDIO_SYNC does not leak into next stream")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

// MARK: - Shortcut value type

// The left/right distinction is the whole point of this type: the previous
// trigger stored both key codes for one concept and picked the smaller one, so
// the right-hand variants could never be sent. Right Command — the trigger used
// by the voice input target this project is being generalized for — was among
// the casualties.
func testShortcutDistinguishesLeftFromRight() {
    let rightCommand = Shortcut(keyCode: ShortcutKey.rightCommand, modifierFlags: 0)
    let leftCommand = Shortcut(keyCode: ShortcutKey.leftCommand, modifierFlags: 0)

    require(
        rightCommand != leftCommand,
        "left and right Command must not collapse into one value"
    )
    require(
        rightCommand.displayText.contains("右"),
        "right Command must be distinguishable in the echoed text"
    )
    require(
        leftCommand.displayText.contains("左"),
        "left Command must be distinguishable in the echoed text"
    )
}

func testShortcutCarriesCombinationWithMainKey() {
    let optionSpace = Shortcut(
        keyCode: ShortcutKey.space,
        modifierFlags: ShortcutModifier.option
    )
    require(
        optionSpace.displayText.contains("⌥"),
        "a combination with a main key must show its modifier"
    )
    require(
        optionSpace.displayText.contains("空格"),
        "a combination with a main key must name that key"
    )
}

func testShortcutCarriesTwoModifiers() {
    let controlShiftV = Shortcut(
        keyCode: ShortcutKey.v,
        modifierFlags: ShortcutModifier.control | ShortcutModifier.shift
    )
    let text = controlShiftV.displayText
    require(
        text.contains("⌃") && text.contains("⇧"),
        "two modifiers must both be shown"
    )
    require(
        text.range(of: "⌃")!.lowerBound < text.range(of: "⇧")!.lowerBound,
        "modifiers must render in the macOS order ⌃ before ⇧"
    )
}

func testShortcutRoundTripsAnObservedPress() {
    // What the event tap reports for a real press is stored verbatim, so a
    // bare modifier and a modified key are both representable without guessing.
    // The value is deliberately arbitrary: this asserts pass-through, not
    // interpretation.
    let observed = Shortcut(keyCode: 0x0A, modifierFlags: ShortcutModifier.control)
    require(
        observed.keyCode == 0x0A && observed.modifierFlags == ShortcutModifier.control,
        "a captured press must be stored exactly as observed, uninterpreted"
    )
}

func testShortcutRejectsSystemReservedKeys() {
    require(
        !Shortcut.isCapturable(keyCode: ShortcutKey.brightnessUp),
        "a system-reserved key must not be recordable"
    )
    require(
        Shortcut.isCapturable(keyCode: ShortcutKey.rightCommand),
        "an ordinary key must be recordable"
    )
}

func testShortcutDownCarriesModifiersAndUpClearsThem() {
    let optionSpace = Shortcut(
        keyCode: ShortcutKey.space,
        modifierFlags: ShortcutModifier.option
    )
    require(
        optionSpace.downEvent().modifierFlags == ShortcutModifier.option,
        "the key-down event must carry the modifiers"
    )
    require(
        optionSpace.upEvent().modifierFlags == 0,
        "the key-up event must clear modifiers so the target sees a clean release"
    )
    require(
        optionSpace.upEvent().keyCode == ShortcutKey.space,
        "the key-up event must repeat the same key"
    )
}

func testShortcutDistinguishesWhetherAModifierWasAlsoHeld() {
    // A real press of left Command may be reported either as a bare modifier or
    // as that key with the Command flag set, depending on the source. Storing
    // verbatim keeps both representable; keeping them distinct is what lets the
    // picker later decide whether to normalise them.
    let bare = Shortcut(keyCode: ShortcutKey.leftCommand, modifierFlags: 0)
    let flagged = Shortcut(
        keyCode: ShortcutKey.leftCommand,
        modifierFlags: ShortcutModifier.command
    )
    require(
        bare != flagged,
        "a bare modifier and a flagged modifier must remain distinguishable"
    )
    require(
        bare.displayText == flagged.displayText,
        "both must read back the same, since a user pressed one key"
    )
}

func testShortcutNamesLettersByKeyboardLayoutNotAlphabet() {
    // `kVK_ANSI_*` is the US keyboard layout, not the alphabet: V is 0x09 and S
    // is 0x01, while 0x12 is the digit 1. An earlier draft derived letter names
    // arithmetically from the key code and rendered every letter wrong.
    require(
        Shortcut(keyCode: ShortcutKey.v, modifierFlags: 0).displayText == "V",
        "V must render as V"
    )
    require(
        Shortcut(keyCode: 0x01, modifierFlags: 0).displayText == "S",
        "key code 0x01 is S, not a letter derived from its position"
    )
    require(
        Shortcut(keyCode: 0x12, modifierFlags: 0).displayText == "1",
        "key code 0x12 is the digit 1, not the 19th letter"
    )
    require(
        Shortcut(keyCode: 0x16, modifierFlags: 0).displayText == "6",
        "the digit row is not in numeric order on a US layout"
    )
}

// MARK: - Shortcut migration

func testShortcutMigrationDistinguishesThreeCases() {
    let option = Shortcut(
        keyCode: ShortcutKey.leftOption,
        modifierFlags: ShortcutModifier.option
    )

    // 1. The user chose a trigger explicitly under the old picker.
    require(
        ShortcutMigration.decide(
            persistedTriggerKey: "command",
            hasOtherPersistedSettings: true
        ) == .stored(Shortcut(
            keyCode: ShortcutKey.leftCommand,
            modifierFlags: ShortcutModifier.command
        )),
        "an explicitly stored legacy value must migrate to that exact shortcut"
    )

    // 2. A legacy user who never touched the picker. The old default was never
    //    written to storage, so it must be reconstructed here or these users
    //    would silently lose their trigger.
    require(
        ShortcutMigration.decide(
            persistedTriggerKey: nil,
            hasOtherPersistedSettings: true
        ) == .legacyImplicit(option),
        "a legacy user who never set a trigger must keep the old behavior"
    )

    // 3. A fresh install gets nothing: there is no shortcut to guess at.
    require(
        ShortcutMigration.decide(
            persistedTriggerKey: nil,
            hasOtherPersistedSettings: false
        ) == .freshInstall,
        "a fresh install must not be given a default shortcut"
    )
}

func testShortcutMigrationFallsBackOnUnrecognisedLegacyValue() {
    let fallback = ShortcutMigration.decide(
        persistedTriggerKey: "left-elbow",
        hasOtherPersistedSettings: true
    )
    require(
        fallback == .legacyImplicit(Shortcut(
            keyCode: ShortcutKey.leftOption,
            modifierFlags: ShortcutModifier.option
        )),
        "an unrecognised stored value must fall back, not crash or guess"
    )
}

// MARK: - Toggle shape and observation

/// Stands in for the real CoreGraphics poster so the toggle's shape can be
/// asserted without touching the system event layer.
private final class CountingPoster: ShortcutEventPosting {
    private(set) var posted: [ShortcutKeyEvent] = []
    private(set) var markers: [Int64] = []

    func post(_ event: ShortcutKeyEvent, marker: Int64) {
        posted.append(event)
        markers.append(marker)
    }
}

func testShortcutTapSequenceIsPressThenRelease() {
    let rightCommand = Shortcut(keyCode: ShortcutKey.rightCommand, modifierFlags: 0)
    let sequence = rightCommand.tapSequence()

    require(sequence.count == 2, "a toggle is exactly two events")
    require(
        sequence[0] == rightCommand.downEvent(),
        "the first event is the press"
    )
    require(
        sequence[1] == rightCommand.upEvent(),
        "the second event is the release"
    )
    require(
        sequence[0] != sequence[1],
        "press and release must differ, or the target app cannot see a toggle"
    )
}

func testShortcutMatchesItsOwnKeyAndNotOthers() {
    let rightCommand = Shortcut(
        keyCode: ShortcutKey.rightCommand,
        modifierFlags: ShortcutModifier.command
    )
    require(
        rightCommand.matches(keyCode: ShortcutKey.rightCommand),
        "a shortcut must match its own key"
    )
    require(
        !rightCommand.matches(keyCode: ShortcutKey.leftCommand),
        "right Command must not be satisfied by left Command"
    )
    require(
        !rightCommand.matches(keyCode: ShortcutKey.space),
        "a shortcut must not match an unrelated key"
    )
}

func testShortcutMatchesBareAndFlaggedFormOfOneModifier() {
    // The event tap may report a modifier press either bare or with its own
    // flag set. Both are the same physical press, so the observer must accept
    // either rather than silently missing the press.
    let bare = Shortcut(keyCode: ShortcutKey.rightCommand, modifierFlags: 0)
    let flagged = Shortcut(
        keyCode: ShortcutKey.rightCommand,
        modifierFlags: ShortcutModifier.command
    )
    require(
        bare.matches(keyCode: ShortcutKey.rightCommand)
            && flagged.matches(keyCode: ShortcutKey.rightCommand),
        "one modifier press must be recognised however it was reported"
    )
}
func testShortcutBareModifierStillProducesTwoDistinctEvents() {
    // The trigger this work exists for is a bare right Command. Recorded bare
    // it carries no flag, so a naive press/release pair would be byte for byte
    // identical and the target would see the key pressed twice and never
    // released. The press must therefore report the modifier's own flag.
    let bare = Shortcut(keyCode: ShortcutKey.rightCommand, modifierFlags: 0)
    let sequence = bare.tapSequence()

    require(
        sequence[0].modifierFlags == ShortcutModifier.command,
        "a modifier press must report its own flag"
    )
    require(
        sequence[0] != sequence[1],
        "press and release of a bare modifier must still be distinguishable"
    )
    require(
        sequence[1].modifierFlags == 0,
        "the release must clear the modifier"
    )
}

func testShortcutMainKeyPressIsUnchangedByTheModifierRule() {
    // The rule above applies only to modifier keys. A combination's press must
    // carry exactly the modifiers that were recorded.
    let controlShiftV = Shortcut(
        keyCode: ShortcutKey.v,
        modifierFlags: ShortcutModifier.control | ShortcutModifier.shift
    )
    require(
        controlShiftV.downEvent().modifierFlags
            == ShortcutModifier.control | ShortcutModifier.shift,
        "a combination's press must carry exactly the recorded modifiers"
    )
}

func testShortcutReadsBackAFnMigratedFromTheOldPicker() {
    // A 1.1.1 install can have stored Fn as its trigger. Fn is no longer
    // offered for recording, but a migrated value still has to read back as
    // something a person recognises rather than as a raw key code.
    let migrated = Shortcut(keyCode: ShortcutKey.fn, modifierFlags: ShortcutModifier.function)
    require(
        migrated.displayText == "Fn / Globe",
        "a migrated Fn trigger must read back by name, not as a key code"
    )
    require(
        !migrated.displayText.contains("键码"),
        "a migrated trigger must never show a raw key code to the user"
    )
}

// MARK: - Storage round trip

func testShortcutRecordedAfterTheAppHasReadIsNotIgnored() {
    // Regression. The real sequence is: the app reads the shortcut at launch,
    // the user then records a different one. A getter that memoised its
    // migrated value kept serving the launch-time shortcut, so the console
    // displayed the newly recorded key while the app actually emitted the old
    // one — pressing the remote voice key fired the old key.
    AppStorage.shortcut = nil
    let atLaunch = AppStorage.shortcut

    let recorded = Shortcut(
        keyCode: ShortcutKey.rightCommand,
        modifierFlags: ShortcutModifier.command
    )
    AppStorage.shortcut = recorded

    require(
        AppStorage.shortcut == recorded,
        "a shortcut recorded after the first read must be served back"
    )
    require(
        AppStorage.shortcut?.keyCode == ShortcutKey.rightCommand,
        "the recorded key must not be replaced by the launch-time key"
    )
    _ = atLaunch

    AppStorage.shortcut = nil
    require(
        AppStorage.shortcut == nil,
        "clearing must be readable too, not just writing"
    )
}

func testShortcutSurvivesBeingRewritten() {
    AppStorage.shortcut = nil
    _ = AppStorage.shortcut
    let first = Shortcut(
        keyCode: ShortcutKey.rightCommand,
        modifierFlags: ShortcutModifier.command
    )
    let second = Shortcut(
        keyCode: ShortcutKey.space,
        modifierFlags: ShortcutModifier.option
    )
    AppStorage.shortcut = first
    AppStorage.shortcut = second
    require(
        AppStorage.shortcut == second,
        "the most recently recorded shortcut must win"
    )
    AppStorage.shortcut = nil
}

// MARK: - Device consumer probe

func testConsumerProbeFindsTheProcessHoldingTheDevice() {
    let picture: [(pid: pid_t, deviceNames: [String])] = [
        (100, ["MacBook Pro Microphone"]),
        (200, ["vRemoteDr 2ch"]),
        (300, ["vRemoteDr 2ch", "MacBook Pro Microphone"]),
    ]
    let found = VoiceDeviceConsumer.holders(
        among: picture,
        targetDeviceName: "vRemoteDr 2ch",
        excludedPids: []
    )
    require(found.count == 2, "both processes holding the device are reported")
    require(
        found.map(\.pid) == [200, 300],
        "only the processes actually holding it are reported"
    )
}

func testConsumerProbeExcludesThisApp() {
    // vRemoter holds the device itself through its IOProc, so counting itself
    // would make every answer "held" and the guard would never let go.
    let picture: [(pid: pid_t, deviceNames: [String])] = [
        (42, ["vRemoteDr 2ch"]),
        (200, ["vRemoteDr 2ch"]),
    ]
    let found = VoiceDeviceConsumer.holders(
        among: picture,
        targetDeviceName: "vRemoteDr 2ch",
        excludedPids: [42]
    )
    require(
        found.map(\.pid) == [200],
        "this app must never be counted as a consumer"
    )
}

func testConsumerProbeIgnoresSimilarNames() {
    let picture: [(pid: pid_t, deviceNames: [String])] = [
        (200, ["vRemoteDr 4ch"]),
        (201, ["vRemoteDr 2ch Pro"]),
        (202, ["vremoteDR 2ch"]),
    ]
    let found = VoiceDeviceConsumer.holders(
        among: picture,
        targetDeviceName: "vRemoteDr 2ch",
        excludedPids: []
    )
    require(
        found.map(\.pid) == [202],
        "the device name is matched case-insensitively and only as a whole name"
    )
}

func testConsumerAnswerReportsHeldAndUnknown() {
    require(
        VoiceDeviceConsumer.Answer.held(by: []).isHeld,
        "a held answer must read as held even with an empty list"
    )
    require(
        !VoiceDeviceConsumer.Answer.none.isHeld,
        "an empty picture must not read as held"
    )
    require(
        !VoiceDeviceConsumer.Answer.unknown.isHeld,
        "an unreadable picture must never be treated as held"
    )
}

// MARK: - Shortcut self-test entry

func runShortcutSelfTests() {
    testShortcutDistinguishesLeftFromRight()
    testShortcutCarriesCombinationWithMainKey()
    testShortcutCarriesTwoModifiers()
    testShortcutRoundTripsAnObservedPress()
    testShortcutRejectsSystemReservedKeys()
    testShortcutNamesLettersByKeyboardLayoutNotAlphabet()
    testShortcutDownCarriesModifiersAndUpClearsThem()
    testShortcutDistinguishesWhetherAModifierWasAlsoHeld()
    testShortcutMigrationDistinguishesThreeCases()
    testShortcutMigrationFallsBackOnUnrecognisedLegacyValue()
    testShortcutTapSequenceIsPressThenRelease()
    testShortcutMatchesItsOwnKeyAndNotOthers()
    testShortcutMatchesBareAndFlaggedFormOfOneModifier()
    testShortcutBareModifierStillProducesTwoDistinctEvents()
    testShortcutMainKeyPressIsUnchangedByTheModifierRule()
    testShortcutReadsBackAFnMigratedFromTheOldPicker()
    testShortcutRecordedAfterTheAppHasReadIsNotIgnored()
    testShortcutSurvivesBeingRewritten()
    testConsumerProbeFindsTheProcessHoldingTheDevice()
    testConsumerProbeExcludesThisApp()
    testConsumerProbeIgnoresSimilarNames()
    testConsumerAnswerReportsHeldAndUnknown()

    print("PASS: left/right variants stay distinct")
    print("PASS: combinations with a main key are representable")
    print("PASS: two-modifier combinations render in macOS order")
    print("PASS: a captured press is stored verbatim")
    print("PASS: system-reserved keys are not recordable")
    print("PASS: letters are named by US layout, not by arithmetic")
    print("PASS: key-down carries modifiers, key-up clears them")
    print("PASS: bare and flagged modifier presses stay distinguishable")
    print("PASS: migration separates stored / legacy-implicit / fresh install")
    print("PASS: unrecognised legacy values fall back safely")
    print("PASS: a toggle is a press followed by a release")
    print("PASS: a shortcut matches its own key only")
    print("PASS: one modifier press is recognised however reported")
    print("PASS: a bare modifier still produces a press and a release")
    print("PASS: a combination press carries exactly its modifiers")
    print("PASS: a migrated Fn trigger reads back by name")
    print("PASS: a shortcut recorded after the first read is served back")
    print("PASS: the most recently recorded shortcut wins")
    print("PASS: the probe finds who holds the device")
    print("PASS: the probe excludes this app")
    print("PASS: the probe matches only the whole name")
    print("PASS: an unreadable picture is never held")
}

runShortcutSelfTests()
