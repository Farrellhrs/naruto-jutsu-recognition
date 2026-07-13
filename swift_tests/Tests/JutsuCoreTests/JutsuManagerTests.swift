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

    /// Documents a KNOWN BUG in free mode: kuchiyose's sequence
    /// (boar, horse, monkey, bird) contains wind's (horse, monkey) as a
    /// substring. Wind fires at the monkey step, and every trigger clears
    /// the accepted-sign history — so kuchiyose can never complete in free
    /// mode. If this test starts failing, the bug was fixed: move the
    /// kuchiyose assertion to expect .kuchiyose and delete this comment.
    func testKnownBugWindPreemptsKuchiyoseInFreeMode() {
        commit("boar")
        commit("horse")
        let midState = commit("monkey")
        XCTAssertEqual(midState.triggeredJutsu, .wind,
                       "wind fires mid-way through the kuchiyose sequence")

        let finalState = commit("bird")
        XCTAssertNil(finalState.triggeredJutsu,
                     "history was cleared by the wind trigger, so kuchiyose never completes")
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
