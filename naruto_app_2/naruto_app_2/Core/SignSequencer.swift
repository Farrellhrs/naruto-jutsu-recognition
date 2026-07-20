import Foundation

/// Turns noisy per-frame sign readings into committed signs and jutsu casts.
///
/// Design (fresh for v2):
/// - a *stability gate*: a sign commits after being read consistently for
///   `holdDuration`, exposed as 0-1 progress so the UI can draw a charge ring
/// - *longest-match-first* sequence resolution over the whole catalog
/// - *deferral*: a completed short jutsu waits `graceWindow` when the recent
///   signs still extend toward a longer jutsu that contains it
struct SignSequencer {
    struct Update {
        var committedSign: HandSign?
        var cast: Jutsu?
        var holdProgress: Double
        var recentSigns: [HandSign]
    }

    var holdDuration: TimeInterval = 0.30
    var refractory: TimeInterval = 0.40
    var graceWindow: TimeInterval = 1.6
    var historyLimit = 8

    private var candidate: HandSign?
    private var candidateSince: Date?
    private var committedCandidate = false
    private var lastCommit: (sign: HandSign, at: Date)?

    private(set) var history: [HandSign] = []
    private var historyTimes: [Date] = []
    private var deferred: (jutsu: Jutsu, expiresAt: Date)?

    /// Sequences sorted longest-first so the most specific jutsu wins ties.
    private static let catalog: [Jutsu] = Jutsu.allCases.sorted {
        $0.sequence.count > $1.sequence.count
    }

    // MARK: - Input

    mutating func observe(_ sign: HandSign?, at now: Date = Date()) -> Update {
        // Deferred cast fires once its grace window passes.
        if let parked = deferred, now >= parked.expiresAt {
            deferred = nil
            clearHistory()
            return Update(committedSign: nil, cast: parked.jutsu, holdProgress: 0, recentSigns: [])
        }

        guard let sign else {
            candidate = nil
            candidateSince = nil
            committedCandidate = false
            return Update(committedSign: nil, cast: nil, holdProgress: 0, recentSigns: recent)
        }

        if candidate != sign {
            candidate = sign
            candidateSince = now
            committedCandidate = false
            return Update(committedSign: nil, cast: nil, holdProgress: 0, recentSigns: recent)
        }

        let held = now.timeIntervalSince(candidateSince ?? now)
        let progress = min(1, held / holdDuration)

        guard !committedCandidate, held >= holdDuration else {
            return Update(committedSign: nil, cast: nil, holdProgress: committedCandidate ? 1 : progress, recentSigns: recent)
        }

        committedCandidate = true

        // Refractory: don't double-commit the same sign in quick succession.
        if let last = lastCommit, last.sign == sign, now.timeIntervalSince(last.at) < refractory {
            return Update(committedSign: nil, cast: nil, holdProgress: 1, recentSigns: recent)
        }
        lastCommit = (sign, now)

        history.append(sign)
        historyTimes.append(now)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
            historyTimes.removeFirst(historyTimes.count - historyLimit)
        }

        let cast = resolve(now: now)
        return Update(committedSign: sign, cast: cast, holdProgress: 1, recentSigns: recent)
    }

    mutating func reset() {
        candidate = nil
        candidateSince = nil
        committedCandidate = false
        lastCommit = nil
        deferred = nil
        clearHistory()
    }

    var recent: [HandSign] { Array(history.suffix(4)) }

    // MARK: - Resolution

    private mutating func resolve(now: Date) -> Jutsu? {
        guard let match = Self.catalog.first(where: { tailMatches($0.sequence) }) else {
            // No completion; keep or drop any parked cast depending on
            // whether the chain still extends toward a longer jutsu.
            if let parked = deferred {
                if longestExtendablePrefix() > parked.jutsu.sequence.count {
                    deferred = (parked.jutsu, now.addingTimeInterval(graceWindow))
                } else {
                    deferred = nil
                }
            }
            return nil
        }

        // Completed match. Defer it while a longer jutsu is still reachable.
        if longestExtendablePrefix() > match.sequence.count {
            deferred = (match, now.addingTimeInterval(graceWindow))
            return nil
        }

        deferred = nil
        clearHistory()
        return match
    }

    private func tailMatches(_ sequence: [HandSign]) -> Bool {
        guard history.count >= sequence.count else { return false }
        return Array(history.suffix(sequence.count)) == sequence
    }

    /// Longest L >= 2 where the last L committed signs equal the first L signs
    /// of a still-incomplete catalog sequence.
    private func longestExtendablePrefix() -> Int {
        var best = 0
        for jutsu in Self.catalog {
            let sequence = jutsu.sequence
            let cap = min(history.count, sequence.count - 1)
            guard cap >= 2 else { continue }
            for length in stride(from: cap, through: 2, by: -1) {
                if Array(history.suffix(length)) == Array(sequence.prefix(length)) {
                    best = max(best, length)
                    break
                }
            }
        }
        return best
    }

    private mutating func clearHistory() {
        history.removeAll(keepingCapacity: true)
        historyTimes.removeAll(keepingCapacity: true)
    }
}
