import XCTest
@testable import JutsuCore

/// Tests for the sign-sequence state machine that turns noisy per-frame
/// classifier output into committed signs and jutsu triggers.
final class JutsuManagerTests: XCTestCase {
    private var manager: JutsuManager!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        manager = JutsuManager()
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    /// Feed the same label long enough to pass the 300 ms hold gate,
    /// advancing the injected clock. Returns the state at commit time.
    @discardableResult
    private func commit(_ label: String,
                        mode: AppMode = .free,
                        target: JutsuType? = nil) -> JutsuState {
        _ = process(label, mode: mode, target: target)          // start hold
        clock = clock.addingTimeInterval(0.31)                  // pass 300 ms
        let state = process(label, mode: mode, target: target)  // commit
        clock = clock.addingTimeInterval(0.40)                  // clear debounce window
        return state
    }

    private func process(_ label: String,
                         mode: AppMode = .free,
                         target: JutsuType? = nil) -> JutsuState {
        manager.processCandidate(
            label: label,
            score: 0.9,
            overlay: [],
            faceDirection: nil,
            mode: mode,
            targetJutsu: target,
            now: clock
        )
    }

    // MARK: - Hold-to-commit gate

    func testSignIsNotCommittedBeforeHoldDuration() {
        _ = process("ox")
        clock = clock.addingTimeInterval(0.10)  // only 100 ms
        let state = process("ox")
        XCTAssertNil(state.triggeredJutsu)
        XCTAssertTrue(manager.seenSigns.isEmpty, "sign committed before the 300 ms hold elapsed")
    }

    func testSignCommitsAfterHoldDuration() {
        commit("ox")
        XCTAssertTrue(manager.seenSigns.contains("ox"))
    }

    func testFlickeringLabelsNeverCommit() {
        // Alternate labels faster than the hold window — classifier flicker.
        for _ in 0..<10 {
            _ = process("ox")
            clock = clock.addingTimeInterval(0.1)
            _ = process("monkey")
            clock = clock.addingTimeInterval(0.1)
        }
        XCTAssertTrue(manager.seenSigns.isEmpty, "flickering labels must not commit any sign")
    }

    // MARK: - Label normalization

    func testHareAliasNormalizesToRabbit() {
        commit("hare")
        XCTAssertTrue(manager.seenSigns.contains("rabbit"),
                      "'hare' (model label) should be committed as 'rabbit'")
    }

    func testLabelNormalizationHandlesCaseAndWhitespace() {
        commit("  OX ")
        XCTAssertTrue(manager.seenSigns.contains("ox"))
    }

    // MARK: - Free-mode sequence triggers

    func testChidoriTriggersOnOxMonkey() {
        commit("ox")
        let state = commit("monkey")
        XCTAssertEqual(state.triggeredJutsu, .lightning)
    }

    func testRasenganTriggersOnMonkeyBird() {
        commit("monkey")
        let state = commit("bird")
        XCTAssertEqual(state.triggeredJutsu, .rasengan)
    }

    func testInterruptedSequenceDoesNotTrigger() {
        commit("ox")
        commit("tiger")   // breaks the ox -> monkey tail
        let state = commit("monkey")
        XCTAssertNil(state.triggeredJutsu)
    }

    func testKuchiyoseIsReachableInBattleMode() {
        // In battle mode the counter follows the target sequence directly,
        // so the wind-substring overlap (see the quirk test below) does not
        // interfere.
        commit("boar", mode: .battle, target: .kuchiyose)
        commit("horse", mode: .battle, target: .kuchiyose)
        commit("monkey", mode: .battle, target: .kuchiyose)
        let state = commit("bird", mode: .battle, target: .kuchiyose)
        XCTAssertEqual(state.triggeredJutsu, .kuchiyose)
    }

    func testKuchiyoseFailsWhenSequenceIsTooSlow() {
        commit("boar")
        clock = clock.addingTimeInterval(5.0)  // exceed the 4.5 s window
        commit("horse")
        commit("monkey")
        let state = commit("bird")
        // The timed-out kuchiyose must not fire. (The tail monkey -> bird
        // still legitimately matches rasengan — see the overlap test below.)
        XCTAssertNotEqual(state.triggeredJutsu, .kuchiyose,
                          "kuchiyose must respect its 4.5 s sequence time limit")
    }

    // MARK: - Deferred triggers (overlapping sequences)

