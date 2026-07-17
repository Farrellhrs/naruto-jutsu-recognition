import CoreML
import Foundation
import ImageIO
import os.log

extension Logger {
    static let gestureRecognizer = Logger(subsystem: "com.farrellhrs.narutoapp", category: "GestureRecognizer")
}

final class GestureRecognizer {
    private let model: MLModel?
    private let landmarkDetector: HandLandmarkDetecting?
    private let faceDirectionEstimator: FaceDirectionEstimating

    // Rolling inference-latency stats (landmarks -> features -> CoreML), logged
    // once per window so "real-time" is a measured claim, not an assumption.
    private var latencySampleCount = 0
    private var latencyAccumulatedMs: Double = 0
    private let latencyLogWindow = 120

    private let featureCount = 126
    private let singleHandFeatureCount = 63
    private let minJointConfidence: Float = 0.05
    private let inferenceMirrorX = false
    private let overlayMirrorY: Bool = {
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
    }()

    private struct PreprocessResult {
        let modeText: String
        let candidateVectors: [[Float]]
    }

    private struct PredictionResult {
        let label: String
        let confidence: Double
        let probabilities: [String: Double]
    }

    init(maxHands: Int = 2) {
        let taskModelPath = Bundle.main.url(forResource: "hand_landmarker", withExtension: "task")?.path
        landmarkDetector = HandLandmarkDetectorFactory.makeDetector(
            mediaPipeTaskModelPath: taskModelPath,
            maxHands: maxHands,
            minJointConfidence: minJointConfidence
        )
        faceDirectionEstimator = FaceDirectionEstimatorFactory.makeEstimator(maxRange: 0.10, maxAngleDegrees: 45.0)

        // The unified 126-feature model is the only supported classifier.
        // Legacy one-hand / two-hand models used incompatible feature layouts,
        // so silently falling back to them would corrupt predictions.
        var loadedModel: MLModel?
        if let modelURL = Bundle.main.url(forResource: "hand_gesture_rf_unified", withExtension: "mlmodelc") {
            do {
                loadedModel = try MLModel(contentsOf: modelURL)
            } catch {
                assertionFailure("Failed to load hand_gesture_rf_unified: \(error)")
                Logger.gestureRecognizer.fault("Failed to load hand_gesture_rf_unified: \(error.localizedDescription)")
            }
        } else {
            assertionFailure("hand_gesture_rf_unified.mlmodelc missing from bundle")
            Logger.gestureRecognizer.fault("hand_gesture_rf_unified.mlmodelc missing from bundle")
        }
        self.model = loadedModel
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        scoreScale: Double
    ) throws -> GestureObservation? {
        guard let model, let landmarkDetector else { return nil }

        let inferenceStart = CFAbsoluteTimeGetCurrent()
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)

        let faceDirection = try faceDirectionEstimator.estimateFaceDirection(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY,
            timestampMs: timestampMs
        )

        let mouthPoint = faceDirection?.mouthPoint
        let handSamples = try landmarkDetector.detectHands(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            timestampMs: timestampMs
        )

        let focusedSamples = selectPrimaryHands(from: handSamples)

        guard !focusedSamples.isEmpty else {
            return GestureObservation(
                modeText: "Mode: -",
                label: "unknown",
                score: 0,
                topText: "",
                overlayHands: [],
                mouthPoint: mouthPoint,
                faceDirection: faceDirection
            )
        }

        let overlay = extractOverlayHands(
            from: focusedSamples,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored
        )

        guard let preprocess = buildPreprocessResult(
            from: focusedSamples,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored
        ) else {
            return GestureObservation(modeText: "Mode: -", label: "unknown", score: 0, topText: "", overlayHands: overlay, mouthPoint: mouthPoint, faceDirection: faceDirection)
        }

        let prediction = try runBestPrediction(model: model, preprocess: preprocess)
        recordLatency(sinceStart: inferenceStart)

