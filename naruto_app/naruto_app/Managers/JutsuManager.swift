import Foundation
import CoreGraphics

final class JutsuManager {
    private let requiredHoldDuration: TimeInterval = 0.3
    private let wrongSignResetDelay: TimeInterval = 2.0
    private let kuchiyoseSequenceTimeLimit: TimeInterval = 4.5
    private let knownSigns: Set<String> = [
        "bird", "boar", "dog", "dragon", "hare", "horse", "monkey",
        "ox", "ram", "rat", "snake", "tiger", "rabbit"
    ]
    private let maxSequenceLength: Int = JutsuType.allCases.map { $0.signSequence.count }.max() ?? 4

    private var acceptedSignHistory: [String] = []
    private var acceptedSignTimestamps: [Date] = []
    private var targetProgressCount = 0
    private var targetSequenceStartedAt: Date?
    private var sequentialWrongLabel: String?
    private var sequentialWrongStart: Date?
    private var pendingGestureLabel: String?
    private var pendingGestureStart: Date?
    private var pendingGestureCommitted = false
    private var lastAcceptedLabel: String?
    private var lastAcceptedAt: Date = .distantPast
    private var fireUntil: Date?

    private(set) var fireHands: [CGPoint] = []
    private(set) var fireScales: [CGFloat] = []
    private(set) var mouthPoint: CGPoint?
    private(set) var fireballDirectionVector: CGVector?
    private(set) var fireballDirectionVector3D: FaceVector3D?
    private(set) var fireballMouthOpen = false
    private(set) var fireballMouthOpenNormalized: CGFloat = 0
    private(set) var fireballDepthScale: CGFloat = 1.0
    private(set) var fireActive = false
    private(set) var activeEffectJutsu: JutsuType?
    private(set) var seenSigns: Set<String> = []
    var currentSequenceProgressCount: Int { targetProgressCount }

    private struct GestureCommitResult {
        let trigger: JutsuType?
        let status: String
    }

    private enum TargetProgressUpdate {
        case advanced
        case wrongIgnored(remainingMs: Int)
        case timedOut
        case wrongReset
    }

    func resetAll() {
        acceptedSignHistory.removeAll(keepingCapacity: true)
        acceptedSignTimestamps.removeAll(keepingCapacity: true)
        targetProgressCount = 0
        targetSequenceStartedAt = nil
        sequentialWrongLabel = nil
        sequentialWrongStart = nil
        resetGestureHoldState()
        fireUntil = nil
        fireHands = []
        fireScales = []
        mouthPoint = nil
        fireballDirectionVector = nil
        fireballDirectionVector3D = nil
        fireballMouthOpen = false
        fireballMouthOpenNormalized = 0
        fireballDepthScale = 1.0
        fireActive = false
        activeEffectJutsu = nil
        seenSigns = []
        lastAcceptedLabel = nil
        lastAcceptedAt = .distantPast
    }

    func resetGestureHoldState() {
        pendingGestureLabel = nil
        pendingGestureStart = nil
        pendingGestureCommitted = false
    }

    func tickFireExpiry(now: Date = Date()) {
        guard let until = fireUntil else { return }
        if now >= until {
            deactivateEffectState()
        }
    }

    func updateLiveFireHands(with overlay: [[CGPoint]]) {
        applyEffectHands(from: overlay)
    }

    func updateLiveFaceDirection(_ faceDirection: FaceDirectionObservation?) {
        guard fireActive, (activeEffectJutsu == .fireball || activeEffectJutsu == .burningAsh) else { return }
        if let faceDirection {
            mouthPoint = faceDirection.mouthPoint
            fireballDirectionVector = faceDirection.directionVector
            fireballDirectionVector3D = faceDirection.directionVector3D
            fireballMouthOpen = faceDirection.mouthOpen
            fireballMouthOpenNormalized = faceDirection.normalizedMouthOpen
            fireballDepthScale = faceDirection.depthScaleFactor
        }
    }