    /// Kuchiyose's sequence (boar, horse, monkey, bird) contains wind's
    /// (horse, monkey) as a substring. The deferral fix parks wind while the
    /// history is still a live prefix of kuchiyose, so the full sequence can
    /// complete in free mode.
    func testKuchiyoseCompletesInFreeModeViaDeferral() {
        commit("boar")
        commit("horse")
        let midState = commit("monkey")
        XCTAssertNil(midState.triggeredJutsu,
                     "wind must be deferred while kuchiyose is still in progress")

        let finalState = commit("bird")
        XCTAssertEqual(finalState.triggeredJutsu, .kuchiyose)
    }

    func testStandaloneWindStillFiresImmediately() {
        // Without the boar prefix there is no longer-sequence overlap,
        // so wind must not be delayed.
        commit("horse")
        let state = commit("monkey")
        XCTAssertEqual(state.triggeredJutsu, .wind)
    }

    func testDeferredWindFiresAfterGraceWindowWhenPlayerStops() {
        commit("boar")
        commit("horse")
        let midState = commit("monkey")
        XCTAssertNil(midState.triggeredJutsu)

        // Player stops signing; after the grace window the parked wind fires.
        clock = clock.addingTimeInterval(2.0)
        let deferredState = manager.tickFireExpiry(now: clock)
        XCTAssertEqual(deferredState?.triggeredJutsu, .wind,
                       "the deferred wind should fire once the grace window expires")
    }

    // MARK: - Tutorial mode (kuchiyose learning rules)

    func testTutorialKuchiyoseHasNoTimeLimit() {
        // A learner takes ~2s per sign — far beyond the old 4.5s window.
        for sign in ["boar", "horse", "monkey"] {
            commit(sign, mode: .tutorial, target: .kuchiyose)
            clock = clock.addingTimeInterval(2.0)
        }
        let state = commit("bird", mode: .tutorial, target: .kuchiyose)
        XCTAssertEqual(state.triggeredJutsu, .kuchiyose,
                       "tutorial must not enforce the kuchiyose time limit")
    }

    func testTutorialKuchiyoseSurvivesBriefWrongSign() {
        commit("boar", mode: .tutorial, target: .kuchiyose)
        // One misclassified commit must not nuke progress in tutorial.
        commit("tiger", mode: .tutorial, target: .kuchiyose)
        XCTAssertEqual(manager.currentSequenceProgressCount, 1,
                       "a brief wrong sign should use the grace period, not reset kuchiyose progress")

        commit("horse", mode: .tutorial, target: .kuchiyose)
        commit("monkey", mode: .tutorial, target: .kuchiyose)
        let state = commit("bird", mode: .tutorial, target: .kuchiyose)
        XCTAssertEqual(state.triggeredJutsu, .kuchiyose)
    }

    func testSpeedKuchiyoseStillEnforcesTimeLimit() {
        for sign in ["boar", "horse", "monkey"] {
            commit(sign, mode: .speed, target: .kuchiyose)
            clock = clock.addingTimeInterval(3.0)
        }
        let state = commit("bird", mode: .speed, target: .kuchiyose)
        XCTAssertNil(state.triggeredJutsu,
                     "speed mode keeps the kuchiyose time-limit challenge")
    }

    // MARK: - Versus mode

    func testVersusModeTriggersLikeFreeMode() {
        commit("ox", mode: .versus)
        let state = commit("monkey", mode: .versus)
        XCTAssertEqual(state.triggeredJutsu, .lightning)
    }

    func testVersusDamageAndCounterTablesAreConsistent() {
        for jutsu in JutsuType.allCases {
            XCTAssertGreaterThan(jutsu.versusDamage, 0)
            // Counter relationships must be symmetric enough to be learnable:
            // every jutsu has a defined counter.
            _ = jutsu.counteredBy
        }
        XCTAssertEqual(JutsuType.fireball.counteredBy, .waterDragon)
        XCTAssertEqual(JutsuType.lightning.counteredBy, .rasengan)
    }

    // MARK: - Battle mode

    func testBattleCounterAdvancesAndTriggersTarget() {
        commit("ox", mode: .battle, target: .lightning)
        XCTAssertEqual(manager.currentSequenceProgressCount, 1)

        let state = commit("monkey", mode: .battle, target: .lightning)
        XCTAssertEqual(state.triggeredJutsu, .lightning)
    }

    func testBattleWrongSignDoesNotAdvanceCounter() {
        commit("ox", mode: .battle, target: .lightning)
        commit("tiger", mode: .battle, target: .lightning)  // wrong sign, briefly held
        XCTAssertEqual(manager.currentSequenceProgressCount, 1,
                       "a briefly-held wrong sign should not advance or reset the counter")
    }

    // MARK: - Reset

    func testResetAllClearsState() {
        commit("ox")
        manager.resetAll()
        XCTAssertTrue(manager.seenSigns.isEmpty)
        XCTAssertEqual(manager.currentSequenceProgressCount, 0)
    }
}
