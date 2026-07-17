import AVFoundation
import Combine
import CoreGraphics
import CoreMedia
import Foundation

/// Two-player duel: each half of the camera frame belongs to one player.
/// Both players sign simultaneously; completed jutsu fly at the opponent.
/// Casting the elemental counter of an incoming jutsu before it lands
/// blocks it.
@MainActor
final class VersusViewModel: ObservableObject {
    enum Side: String {
        case left = "P1"
        case right = "P2"

        var opponent: Side { self == .left ? .right : .left }
    }

    struct IncomingAttack: Identifiable {
        let id = UUID()
        let jutsu: JutsuType
        let from: Side
        let launchedAt: Date
        let travelTime: TimeInterval

        func progress(at date: Date) -> Double {
            min(1, max(0, date.timeIntervalSince(launchedAt) / travelTime))
        }
    }

    struct CastEvent: Identifiable {
        let id = UUID()
        let jutsu: JutsuType
        let side: Side
        var age: TimeInterval = 0
    }

    struct Burst: Identifiable {
        let id = UUID()
        var position: CGPoint
        var colorHex: UInt32
        var age: TimeInterval = 0
        var lifetime: TimeInterval = 0.5
        var maxRadius: CGFloat = 60
    }

    @Published private(set) var leftHP = 100
    @Published private(set) var rightHP = 100
    @Published private(set) var leftStatus = "Show your hands"
    @Published private(set) var rightStatus = "Show your hands"
    @Published private(set) var leftDetectedSign = ""
    @Published private(set) var rightDetectedSign = ""
    @Published private(set) var attacks: [IncomingAttack] = []
    @Published private(set) var castEvents: [CastEvent] = []
    @Published private(set) var bursts: [Burst] = []
    @Published private(set) var winner: Side?
    @Published private(set) var cameraReady = false
    @Published private(set) var hitPulse = 0

    var session: AVCaptureSession { cameraManager.session }
    var previewMirrored: Bool { cameraManager.previewMirrored }

    private let cameraManager = CameraManager()
    // Four hands: two per player.
    private let recognizer = GestureRecognizer(maxHands: 4)
    private let leftManager = JutsuManager()
    private let rightManager = JutsuManager()

    private let processingQueue = DispatchQueue(label: "versus.inference", qos: .userInitiated)
    private var isProcessingFrame = false
    private var tickTimer: Timer?
    private var arenaSize: CGSize = .zero
    private var cancellables = Set<AnyCancellable>()

    private let scoreThreshold: Double = 180.0
    private let scoreScale: Double = 1000.0
    private let attackTravelTime: TimeInterval = 1.8

    /// Most recent cast per side, used to resolve blocks at impact time.
    private var lastCast: [Side: (jutsu: JutsuType, at: Date)] = [:]

