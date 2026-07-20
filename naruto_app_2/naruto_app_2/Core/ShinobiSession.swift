import AVFoundation
import Combine
import CoreMedia
import Foundation
import Observation
import UIKit

/// The per-screen facade: camera frames in, observable game state out.
@Observable
@MainActor
final class ShinobiSession {
    // Live recognition state
    private(set) var currentSign: HandSign?
    private(set) var holdProgress: Double = 0
    private(set) var confidence: Double = 0
    private(set) var recentSigns: [HandSign] = []
    private(set) var overlayHands: [[CGPoint]] = []
    private(set) var cameraReady = false

    // Events
    private(set) var lastCast: Jutsu?
    private(set) var castCount = 0
    private(set) var commitCount = 0

    var session: AVCaptureSession { feed.session }

    private let feed = CameraFeed()
    private let engine = SignRecognitionEngine()
    private var sequencer = SignSequencer()
    private let inferenceQueue = DispatchQueue(label: "shinobi.inference", qos: .userInitiated)
    private var busy = false

    private let minimumConfidence = 0.18

    func start() {
        feed.onReadyChange = { [weak self] ready in
            self?.cameraReady = ready
        }
        feed.onFrame = { [weak self] buffer in
            self?.ingest(buffer)
        }
        feed.start()
    }

    func stop() {
        feed.onFrame = nil
        feed.stop()
        sequencer.reset()
    }

    func resetSequence() {
        sequencer.reset()
        recentSigns = []
        lastCast = nil
    }

    private nonisolated func ingest(_ buffer: CMSampleBuffer) {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.process(buffer)
        }
    }

    private nonisolated func process(_ buffer: CMSampleBuffer) {
        Task { @MainActor in
            if self.busy { return }
            self.busy = true
        }

        let reading = engine.read(buffer)

        Task { @MainActor in
            defer { self.busy = false }
            guard let reading else { return }
            self.apply(reading)
        }
    }

    private func apply(_ reading: SignReading) {
        overlayHands = reading.hands
        confidence = reading.confidence

        let confidentSign = reading.confidence >= minimumConfidence ? reading.sign : nil
        currentSign = confidentSign

        let update = sequencer.observe(confidentSign)
        holdProgress = update.holdProgress
        recentSigns = update.recentSigns

        if update.committedSign != nil {
            commitCount += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        }

        if let cast = update.cast {
            lastCast = cast
            castCount += 1
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            SoundFX.shared.play(cast)
        }
    }
}