    func processCandidate(
        label: String,
        score _: Double,
        overlay: [[CGPoint]],
        faceDirection: FaceDirectionObservation?,
        mode: AppMode,
        targetJutsu: JutsuType?
    ) -> JutsuState {
        let now = Date()
        let normalized = normalizeSignLabel(label)

        if pendingGestureLabel != normalized {
            pendingGestureLabel = normalized
            pendingGestureStart = now
            pendingGestureCommitted = false
            return snapshot(status: "Hold \(normalized) 200ms", triggeredJutsu: nil)
        }

        guard let start = pendingGestureStart else {
            pendingGestureStart = now
            pendingGestureCommitted = false
            return snapshot(status: "Hold \(normalized) 200ms", triggeredJutsu: nil)
        }

        let elapsed = now.timeIntervalSince(start)
        if !pendingGestureCommitted && elapsed >= requiredHoldDuration {
            pendingGestureCommitted = true
            let result = registerAcceptedGesture(
                label: normalized,
                overlay: overlay,
                faceDirection: faceDirection,
                mode: mode,
                targetJutsu: targetJutsu,
                now: now
            )
            let status: String
            if let triggered = result.trigger {
                status = "\(triggered.title) Jutsu!"
            } else {
                status = result.status
            }
            return snapshot(status: status, triggeredJutsu: result.trigger)
        }

        if pendingGestureCommitted,
           let wrongStatus = maybeResetSequenceForPersistentWrongLabel(
               currentLabel: normalized,
               mode: mode,
               targetJutsu: targetJutsu,
               now: now
           ) {
            return snapshot(status: wrongStatus, triggeredJutsu: nil)
        }

        let remainingMs = max(0, Int((requiredHoldDuration - elapsed) * 1000))
        return snapshot(status: "Holding \(normalized)... \(remainingMs)ms", triggeredJutsu: nil)
    }

    private func registerAcceptedGesture(
        label: String,
        overlay: [[CGPoint]],
        faceDirection: FaceDirectionObservation?,
        mode: AppMode,
        targetJutsu: JutsuType?,
        now: Date
    ) -> GestureCommitResult {
        if label == lastAcceptedLabel && now.timeIntervalSince(lastAcceptedAt) < 0.35 {
            return GestureCommitResult(trigger: nil, status: "Prediction: \(label)")
        }

        guard knownSigns.contains(label) else {
            return GestureCommitResult(trigger: nil, status: "Prediction: \(label)")
        }

        lastAcceptedLabel = label
        lastAcceptedAt = now

        let trigger: JutsuType?
        let progressStatus: String
        switch mode {
        case .free:
            appendAcceptedSign(label, at: now)
            seenSigns = Set(acceptedSignHistory)

            if matchesTail(JutsuType.burningAsh.signSequence) {
                trigger = .burningAsh
            } else if matchesTail(JutsuType.lightning.signSequence) {
                trigger = .lightning
            } else if matchesTailWithinDuration(JutsuType.kuchiyose.signSequence, maxDuration: kuchiyoseSequenceTimeLimit) {
                trigger = .kuchiyose
            } else if matchesTail(JutsuType.fireball.signSequence) {
                // In free mode, same sequence can map to multiple fire-style jutsu.
                // Prefer fireball when user performs blowing gesture toward camera.
                let canUseFireball = (faceDirection?.mouthOpen == true) && ((faceDirection?.vectorZ ?? 1) < 0)
                trigger = canUseFireball ? .fireball : .fire
            } else if matchesTail(JutsuType.wind.signSequence) {
                trigger = .wind
            } else if matchesTail(JutsuType.rasengan.signSequence) {
                trigger = .rasengan
            } else if matchesTail(JutsuType.waterDragon.signSequence) {
                trigger = .waterDragon
            } else {
                trigger = nil
            }

            let recent = acceptedSignHistory.suffix(3).joined(separator: " -> ")
            progressStatus = recent.isEmpty ? "Prediction: \(label)" : "Sequence: \(recent)"
        case .battle:
            if let targetJutsu {
                let progressUpdate = updateTargetProgress(with: label, targetJutsu: targetJutsu, now: now)
                if targetProgressCount == targetJutsu.signSequence.count {
                    trigger = targetJutsu
                } else {
                    trigger = nil
                }

                switch progressUpdate {
                case .advanced:
                    progressStatus = "Counter \(targetProgressCount)/\(targetJutsu.signSequence.count)"
                case .wrongIgnored:
                    progressStatus = "Follow the counter sequence"
                case .timedOut:
                    progressStatus = "Counter timed out. Start over"
                case .wrongReset:
                    progressStatus = "Counter reset"
                }
            } else {
                targetProgressCount = 0
                targetSequenceStartedAt = nil
                sequentialWrongLabel = nil
                sequentialWrongStart = nil

                appendAcceptedSign(label, at: now)
                seenSigns = Set(acceptedSignHistory)

                if matchesTail(JutsuType.burningAsh.signSequence) {
                    trigger = .burningAsh
                } else if matchesTail(JutsuType.lightning.signSequence) {
                    trigger = .lightning
                } else if matchesTailWithinDuration(JutsuType.kuchiyose.signSequence, maxDuration: kuchiyoseSequenceTimeLimit) {
                    trigger = .kuchiyose
                } else if matchesTail(JutsuType.fireball.signSequence) {
                    let canUseFireball = (faceDirection?.mouthOpen == true) && ((faceDirection?.vectorZ ?? 1) < 0)
                    trigger = canUseFireball ? .fireball : .fire
                } else if matchesTail(JutsuType.wind.signSequence) {
                    trigger = .wind
                } else if matchesTail(JutsuType.rasengan.signSequence) {
                    trigger = .rasengan
                } else if matchesTail(JutsuType.waterDragon.signSequence) {
                    trigger = .waterDragon
                } else {
                    trigger = nil
                }

                let recent = acceptedSignHistory.suffix(3).joined(separator: " -> ")
                progressStatus = recent.isEmpty ? "Prediction: \(label)" : "Sequence: \(recent)"
            }
        case .tutorial, .speed:
            guard let targetJutsu else {
                return GestureCommitResult(trigger: nil, status: "Prediction: \(label)")
            }

            let progressUpdate = updateTargetProgress(with: label, targetJutsu: targetJutsu, now: now)
            if targetProgressCount == targetJutsu.signSequence.count {
                trigger = targetJutsu
            } else {
                trigger = nil
            }

            switch progressUpdate {
            case .advanced:
                progressStatus = "Sequence \(targetProgressCount)/\(targetJutsu.signSequence.count)"
            case .wrongIgnored(let remainingMs):
                progressStatus = "Wrong sign ignored (\(remainingMs)ms before reset)"
            case .timedOut:
                progressStatus = "Sequence timed out. Start over"
            case .wrongReset:
                progressStatus = "Wrong sign. Sequence reset"
            }
        }

        guard let trigger else {
            return GestureCommitResult(trigger: nil, status: progressStatus)
        }

        applyEffectHands(from: overlay)

        fireActive = !fireHands.isEmpty
        activeEffectJutsu = trigger
        self.mouthPoint = faceDirection?.mouthPoint
        self.fireballDirectionVector = faceDirection?.directionVector
        self.fireballDirectionVector3D = faceDirection?.directionVector3D
        self.fireballMouthOpen = faceDirection?.mouthOpen ?? false
        self.fireballMouthOpenNormalized = faceDirection?.normalizedMouthOpen ?? 0
        self.fireballDepthScale = faceDirection?.depthScaleFactor ?? 1.0
        fireUntil = now.addingTimeInterval(5.0)

        acceptedSignHistory.removeAll(keepingCapacity: true)
        acceptedSignTimestamps.removeAll(keepingCapacity: true)
        targetProgressCount = 0
        targetSequenceStartedAt = nil
        sequentialWrongLabel = nil
        sequentialWrongStart = nil
        seenSigns = []
        resetGestureHoldState()

        return GestureCommitResult(trigger: trigger, status: progressStatus)
    }

