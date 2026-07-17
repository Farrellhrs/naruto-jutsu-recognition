import AVFoundation
import Foundation
import ImageIO
import UIKit
import Vision

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

struct HandLandmarkSample {
    let landmarks: [SIMD3<Float>]
    let handedness: String?
}

protocol HandLandmarkDetecting {
    var backendName: String { get }
    func detectHands(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestampMs: Int64
    ) throws -> [HandLandmarkSample]
}

enum HandLandmarkDetectorFactory {
    static func makeDetector(
        mediaPipeTaskModelPath: String?,
        maxHands: Int,
        minJointConfidence: Float
    ) -> HandLandmarkDetecting {
        if let mediaPipeTaskModelPath,
           let mediaPipeDetector = MediaPipeRuntimeHandLandmarkDetector(
               modelPath: mediaPipeTaskModelPath,
               maxHands: maxHands
           ) {
            return mediaPipeDetector
        }

        return VisionHandLandmarkDetector(maxHands: maxHands, minJointConfidence: minJointConfidence)
    }
}

final class VisionHandLandmarkDetector: HandLandmarkDetecting {
    let backendName = "Vision (fallback)"

    private let request = VNDetectHumanHandPoseRequest()
    private let minJointConfidence: Float
    private let maxHands: Int

    private let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    init(maxHands: Int, minJointConfidence: Float) {
        request.maximumHandCount = maxHands
        self.minJointConfidence = minJointConfidence
        self.maxHands = maxHands
    }

    func detectHands(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestampMs: Int64
    ) throws -> [HandLandmarkSample] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        return observations.prefix(maxHands).compactMap { observation in
            do {
                let points = try observation.recognizedPoints(.all)
                var landmarks: [SIMD3<Float>] = []
                landmarks.reserveCapacity(21)

                for joint in jointOrder {
                    if let p = points[joint], p.confidence > minJointConfidence {
                        // Vision y-axis points up; MediaPipe y-axis points down.
                        landmarks.append(SIMD3<Float>(Float(p.x), Float(1.0 - p.y), 0.0))
                    } else {
                        landmarks.append(SIMD3<Float>(0.0, 0.0, 0.0))
                    }
                }

                guard landmarks.count == 21 else { return nil }
                return HandLandmarkSample(landmarks: landmarks, handedness: nil)
            } catch {
                return nil
            }
        }
    }
}

final class MediaPipeRuntimeHandLandmarkDetector: HandLandmarkDetecting {
    let backendName = "MediaPipe iOS Tasks"

    private let landmarker: NSObject

    init?(
        modelPath: String,
        maxHands: Int
    ) {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return nil
        }

        guard let landmarker = try? Self.makeLandmarker(modelPath: modelPath, maxHands: maxHands) else {
            return nil
        }

