import CoreML
import CoreMedia
import Vision

/// One frame's worth of recognition output.
struct SignReading {
    let sign: HandSign?
    let rawLabel: String
    let confidence: Double
    /// Normalized (0-1, top-left origin) landmark points per detected hand,
    /// for drawing the chakra-constellation overlay.
    let hands: [[CGPoint]]
}

/// Vision hand pose -> wrist-centered scale-normalized 126 features ->
/// CoreML RandomForest. Self-contained: no external dependencies.
final class SignRecognitionEngine {
    private let model: MLModel?
    private let poseRequest: VNDetectHumanHandPoseRequest

    /// MediaPipe landmark ordering, which the classifier was trained on.
    private static let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    private static let featureNames: [String] = (0..<126).map { String(format: "f_%03d", $0) }

    init() {
        poseRequest = VNDetectHumanHandPoseRequest()
        poseRequest.maximumHandCount = 2

        if let url = Bundle.main.url(forResource: "hand_gesture_rf_unified", withExtension: "mlmodelc"),
           let loaded = try? MLModel(contentsOf: url) {
            model = loaded
        } else {
            assertionFailure("hand_gesture_rf_unified.mlmodelc missing from bundle")
            model = nil
        }
    }

    func read(_ sampleBuffer: CMSampleBuffer) -> SignReading? {
        guard let model,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([poseRequest])) != nil,
              let observations = poseRequest.results, !observations.isEmpty else {
            return SignReading(sign: nil, rawLabel: "", confidence: 0, hands: [])
        }

        var leftBlock = [Float](repeating: 0, count: 63)
        var rightBlock = [Float](repeating: 0, count: 63)
        var unassigned: [(centerX: CGFloat, block: [Float])] = []
        var overlayHands: [[CGPoint]] = []

        for observation in observations.prefix(2) {
            guard let points = try? observation.recognizedPoints(.all) else { continue }

            var landmarks: [SIMD3<Float>] = []
            var overlay: [CGPoint] = []
            landmarks.reserveCapacity(21)

            for joint in Self.jointOrder {
                if let p = points[joint], p.confidence > 0.15 {
                    // Vision uses bottom-left origin; flip to top-left.
                    landmarks.append(SIMD3(Float(p.location.x), Float(1 - p.location.y), 0))
                    overlay.append(CGPoint(x: p.location.x, y: 1 - p.location.y))
                } else {
                    landmarks.append(SIMD3(0, 0, 0))
                    overlay.append(CGPoint(x: -1, y: -1))
                }
            }

            guard landmarks.contains(where: { $0.x != 0 || $0.y != 0 }) else { continue }
            overlayHands.append(overlay)

            let block = Self.normalize(landmarks)
            switch observation.chirality {
            case .left:
                leftBlock = block
            case .right:
                rightBlock = block
            default:
                let meanX = overlay.filter { $0.x >= 0 }.map(\.x).reduce(0, +) / CGFloat(max(1, overlay.filter { $0.x >= 0 }.count))
                unassigned.append((meanX, block))
            }
        }

        for hand in unassigned.sorted(by: { $0.centerX < $1.centerX }) {
            if leftBlock.allSatisfy({ $0 == 0 }) {
                leftBlock = hand.block
            } else if rightBlock.allSatisfy({ $0 == 0 }) {
                rightBlock = hand.block
            }
        }

        let features = leftBlock + rightBlock
        guard features.contains(where: { $0 != 0 }) else {
            return SignReading(sign: nil, rawLabel: "", confidence: 0, hands: overlayHands)
        }

        guard let (label, confidence) = Self.predict(model: model, features: features) else {
            return SignReading(sign: nil, rawLabel: "", confidence: 0, hands: overlayHands)
        }

        return SignReading(
            sign: HandSign.from(label: label),
            rawLabel: label,
            confidence: confidence,
            hands: overlayHands
        )
    }

    /// Wrist-centered, max-2D-norm scaled — identical to the training pipeline.
    private static func normalize(_ landmarks: [SIMD3<Float>]) -> [Float] {
        var lm = landmarks
        let wrist = lm[0]
        for i in lm.indices {
            lm[i] -= wrist
        }
        var scale: Float = 0
        for p in lm {
            scale = max(scale, (p.x * p.x + p.y * p.y).squareRoot())
        }
        if scale < 1e-6 { scale = 1 }
        return lm.flatMap { [$0.x / scale, $0.y / scale, $0.z / scale] }
    }

    private static func predict(model: MLModel, features: [Float]) -> (String, Double)? {
        var dict: [String: Any] = [:]
        for (index, name) in featureNames.enumerated() {
            dict[name] = Double(features[index])
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: dict),
              let output = try? model.prediction(from: provider) else { return nil }

        var label: String?
        var probability = 0.0
        for name in output.featureNames {
            let value = output.featureValue(for: name)
            if let text = value?.stringValue, !text.isEmpty {
                label = text
            }
            if let probs = value?.dictionaryValue as? [String: Double], !probs.isEmpty {
                if let best = probs.max(by: { $0.value < $1.value }) {
                    if label == nil { label = best.key }
                    probability = probs[label ?? best.key] ?? best.value
                }
            }
        }

        guard let label else { return nil }
        return (label, probability)
    }
}