    private func appendAcceptedSign(_ label: String, at now: Date) {
        acceptedSignHistory.append(label)
        acceptedSignTimestamps.append(now)
        let overflow = acceptedSignHistory.count - maxSequenceLength
        if overflow > 0 {
            acceptedSignHistory.removeFirst(overflow)
            acceptedSignTimestamps.removeFirst(overflow)
        }
    }

    private func matchesTail(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, acceptedSignHistory.count >= sequence.count else { return false }
        return Array(acceptedSignHistory.suffix(sequence.count)) == sequence
    }

    private func matchesTailWithinDuration(_ sequence: [String], maxDuration: TimeInterval) -> Bool {
        guard matchesTail(sequence) else { return false }
        guard acceptedSignTimestamps.count >= sequence.count else { return false }

        let tailTimes = acceptedSignTimestamps.suffix(sequence.count)
        guard let first = tailTimes.first, let last = tailTimes.last else { return false }
        return last.timeIntervalSince(first) <= maxDuration
    }

    private func updateTargetProgress(with label: String, targetJutsu: JutsuType, now: Date) -> TargetProgressUpdate {
        let sequence = targetJutsu.signSequence
        guard !sequence.isEmpty else {
            targetProgressCount = 0
            seenSigns = []
            targetSequenceStartedAt = nil
            sequentialWrongLabel = nil
            sequentialWrongStart = nil
            return .wrongIgnored(remainingMs: Int(wrongSignResetDelay * 1000))
        }

        if targetJutsu == .kuchiyose,
           let startedAt = targetSequenceStartedAt,
           now.timeIntervalSince(startedAt) > kuchiyoseSequenceTimeLimit {
            targetProgressCount = 0
            seenSigns = []
            targetSequenceStartedAt = nil
            sequentialWrongLabel = nil
            sequentialWrongStart = nil

            if label == sequence[0] {
                targetProgressCount = 1
                seenSigns = Set(sequence.prefix(targetProgressCount))
                targetSequenceStartedAt = now
                return .advanced
            }

            return .timedOut
        }

        if targetProgressCount < sequence.count && label == sequence[targetProgressCount] {
            if targetJutsu == .kuchiyose, targetProgressCount == 0 {
                targetSequenceStartedAt = now
            }
            targetProgressCount += 1
            seenSigns = Set(sequence.prefix(targetProgressCount))
            sequentialWrongLabel = nil
            sequentialWrongStart = nil
            return .advanced
        }

        if targetJutsu == .kuchiyose {
            targetProgressCount = 0
            seenSigns = []
            targetSequenceStartedAt = nil
            sequentialWrongLabel = nil
            sequentialWrongStart = nil

            if label == sequence[0] {
                targetProgressCount = 1
                seenSigns = Set(sequence.prefix(targetProgressCount))
                targetSequenceStartedAt = now
                return .advanced
            }

            return .wrongReset
        }

        sequentialWrongLabel = label
        sequentialWrongStart = now
        return .wrongIgnored(remainingMs: Int(wrongSignResetDelay * 1000))
    }

