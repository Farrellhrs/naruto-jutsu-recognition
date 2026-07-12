import AVFoundation
import AudioToolbox
import Combine
import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published var statusText: String = "Preparing..."
    @Published var modeText: String = "Mode: -"
    @Published var debugText: String = ""
    @Published var overlayHands: [[CGPoint]] = []
    @Published var faceDebugPoints: [CGPoint] = []
    @Published var fireHands: [CGPoint] = []
    @Published var fireScales: [CGFloat] = []
    @Published var mouthPoint: CGPoint?
    @Published var fireballDirectionVector: CGVector?
    @Published var fireballDirectionVector3D: FaceVector3D?
    @Published var fireballMouthOpen: Bool = false
    @Published var fireballMouthOpenNormalized: CGFloat = 0
    @Published var fireballDepthScale: CGFloat = 1.0
    @Published var fireActive: Bool = false
    @Published var activeEffectJutsu: JutsuType?
    @Published var seenSigns: Set<String> = []
    @Published var sequenceProgressCount: Int = 0

    @Published var showResult = false
    @Published var resultJutsu: JutsuType?
    @Published var elapsedText = "0.00s"

    let config: GameConfig
    let cameraManager = CameraManager()

    private let recognizer = GestureRecognizer()
    private let jutsuManager = JutsuManager()
    private let processingQueue = DispatchQueue(label: "jutsu.master.processing.queue")

    private let scoreThreshold: Double = 180.0
    private let scoreScale: Double = 1000.0
    private let fireballDebugModeEnabled = false
    private let correctSignSoundID: SystemSoundID = 1104

    private var challengeStart: Date?
    private var challengeCompleted = false
    private var challengeTarget: JutsuType?
    private var battleDefendTarget: JutsuType?
    private var pendingTutorialResultJutsu: JutsuType?
    private var isProcessingFrame = false
    private var jutsuAudioPlayer: AVAudioPlayer?
    private var playingAudioJutsu: JutsuType?
    private var rasenganAudioLastPalm: CGPoint?
    private var rasenganAudioLastTimestamp: CFTimeInterval = 0
    private var rasenganAudioSmoothedSpeed: Double = 0

    init(config: GameConfig) {
        self.config = config
        if config.mode == .speed {
            challengeTarget = config.selectedJutsu
        } else if config.mode == .tutorial {
            challengeTarget = config.selectedJutsu
        }

        cameraManager.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handleFrame(sampleBuffer)
        }
    }

    var session: AVCaptureSession { cameraManager.session }
    var cameraReady: Bool { cameraManager.cameraReady }
    var previewOrientation: AVCaptureVideoOrientation { cameraManager.previewOrientation }
    var previewMirrored: Bool { cameraManager.previewMirrored }
    var currentModeTitle: String { config.mode.title }
    var targetJutsu: JutsuType? { challengeTarget }
    var selectedSummon: SummonAnimal { config.selectedSummon }

    func start() {
        pendingTutorialResultJutsu = nil
        battleDefendTarget = nil
        if config.mode == .speed {
            challengeStart = Date()
            challengeCompleted = false
        }
        cameraManager.start()
        statusText = "Show signs"
    }

    func stop() {
        cameraManager.stop()
        battleDefendTarget = nil
        jutsuManager.resetAll()
        pendingTutorialResultJutsu = nil
        stopJutsuSound()
    }

    func retry() {
        showResult = false
        resultJutsu = nil
        pendingTutorialResultJutsu = nil
        challengeCompleted = false
        battleDefendTarget = nil
        elapsedText = "0.00s"
        jutsuManager.resetAll()
        stopJutsuSound()

        if config.mode == .speed {
            challengeStart = Date()
            statusText = "Go!"
        } else {
            statusText = "Try again"
        }
    }

    func setBattleDefendTarget(_ target: JutsuType?) {
        guard config.mode == .battle else { return }
        battleDefendTarget = target
    }

    private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        if isProcessingFrame { return }
        isProcessingFrame = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessingFrame = false }

            self.jutsuManager.tickFireExpiry()

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            do {
                guard let detected = try self.recognizer.detect(
                    pixelBuffer: pixelBuffer,
                    orientation: self.cameraManager.visionOrientation,
                    isFrontCamera: self.cameraManager.isFrontCamera,
                    captureMirrored: self.cameraManager.captureStreamMirrored,
                    previewMirrored: self.cameraManager.previewMirrored,
                    scoreScale: self.scoreScale
                ) else {
                    Task { @MainActor in
                        self.jutsuManager.resetGestureHoldState()
                        self.modeText = "Mode: -"
                        self.statusText = "No hand"
                        self.debugText = ""
                        self.overlayHands = []
                        self.faceDebugPoints = []
                        self.applyJutsuState(self.idleState())
                    }
                    return
                }

                Task { @MainActor in
                    self.modeText = detected.modeText
                    self.debugText = ""
                    self.overlayHands = detected.overlayHands
                    self.faceDebugPoints = detected.faceDirection?.debugPoints ?? []

                    if self.jutsuManager.fireActive {
                        self.jutsuManager.updateLiveFireHands(with: detected.overlayHands)
                        self.jutsuManager.updateLiveFaceDirection(detected.faceDirection)
                    }

                    if detected.score >= self.scoreThreshold {
                        let effectiveTargetJutsu: JutsuType?
                        switch self.config.mode {
                        case .battle:
                            effectiveTargetJutsu = self.battleDefendTarget
                        default:
                            effectiveTargetJutsu = self.challengeTarget
                        }

                        let state = self.jutsuManager.processCandidate(
                            label: detected.label,
                            score: detected.score,
                            overlay: detected.overlayHands,
                            faceDirection: detected.faceDirection,
                            mode: self.config.mode,
                            targetJutsu: effectiveTargetJutsu
                        )
                        self.statusText = state.statusMessage
                        self.applyJutsuState(state)
                        self.handleTriggerIfNeeded(state.triggeredJutsu)
                    } else {
                        self.jutsuManager.resetGestureHoldState()
                        self.statusText = "No confident sign"
                        self.applyJutsuState(self.idleState())
                    }
                }
            } catch {
                Task { @MainActor in
                    self.jutsuManager.resetGestureHoldState()
                    self.statusText = "Inference error"
                    self.debugText = ""
                    self.overlayHands = []
                    self.faceDebugPoints = []
                    self.applyJutsuState(self.idleState())
                }
            }
        }
    }

    private func composeDetectedSignText(label: String, faceDirection: FaceDirectionObservation?) -> String {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.lowercased() != "unknown" else {
            return ""
        }

        let detected = "Detected: \(cleaned.capitalized)"
        guard fireballDebugModeEnabled, let faceDirection else {
            return detected
        }

        return detected + " | " + faceDirection.debugLine
    }

    private func idleState() -> JutsuState {
        var state = JutsuState()
        state.fireActive = jutsuManager.fireActive
        state.fireHands = jutsuManager.fireHands
        state.fireScales = jutsuManager.fireScales
        state.mouthPoint = jutsuManager.mouthPoint
        state.fireballDirectionVector = jutsuManager.fireballDirectionVector
        state.fireballDirectionVector3D = jutsuManager.fireballDirectionVector3D
        state.fireballMouthOpen = jutsuManager.fireballMouthOpen
        state.fireballMouthOpenNormalized = jutsuManager.fireballMouthOpenNormalized
        state.fireballDepthScale = jutsuManager.fireballDepthScale
        state.activeEffectJutsu = jutsuManager.activeEffectJutsu
        state.seenSigns = jutsuManager.seenSigns
        state.sequenceProgressCount = jutsuManager.currentSequenceProgressCount
        return state
    }

    private func applyJutsuState(_ state: JutsuState) {
        let previousProgress = sequenceProgressCount

        fireActive = state.fireActive
        fireHands = state.fireHands
        fireScales = state.fireScales
        mouthPoint = state.mouthPoint
        fireballDirectionVector = state.fireballDirectionVector
        fireballDirectionVector3D = state.fireballDirectionVector3D
        fireballMouthOpen = state.fireballMouthOpen
        fireballMouthOpenNormalized = state.fireballMouthOpenNormalized
        fireballDepthScale = state.fireballDepthScale
        activeEffectJutsu = state.activeEffectJutsu
        seenSigns = state.seenSigns
        sequenceProgressCount = state.sequenceProgressCount

        if state.sequenceProgressCount > previousProgress {
            AudioServicesPlaySystemSound(correctSignSoundID)
        }

        maybePresentTutorialResultIfNeeded(after: state)
        syncJutsuSound(with: state)
    }

    private func maybePresentTutorialResultIfNeeded(after state: JutsuState) {
        guard config.mode == .tutorial else { return }
        guard !showResult, !state.fireActive, let pending = pendingTutorialResultJutsu else { return }
        resultJutsu = pending
        showResult = true
        pendingTutorialResultJutsu = nil
    }

    private func syncJutsuSound(with state: JutsuState) {
        guard state.fireActive, let jutsu = state.activeEffectJutsu else {
            stopJutsuSound()
            return
        }

        if playingAudioJutsu != jutsu || jutsuAudioPlayer?.isPlaying != true {
            playJutsuSound(for: jutsu)
        }

        updateJutsuSoundDynamics(for: jutsu, state: state)
    }

    private func playJutsuSound(for jutsu: JutsuType) {
        guard let soundInfo = soundResource(for: jutsu) else {
            stopJutsuSound()
            return
        }

        stopJutsuSound()

        let resourceURL =
            Bundle.main.url(forResource: soundInfo.name, withExtension: soundInfo.ext, subdirectory: "sound_effect")
            ?? Bundle.main.url(forResource: soundInfo.name, withExtension: soundInfo.ext)

        guard let resourceURL else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: resourceURL)
            player.numberOfLoops = -1
            player.enableRate = true
            player.volume = 0.90
            player.rate = 1.0
            player.prepareToPlay()
            player.play()
            jutsuAudioPlayer = player
            playingAudioJutsu = jutsu
        } catch {
            stopJutsuSound()
        }
    }

    private func stopJutsuSound() {
        jutsuAudioPlayer?.stop()
        jutsuAudioPlayer = nil
        playingAudioJutsu = nil
        resetRasenganAudioTracking()
    }

    private func updateJutsuSoundDynamics(for jutsu: JutsuType, state: JutsuState) {
        guard let player = jutsuAudioPlayer else { return }

        switch jutsu {
        case .rasengan, .wind:
            let intensity = currentRasenganAudioIntensity(from: state.fireHands)
            player.volume = Float(min(1.0, 0.42 + (intensity * 0.58)))
            if player.enableRate {
                player.rate = Float(min(1.45, max(0.95, 1.0 + (intensity * 0.24))))
            }
        default:
            player.volume = 0.90
            if player.enableRate {
                player.rate = 1.0
            }
            resetRasenganAudioTracking()
        }
    }

    private func currentRasenganAudioIntensity(from hands: [CGPoint]) -> Double {
        guard let palm = hands.first else {
            resetRasenganAudioTracking()
            return 0
        }

        let now = CACurrentMediaTime()
        defer {
            rasenganAudioLastPalm = palm
            rasenganAudioLastTimestamp = now
        }

        guard let previousPalm = rasenganAudioLastPalm, rasenganAudioLastTimestamp > 0 else {
            return 0
        }

        let dt = max(1.0 / 120.0, now - rasenganAudioLastTimestamp)
        let dx = Double(palm.x - previousPalm.x)
        let dy = Double(palm.y - previousPalm.y)
        let speed = sqrt((dx * dx) + (dy * dy)) / dt

        rasenganAudioSmoothedSpeed = (rasenganAudioSmoothedSpeed * 0.74) + (speed * 0.26)
        return min(1.0, max(0.0, rasenganAudioSmoothedSpeed / 1.5))
    }

    private func resetRasenganAudioTracking() {
        rasenganAudioLastPalm = nil
        rasenganAudioLastTimestamp = 0
        rasenganAudioSmoothedSpeed = 0
    }

    private func soundResource(for jutsu: JutsuType) -> (name: String, ext: String)? {
        switch jutsu {
        case .lightning:
            return ("Chidori", "mp3")
        case .fireball, .fire:
            return ("Fireball", "mp3")
        case .burningAsh:
            return ("Burning Ash", "mp3")
        case .kuchiyose:
            return nil
        case .rasengan:
            return ("Rasengan", "mp3")
        case .waterDragon:
            return nil
        case .wind:
            return ("Rasengan", "mp3")
        }
    }

    private func handleTriggerIfNeeded(_ triggered: JutsuType?) {
        guard let triggered else { return }

        switch config.mode {
        case .free, .battle:
            resultJutsu = triggered
            showResult = false
        case .tutorial:
            pendingTutorialResultJutsu = triggered
            resultJutsu = triggered
            showResult = false
            if !fireActive {
                showResult = true
                pendingTutorialResultJutsu = nil
            }
        case .speed:
            resultJutsu = triggered
            guard !challengeCompleted else { return }
            challengeCompleted = true
            if let start = challengeStart {
                let elapsed = Date().timeIntervalSince(start)
                elapsedText = String(format: "%.2fs", elapsed)
            }
            showResult = true
        }
    }
}