        self.landmarker = landmarker
    }

    func detectHands(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestampMs: Int64
    ) throws -> [HandLandmarkSample] {
        let image = try Self.makeMPImage(pixelBuffer: pixelBuffer, orientation: orientation)
        let result = try Self.detectWithLandmarker(landmarker: landmarker, image: image, timestampMs: timestampMs)
        return Self.parseResult(result)
    }

    private static func makeLandmarker(modelPath: String, maxHands: Int) throws -> NSObject {
#if canImport(MediaPipeTasksVision)
        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelPath
        let options = HandLandmarkerOptions()
        options.baseOptions = baseOptions
        options.numHands = maxHands
        options.minHandDetectionConfidence = 0.3
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.runningMode = .video

        let landmarker = try HandLandmarker(options: options)
        return landmarker
#else
        guard let optionsClass = NSClassFromString("MPPHandLandmarkerOptions") as? NSObject.Type,
              let baseOptionsClass = NSClassFromString("MPPBaseOptions") as? NSObject.Type,
              let landmarkerClass = NSClassFromString("MPPHandLandmarker") as? NSObject.Type else {
            throw NSError(domain: "MediaPipeRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "MediaPipe classes not found. Ensure MediaPipeTasksVision is linked."])
        }

        let options = optionsClass.init()
        let baseOptions = baseOptionsClass.init()

        baseOptions.setValue(modelPath, forKey: "modelAssetPath")
        options.setValue(baseOptions, forKey: "baseOptions")
        options.setValue(NSNumber(value: maxHands), forKey: "numHands")
        options.setValue(NSNumber(value: 0.3), forKey: "minHandDetectionConfidence")
        options.setValue(NSNumber(value: 0.5), forKey: "minHandPresenceConfidence")
        options.setValue(NSNumber(value: 0.5), forKey: "minTrackingConfidence")
        // MPPRunningMode.video = 1
        options.setValue(NSNumber(value: 1), forKey: "runningMode")

        let selector = NSSelectorFromString("initWithOptions:error:")
        let instance = landmarkerClass.init()
        guard instance.responds(to: selector) else {
            throw NSError(domain: "MediaPipeRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "initWithOptions:error: not found on MPPHandLandmarker"])
        }

        var error: NSError?
        typealias InitIMP = @convention(c) (AnyObject, Selector, AnyObject, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let imp = instance.method(for: selector)
        let function = unsafeBitCast(imp, to: InitIMP.self)

        guard let initialized = function(instance, selector, options, &error) as? NSObject else {
            throw error ?? NSError(domain: "MediaPipeRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize MPPHandLandmarker"])
        }

        if let error {
            throw error
        }

        return initialized
#endif
    }

    private static func makeMPImage(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> NSObject {
#if canImport(MediaPipeTasksVision)
        guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer, orientation: uiOrientationFromCG(orientation)) else {
            throw NSError(domain: "MediaPipeRuntime", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create MPImage from pixel buffer"])
        }
        return mpImage
#else
        guard let imageClass = NSClassFromString("MPPImage") as? NSObject.Type else {
            throw NSError(domain: "MediaPipeRuntime", code: 4, userInfo: [NSLocalizedDescriptionKey: "MPPImage class not found"])
        }

        let selector = NSSelectorFromString("initWithPixelBuffer:orientation:error:")
        let instance = imageClass.init()
        guard instance.responds(to: selector) else {
            throw NSError(domain: "MediaPipeRuntime", code: 5, userInfo: [NSLocalizedDescriptionKey: "initWithPixelBuffer:orientation:error: not found on MPPImage"])
        }

        var error: NSError?
        let uiOrientation = uiOrientationFromCG(orientation)
        typealias InitImageIMP = @convention(c) (AnyObject, Selector, CVPixelBuffer, UIImage.Orientation, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let imp = instance.method(for: selector)
        let function = unsafeBitCast(imp, to: InitImageIMP.self)

        guard let image = function(instance, selector, pixelBuffer, uiOrientation, &error) as? NSObject else {
            throw error ?? NSError(domain: "MediaPipeRuntime", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create MPPImage from pixel buffer"])
        }

        if let error {
            throw error
        }

        return image
#endif
    }

    private static func detectWithLandmarker(
        landmarker: NSObject,
        image: NSObject,
        timestampMs: Int64
    ) throws -> NSObject {
#if canImport(MediaPipeTasksVision)
        guard let typedLandmarker = landmarker as? HandLandmarker,
              let typedImage = image as? MPImage else {
            throw NSError(domain: "MediaPipeRuntime", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed typed cast for MediaPipe runtime detect"])
        }

        let result = try typedLandmarker.detect(videoFrame: typedImage, timestampInMilliseconds: Int(timestampMs))
        return result
#else
        let selector = NSSelectorFromString("detectVideoFrame:timestampInMilliseconds:error:")
        guard landmarker.responds(to: selector) else {
            throw NSError(domain: "MediaPipeRuntime", code: 7, userInfo: [NSLocalizedDescriptionKey: "detectVideoFrame:timestampInMilliseconds:error: not found on MPPHandLandmarker"])
        }

        var error: NSError?
        typealias DetectIMP = @convention(c) (AnyObject, Selector, AnyObject, Int, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let imp = landmarker.method(for: selector)
        let function = unsafeBitCast(imp, to: DetectIMP.self)

        guard let result = function(landmarker, selector, image, Int(timestampMs), &error) as? NSObject else {
            if let error {
                throw error
            }
            throw NSError(domain: "MediaPipeRuntime", code: 8, userInfo: [NSLocalizedDescriptionKey: "MediaPipe detectVideoFrame returned nil"])
        }

        if let error {
            throw error
        }

        return result
#endif
    }

    private static func parseResult(_ result: NSObject) -> [HandLandmarkSample] {
#if canImport(MediaPipeTasksVision)
        guard let typedResult = result as? HandLandmarkerResult else { return [] }

        var samples: [HandLandmarkSample] = []
        for handIndex in 0..<typedResult.landmarks.count {
            let handLandmarks = typedResult.landmarks[handIndex]
            var points: [SIMD3<Float>] = []
            points.reserveCapacity(21)

            for landmark in handLandmarks {
                points.append(SIMD3<Float>(Float(landmark.x), Float(landmark.y), Float(landmark.z)))
            }

            if points.count < 21 {
                points.append(contentsOf: Array(repeating: SIMD3<Float>(0.0, 0.0, 0.0), count: 21 - points.count))
            } else if points.count > 21 {
                points = Array(points.prefix(21))
            }

            var handedness: String?
            if handIndex < typedResult.handedness.count,
               let firstCategory = typedResult.handedness[handIndex].first {
                handedness = firstCategory.categoryName
            }

            samples.append(HandLandmarkSample(landmarks: points, handedness: handedness))
        }

        return samples
#else
        guard let landmarksGroups = result.value(forKey: "landmarks") as? NSArray else {
            return []
        }

        let handednessGroups = result.value(forKey: "handedness") as? NSArray

        var samples: [HandLandmarkSample] = []

        for i in 0..<landmarksGroups.count {
            guard let handLandmarks = landmarksGroups[i] as? NSArray else { continue }

            var points: [SIMD3<Float>] = []
            points.reserveCapacity(21)

            for pointObj in handLandmarks {
                guard let point = pointObj as? NSObject else { continue }
                let x = (point.value(forKey: "x") as? NSNumber)?.floatValue ?? 0.0
                let y = (point.value(forKey: "y") as? NSNumber)?.floatValue ?? 0.0
                let z = (point.value(forKey: "z") as? NSNumber)?.floatValue ?? 0.0

                let isLikelyValid = !(x == 0.0 && y == 0.0 && z == 0.0)
                if isLikelyValid {
                    points.append(SIMD3<Float>(x, y, z))
                } else {
                    points.append(SIMD3<Float>(0.0, 0.0, 0.0))
                }
            }

            if points.count < 21 {
                points.append(contentsOf: Array(repeating: SIMD3<Float>(0.0, 0.0, 0.0), count: 21 - points.count))
            } else if points.count > 21 {
                points = Array(points.prefix(21))
            }

            var handedness: String?
            if let handednessGroups,
               i < handednessGroups.count,
               let categories = handednessGroups[i] as? NSArray,
               let firstCategory = categories.firstObject as? NSObject,
               let categoryName = firstCategory.value(forKey: "categoryName") as? String {
                handedness = categoryName
            }

            samples.append(HandLandmarkSample(landmarks: points, handedness: handedness))
        }

        return samples
#endif
    }

    private static func uiOrientationFromCG(_ orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