    private func maybeResetSequenceForPersistentWrongLabel(
        currentLabel: String,
        mode: AppMode,
        targetJutsu: JutsuType?,
        now: Date
    ) -> String? {
        guard mode == .tutorial || mode == .speed || mode == .battle else { return nil }
        guard targetJutsu != nil else { return nil }
        guard sequentialWrongLabel == currentLabel, let wrongStart = sequentialWrongStart else { return nil }

        let elapsed = now.timeIntervalSince(wrongStart)
        if elapsed >= wrongSignResetDelay {
            targetProgressCount = 0
            seenSigns = []
            targetSequenceStartedAt = nil
            sequentialWrongLabel = nil
            sequentialWrongStart = nil
            resetGestureHoldState()
            return "Wrong sign for 2s. Sequence reset"
        }

        let remainingMs = max(0, Int((wrongSignResetDelay - elapsed) * 1000))
        return "Wrong sign ignored (\(remainingMs)ms before reset)"
    }

    private func deactivateEffectState() {
        fireActive = false
        fireHands = []
        fireScales = []
        mouthPoint = nil
        fireballDirectionVector = nil
        fireballDirectionVector3D = nil
        fireballMouthOpen = false
        fireballMouthOpenNormalized = 0
        fireballDepthScale = 1.0
        activeEffectJutsu = nil
        fireUntil = nil
    }

    private func applyEffectHands(from overlay: [[CGPoint]]) {
        let (palms, scales) = extractPalmPointsAndScales(from: overlay)
        if palms.count >= 2 {
            fireHands = [palms[0], palms[1]]
            fireScales = [scales[0], scales[1]]
        } else if palms.count == 1 {
            fireHands = [palms[0], palms[0]]
            fireScales = [scales[0], scales[0]]
        } else {
            fireHands = []
            fireScales = []
        }
    }

    private func snapshot(status: String, triggeredJutsu: JutsuType?) -> JutsuState {
        var state = JutsuState()
        state.fireActive = fireActive
        state.fireHands = fireHands
        state.fireScales = fireScales
        state.mouthPoint = mouthPoint
        state.fireballDirectionVector = fireballDirectionVector
        state.fireballDirectionVector3D = fireballDirectionVector3D
        state.fireballMouthOpen = fireballMouthOpen
        state.fireballMouthOpenNormalized = fireballMouthOpenNormalized
        state.fireballDepthScale = fireballDepthScale
        state.activeEffectJutsu = activeEffectJutsu
        state.seenSigns = seenSigns
        state.sequenceProgressCount = targetProgressCount
        state.triggeredJutsu = triggeredJutsu
        state.statusMessage = status
        return state
    }

    private func normalizeSignLabel(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "hare":
            return "rabbit"
        case "serpent":
            return "snake"
        default:
            return normalized.replacingOccurrences(of: "_", with: "")
        }
    }

    private func extractPalmPointsAndScales(from overlay: [[CGPoint]]) -> ([CGPoint], [CGFloat]) {
        var palms: [CGPoint] = []
        var scales: [CGFloat] = []

        for hand in overlay {
            let keyIndices = [0, 5, 9, 13, 17]
            var points: [CGPoint] = []
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX: CGFloat = 0
            var maxY: CGFloat = 0

            for p in hand where p.x >= 0 && p.y >= 0 {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }

            for idx in keyIndices {
                guard idx < hand.count else { continue }
                let p = hand[idx]
                guard p.x >= 0, p.y >= 0 else { continue }
                points.append(p)
            }

            if points.isEmpty { continue }

            let sx = points.reduce(0.0) { $0 + $1.x }
            let sy = points.reduce(0.0) { $0 + $1.y }
            palms.append(CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count)))

            let width = max(0, maxX - minX)
            let height = max(0, maxY - minY)
            let handSize = max(width, height)
            let dynamicScale = max(1.0, min(3.2, handSize * 6.0))
            scales.append(dynamicScale)

            if palms.count == 2 { break }
        }

        return (palms, scales)
    }
}