    func start() {
        cameraManager.onSampleBuffer = { [weak self] buffer in
            self?.handleFrame(buffer)
        }
        cameraManager.$cameraReady
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                self?.cameraReady = ready
            }
            .store(in: &cancellables)
        cameraManager.start()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(deltaTime: 1.0 / 30.0)
            }
        }
    }

    func stop() {
        cameraManager.onSampleBuffer = nil
        cameraManager.stop()
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func rematch() {
        leftHP = 100
        rightHP = 100
        winner = nil
        attacks.removeAll()
        castEvents.removeAll()
        bursts.removeAll()
        lastCast.removeAll()
        leftManager.resetAll()
        rightManager.resetAll()
        leftStatus = "Show your hands"
        rightStatus = "Show your hands"
    }

    func updateArenaSize(_ size: CGSize) {
        arenaSize = size
    }

    // MARK: - Frame processing

    private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        if isProcessingFrame { return }
        isProcessingFrame = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessingFrame = false }
            self.processFrameOnQueue(sampleBuffer)
        }
    }

    private func processFrameOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Deferred triggers (e.g. parked wind inside a kuchiyose attempt).
        if let deferredLeft = leftManager.tickFireExpiry() {
            Task { @MainActor in self.handleSideState(deferredLeft, side: .left) }
        }
        if let deferredRight = rightManager.tickFireExpiry() {
            Task { @MainActor in self.handleSideState(deferredRight, side: .right) }
        }

        guard let frame = try? recognizer.detectVersus(
            pixelBuffer: pixelBuffer,
            orientation: cameraManager.visionOrientation,
            captureMirrored: cameraManager.captureStreamMirrored,
            previewMirrored: cameraManager.previewMirrored,
            scoreScale: scoreScale
        ) else { return }

        processSide(frame.left, side: .left, manager: leftManager)
        processSide(frame.right, side: .right, manager: rightManager)
    }

    private func processSide(
        _ observation: GestureRecognizer.VersusSideObservation?,
        side: Side,
        manager: JutsuManager
    ) {
        guard let observation, observation.score >= scoreThreshold, observation.label != "unknown" else {
            manager.resetGestureHoldState()
            Task { @MainActor in
                self.setSideStatus(side, status: "Show a sign", detected: "")
            }
            return
        }

        let state = manager.processCandidate(
            label: observation.label,
            score: observation.score,
            overlay: observation.overlayHands,
            faceDirection: nil,
            mode: .versus,
            targetJutsu: nil
        )

        Task { @MainActor in
            self.setSideStatus(side, status: state.statusMessage, detected: observation.label)
            self.handleSideState(state, side: side)
        }
    }

    private func setSideStatus(_ side: Side, status: String, detected: String) {
        switch side {
        case .left:
            leftStatus = status
            leftDetectedSign = detected
        case .right:
            rightStatus = status
            rightDetectedSign = detected
        }
    }

    private func handleSideState(_ state: JutsuState, side: Side) {
        guard winner == nil, let jutsu = state.triggeredJutsu else { return }
        cast(jutsu, from: side)
    }

    // MARK: - Combat

    private func cast(_ jutsu: JutsuType, from side: Side) {
        let now = Date()
        lastCast[side] = (jutsu, now)
        Haptics.jutsuTriggered()

        castEvents.append(CastEvent(jutsu: jutsu, side: side))

        attacks.append(
            IncomingAttack(jutsu: jutsu, from: side, launchedAt: now, travelTime: attackTravelTime)
        )
    }

    private func tick(deltaTime: TimeInterval) {
        guard winner == nil else { return }
        let now = Date()

        for idx in castEvents.indices.reversed() {
            castEvents[idx].age += deltaTime
            if castEvents[idx].age >= 1.4 {
                castEvents.remove(at: idx)
            }
        }

        for idx in bursts.indices.reversed() {
            bursts[idx].age += deltaTime
            if bursts[idx].age >= bursts[idx].lifetime {
                bursts.remove(at: idx)
            }
        }

        for idx in attacks.indices.reversed() {
            let attack = attacks[idx]
            guard attack.progress(at: now) >= 1 else { continue }
            attacks.remove(at: idx)
            resolveImpact(of: attack, at: now)
        }
    }

    private func resolveImpact(of attack: IncomingAttack, at now: Date) {
        let defender = attack.from.opponent
        let impactX = defender == .left ? arenaSize.width * 0.16 : arenaSize.width * 0.84
        let impactPoint = CGPoint(x: max(40, impactX), y: max(120, arenaSize.height * 0.45))

        // Block: the defender cast the counter jutsu after this attack launched.
        if let defense = lastCast[defender],
           defense.at >= attack.launchedAt,
           defense.jutsu == attack.jutsu.counteredBy {
            bursts.append(Burst(position: impactPoint, colorHex: 0x66FF99, maxRadius: 80))
            setSideStatus(defender, status: "BLOCKED \(attack.jutsu.title)!", detected: "")
            Haptics.defenseSuccess()
            return
        }

        bursts.append(Burst(position: impactPoint, colorHex: 0xFF6A5A, maxRadius: 70))
        hitPulse += 1
        Haptics.playerHit()

        switch defender {
        case .left:
            leftHP = max(0, leftHP - attack.jutsu.versusDamage)
            if leftHP == 0 { winner = .right }
        case .right:
            rightHP = max(0, rightHP - attack.jutsu.versusDamage)
            if rightHP == 0 { winner = .left }
        }
    }
}