        let score = prediction.confidence * scoreScale
        let topText = formatTopK(probabilities: prediction.probabilities, k: 3, scoreScale: scoreScale)
        return GestureObservation(
            modeText: "Mode: \(preprocess.modeText)",
            label: prediction.label,
            score: score,
            topText: topText,
            overlayHands: overlay,
            mouthPoint: mouthPoint,
            faceDirection: faceDirection
        )
    }

    private func recordLatency(sinceStart start: CFAbsoluteTime) {
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        latencyAccumulatedMs += elapsedMs
        latencySampleCount += 1
        if latencySampleCount >= latencyLogWindow {
            let averageMs = latencyAccumulatedMs / Double(latencySampleCount)
            Logger.gestureRecognizer.info("Avg pipeline latency over \(self.latencyLogWindow) frames: \(String(format: "%.1f", averageMs)) ms/frame")
            latencyAccumulatedMs = 0
            latencySampleCount = 0
        }
    }

    struct VersusSideObservation {
        let label: String
        let score: Double
        let overlayHands: [[CGPoint]]
    }

    struct VersusFrameObservation {
        let left: VersusSideObservation?
        let right: VersusSideObservation?
    }

    /// Two-player detection: hands are grouped by which half of the frame
    /// they occupy (after mirroring is canonicalized), and each side gets an
    /// independent 126-feature prediction. Face features are skipped.
    func detectVersus(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        captureMirrored: Bool,
        previewMirrored: Bool,
        scoreScale: Double
    ) throws -> VersusFrameObservation {
        guard let model, let landmarkDetector else {
            return VersusFrameObservation(left: nil, right: nil)
        }

        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let samples = try landmarkDetector.detectHands(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            timestampMs: timestampMs
        )

        var leftSide: [HandLandmarkSample] = []
        var rightSide: [HandLandmarkSample] = []
        for sample in samples {
            let valid = sample.landmarks.filter { !($0.x == 0 && $0.y == 0 && $0.z == 0) }
            guard !valid.isEmpty else { continue }
            var meanX = valid.reduce(Float(0)) { $0 + $1.x } / Float(valid.count)
            if requiresSoftwareMirrorX(captureMirrored: captureMirrored, previewMirrored: previewMirrored) {
                meanX = 1.0 - meanX
            }
            if meanX < 0.5 {
                leftSide.append(sample)
            } else {
                rightSide.append(sample)
            }
        }

        func observe(_ sideSamples: [HandLandmarkSample]) -> VersusSideObservation? {
            let focused = selectPrimaryHands(from: sideSamples)
            guard !focused.isEmpty else { return nil }

            let overlay = extractOverlayHands(
                from: focused,
                captureMirrored: captureMirrored,
                previewMirrored: previewMirrored
            )

            guard let preprocess = buildPreprocessResult(
                from: focused,
                captureMirrored: captureMirrored,
                previewMirrored: previewMirrored
            ), let prediction = try? runBestPrediction(model: model, preprocess: preprocess) else {
                return VersusSideObservation(label: "unknown", score: 0, overlayHands: overlay)
            }

            return VersusSideObservation(
                label: prediction.label,
                score: prediction.confidence * scoreScale,
                overlayHands: overlay
            )
        }

        return VersusFrameObservation(left: observe(leftSide), right: observe(rightSide))
    }

    private func selectPrimaryHands(from samples: [HandLandmarkSample]) -> [HandLandmarkSample] {
        guard samples.count > 1 else { return samples }

        struct RankedHand {
            let sample: HandLandmarkSample
            let area: Float
            let distanceToCenter: Float
            let center: SIMD2<Float>
        }

        let ranked = samples.compactMap { sample -> RankedHand? in
            let valid = sample.landmarks.filter { !($0.x == 0.0 && $0.y == 0.0 && $0.z == 0.0) }
            guard !valid.isEmpty else { return nil }

            let minX = valid.map(\.x).min() ?? 0
            let maxX = valid.map(\.x).max() ?? 0
            let minY = valid.map(\.y).min() ?? 0
            let maxY = valid.map(\.y).max() ?? 0

            let width = max(0, maxX - minX)
            let height = max(0, maxY - minY)
            let area = width * height

            let centerX = (minX + maxX) * 0.5
            let centerY = (minY + maxY) * 0.5
            let distanceToCenter = hypotf(centerX - 0.5, centerY - 0.5)
            let center = SIMD2<Float>(centerX, centerY)

            return RankedHand(sample: sample, area: area, distanceToCenter: distanceToCenter, center: center)
        }

        guard !ranked.isEmpty else { return [] }

        let sorted = ranked.sorted { lhs, rhs in
            let areaGap = lhs.area - rhs.area
            if abs(areaGap) > 0.015 {
                return lhs.area > rhs.area
            }
            return lhs.distanceToCenter < rhs.distanceToCenter
        }

        let anchor = sorted[0]
        guard sorted.count > 1 else {
            return [anchor.sample]
        }

        // Keep the most stable "primary" hand, then choose a nearby companion hand
        // so two-hand jutsu and overlay visualization still work.
        let companion = sorted.dropFirst().min { lhs, rhs in
            let lhsDistance = hypotf(lhs.center.x - anchor.center.x, lhs.center.y - anchor.center.y)
            let rhsDistance = hypotf(rhs.center.x - anchor.center.x, rhs.center.y - anchor.center.y)
            if abs(lhsDistance - rhsDistance) > 0.01 {
                return lhsDistance < rhsDistance
            }
            return lhs.area > rhs.area
        }

        if let companion {
            return [anchor.sample, companion.sample]
        }

        return [anchor.sample]
    }

    private func formatTopK(probabilities: [String: Double], k: Int, scoreScale: Double) -> String {
        let sorted = probabilities.sorted { $0.value > $1.value }.prefix(k)
        if sorted.isEmpty { return "" }
        let parts = sorted.map { key, value in
            "\(key): \(Int(value * scoreScale))"
        }
        return "Top: " + parts.joined(separator: " | ")
    }

    private func extractOverlayHands(
        from samples: [HandLandmarkSample],
        captureMirrored: Bool,
        previewMirrored: Bool
    ) -> [[CGPoint]] {
        samples.prefix(2).map { sample in
            sample.landmarks.map { landmark in
                let point = canonicalizeOverlayLandmark(
                    landmark,
                    captureMirrored: captureMirrored,
                    previewMirrored: previewMirrored
                )
                if point.x == 0.0, point.y == 0.0, point.z == 0.0 {
                    return CGPoint(x: -1, y: -1)
                }
                return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            }
        }
    }

    private func canonicalizeInferenceLandmark(
        _ point: SIMD3<Float>,
        captureMirrored: Bool,
        previewMirrored: Bool
    ) -> SIMD3<Float> {
        if point.x == 0.0, point.y == 0.0, point.z == 0.0 {
            return point
        }

        var adjusted = point
        if requiresSoftwareMirrorX(captureMirrored: captureMirrored, previewMirrored: previewMirrored) {
            adjusted.x = 1.0 - adjusted.x
        }
        return adjusted
    }

    private func canonicalizeOverlayLandmark(
        _ point: SIMD3<Float>,
        captureMirrored: Bool,
        previewMirrored: Bool
    ) -> SIMD3<Float> {
        var adjusted = canonicalizeInferenceLandmark(
            point,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored
        )
        if overlayMirrorY,
           !(adjusted.x == 0.0 && adjusted.y == 0.0 && adjusted.z == 0.0) {
            adjusted.y = 1.0 - adjusted.y
        }
        return adjusted
    }

    private func requiresSoftwareMirrorX(captureMirrored: Bool, previewMirrored: Bool) -> Bool {
        inferenceMirrorX || (previewMirrored != captureMirrored)
    }

    private func buildPreprocessResult(
        from samples: [HandLandmarkSample],
        captureMirrored: Bool,
        previewMirrored: Bool
    ) -> PreprocessResult? {
        let limited = Array(samples.prefix(2))
        guard !limited.isEmpty else { return nil }

        var leftNormalized = Array(repeating: Float(0.0), count: singleHandFeatureCount)
        var rightNormalized = Array(repeating: Float(0.0), count: singleHandFeatureCount)
        var fallback: [(xCenter: Float, normalized: [Float])] = []
        var validHandCount = 0

        for sample in limited {
            guard sample.landmarks.count == 21 else { continue }
            validHandCount += 1

            let raw = sample.landmarks.map {
                canonicalizeInferenceLandmark(
                    $0,
                    captureMirrored: captureMirrored,
                    previewMirrored: previewMirrored
                )
            }
            let normalized = normalizeLandmarks(raw)
            let normalizedFlat = flattenLandmarks(normalized)

            let handLabel = sample.handedness?.lowercased()
            if handLabel == "left" {
                leftNormalized = normalizedFlat
            } else if handLabel == "right" {
                rightNormalized = normalizedFlat
            } else {
                let xCenter = raw.reduce(Float(0.0)) { $0 + $1.x } / Float(raw.count)
                fallback.append((xCenter: xCenter, normalized: normalizedFlat))
            }
        }

        guard validHandCount > 0 else { return nil }

        for hand in fallback.sorted(by: { $0.xCenter < $1.xCenter }) {
            if leftNormalized.allSatisfy({ $0 == 0.0 }) {
                leftNormalized = hand.normalized
            } else if rightNormalized.allSatisfy({ $0 == 0.0 }) {
                rightNormalized = hand.normalized
            }
        }

        let merged = leftNormalized + rightNormalized
        guard merged.count == featureCount else { return nil }

        let modeText = validHandCount >= 2 ? "two-hand" : "one-hand + zero-pad"
        return PreprocessResult(
            modeText: modeText,
            candidateVectors: [merged]
        )
    }

    private func runBestPrediction(model: MLModel, preprocess: PreprocessResult) throws -> PredictionResult {
        guard !preprocess.candidateVectors.isEmpty else {
            throw NSError(domain: "GestureRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No feature candidates were generated"])
        }

        var best: PredictionResult?

        for vector in preprocess.candidateVectors {
            let result = try runModelPrediction(model: model, featureVector: vector)

            if let currentBest = best {
                if result.confidence > currentBest.confidence {
                    best = result
                }
            } else {
                best = result
            }
        }

        guard let best else {
            throw NSError(domain: "GestureRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model prediction returned no result"])
        }

        return best
    }

    private func runModelPrediction(model: MLModel, featureVector: [Float]) throws -> PredictionResult {
        let input = makeModelInput(from: featureVector)
        let provider = try MLDictionaryFeatureProvider(dictionary: input)
        let prediction = try model.prediction(from: provider)

        let label = prediction.featureValue(for: "classLabel")?.stringValue ?? "unknown"

        let rawProbabilities = prediction.featureValue(for: "classProbability")?.dictionaryValue ?? [:]
        var probabilities: [String: Double] = [:]
        for (key, value) in rawProbabilities {
            guard let name = key as? String else { continue }
            if let p = value as? Double {
                probabilities[name] = p
            } else if let n = value as? NSNumber {
                probabilities[name] = n.doubleValue
            }
        }

        let confidence = probabilities[label] ?? 0.0
        return PredictionResult(label: label, confidence: confidence, probabilities: probabilities)
    }

    private func makeModelInput(from features: [Float]) -> [String: Double] {
        var dict: [String: Double] = [:]
        for (i, value) in features.enumerated() {
            let key = String(format: "f_%03d", i)
            dict[key] = Double(value)
        }
        return dict
    }

    private func normalizeLandmarks(_ landmarks: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var lm = landmarks
        guard !lm.isEmpty else { return lm }

        let wrist = lm[0]
        for i in 0..<lm.count {
            lm[i].x -= wrist.x
            lm[i].y -= wrist.y
            lm[i].z -= wrist.z
        }

        var scale: Float = 0.0
        for p in lm {
            let norm = sqrtf((p.x * p.x) + (p.y * p.y))
            if norm > scale {
                scale = norm
            }
        }

        if scale < 1e-6 {
            scale = 1.0
        }

        for i in 0..<lm.count {
            lm[i].x /= scale
            lm[i].y /= scale
            lm[i].z /= scale
        }

        return lm
    }

    private func flattenLandmarks(_ landmarks: [SIMD3<Float>]) -> [Float] {
        var flat: [Float] = []
        flat.reserveCapacity(landmarks.count * 3)

        for p in landmarks {
            flat.append(p.x)
            flat.append(p.y)
            flat.append(p.z)
        }

        return flat
    }
}
