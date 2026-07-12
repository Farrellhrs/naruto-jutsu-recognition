import AVFoundation
import Foundation
import ImageIO
import UIKit
import Vision

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

protocol FaceDirectionEstimating {
    var backendName: String { get }

    func estimateFaceDirection(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        overlayMirrorY: Bool,
        timestampMs: Int64
    ) throws -> FaceDirectionObservation?
}

enum FaceDirectionEstimatorFactory {
    static func makeEstimator(maxRange: CGFloat = 0.10, maxAngleDegrees: CGFloat = 45.0) -> FaceDirectionEstimating {
        let modelPath = Bundle.main.url(forResource: "face_landmarker", withExtension: "task")?.path

        if let modelPath,
           let mediaPipeEstimator = MediaPipeFaceDirectionEstimator(
               modelPath: modelPath,
               maxRange: maxRange,
               maxAngleDegrees: maxAngleDegrees
           ) {
            return mediaPipeEstimator
        }

        return VisionFaceDirectionEstimator(maxRange: maxRange, maxAngleDegrees: maxAngleDegrees)
    }
}

private enum FaceMeshLandmarkIndex {
    static let noseTip = 1
    static let leftMouthCorner = 61
    static let rightMouthCorner = 291
    static let upperLip = 13
    static let lowerLip = 14
    static let leftEyeOuter = 33
    static let rightEyeOuter = 263
}

private protocol FaceDirectionSmoothing: AnyObject {
    var previousSmoothedVector: FaceVector3D { get set }
}

private extension FaceDirectionSmoothing {
    func canonicalizePoint3D(
        _ point: SIMD3<Float>,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        overlayMirrorY: Bool
    ) -> SIMD3<Float> {
        var adjusted = point

        if isFrontCamera && !captureMirrored {
            adjusted.x = 1.0 - adjusted.x
        }

        if previewMirrored != captureMirrored {
            adjusted.x = 1.0 - adjusted.x
        }

        if overlayMirrorY {
            adjusted.y = 1.0 - adjusted.y
        }

        adjusted.x = min(1.0, max(0.0, adjusted.x))
        adjusted.y = min(1.0, max(0.0, adjusted.y))
        return adjusted
    }

    func point2D(_ point: SIMD3<Float>) -> CGPoint {
        CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }

    func distance2D(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return CGFloat(sqrt((dx * dx) + (dy * dy)))
    }

    func normalized3D(x: Float, y: Float, z: Float) -> FaceVector3D {
        let length = sqrt((x * x) + (y * y) + (z * z))
        if length > 1e-6 {
            return FaceVector3D(
                x: CGFloat(x / length),
                y: CGFloat(y / length),
                z: CGFloat(z / length)
            )
        }
        return FaceVector3D(x: 0, y: -1, z: 0)
    }

    func stableFaceScale(
        leftEye: SIMD3<Float>?,
        rightEye: SIMD3<Float>?,
        fallbackScale: CGFloat?,
        leftMouth: SIMD3<Float>,
        rightMouth: SIMD3<Float>
    ) -> CGFloat {
        if let leftEye, let rightEye {
            return max(1e-6, distance2D(leftEye, rightEye))
        }

        if let fallbackScale, fallbackScale > 1e-6 {
            return fallbackScale
        }

        return max(1e-6, distance2D(leftMouth, rightMouth))
    }

    func buildObservation(
        nosePointRaw: SIMD3<Float>,
        leftMouthRaw: SIMD3<Float>,
        rightMouthRaw: SIMD3<Float>,
        upperLipRaw: SIMD3<Float>,
        lowerLipRaw: SIMD3<Float>,
        leftEyeRaw: SIMD3<Float>?,
        rightEyeRaw: SIMD3<Float>?,
        fallbackFaceScale: CGFloat?,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        overlayMirrorY: Bool,
        backendName: String
    ) -> FaceDirectionObservation {
        let nosePoint3D = canonicalizePoint3D(
            nosePointRaw,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY
        )
        let leftMouth3D = canonicalizePoint3D(
            leftMouthRaw,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY
        )
        let rightMouth3D = canonicalizePoint3D(
            rightMouthRaw,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY
        )
        let upperLip3D = canonicalizePoint3D(
            upperLipRaw,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY
        )
        let lowerLip3D = canonicalizePoint3D(
            lowerLipRaw,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY
        )

        let leftEye3D = leftEyeRaw.map {
            canonicalizePoint3D(
                $0,
                isFrontCamera: isFrontCamera,
                captureMirrored: captureMirrored,
                previewMirrored: previewMirrored,
                overlayMirrorY: overlayMirrorY
            )
        }
        let rightEye3D = rightEyeRaw.map {
            canonicalizePoint3D(
                $0,
                isFrontCamera: isFrontCamera,
                captureMirrored: captureMirrored,
                previewMirrored: previewMirrored,
                overlayMirrorY: overlayMirrorY
            )
        }

        let mouthCenter = SIMD3<Float>(
            (leftMouth3D.x + rightMouth3D.x) * 0.5,
            (leftMouth3D.y + rightMouth3D.y) * 0.5,
            (leftMouth3D.z + rightMouth3D.z) * 0.5
        )

        let rawDX = nosePoint3D.x - mouthCenter.x
        let rawDY = nosePoint3D.y - mouthCenter.y
        let rawDZ = nosePoint3D.z - mouthCenter.z

        let dx = CGFloat(rawDX)
        let dy = CGFloat(rawDY)
        let dz = CGFloat(rawDZ)

        var normalized = normalized3D(x: rawDX, y: rawDY, z: rawDZ)

        // UIKit coordinates grow downward in Y, so invert Y for intuitive up/down direction.
        normalized = FaceVector3D(x: normalized.x, y: -normalized.y, z: normalized.z)

        let smoothed = FaceVector3D(
            x: (previousSmoothedVector.x * 0.8) + (normalized.x * 0.2),
            y: (previousSmoothedVector.y * 0.8) + (normalized.y * 0.2),
            z: (previousSmoothedVector.z * 0.8) + (normalized.z * 0.2)
        )

        let smoothedNormalized = normalized3D(
            x: Float(smoothed.x),
            y: Float(smoothed.y),
            z: Float(smoothed.z)
        )
        previousSmoothedVector = smoothedNormalized

        let mouthOpenDistance = CGFloat(abs(upperLip3D.y - lowerLip3D.y))
        let faceScale = stableFaceScale(
            leftEye: leftEye3D,
            rightEye: rightEye3D,
            fallbackScale: fallbackFaceScale,
            leftMouth: leftMouth3D,
            rightMouth: rightMouth3D
        )
        let normalizedOpen = mouthOpenDistance / max(faceScale, 1e-6)
        let isMouthOpen = normalizedOpen > 0.02

        return FaceDirectionObservation(
            nosePoint: point2D(nosePoint3D),
            leftMouthPoint: point2D(leftMouth3D),
            rightMouthPoint: point2D(rightMouth3D),
            upperLipPoint: point2D(upperLip3D),
            lowerLipPoint: point2D(lowerLip3D),
            mouthPoint: point2D(mouthCenter),
            deltaX: dx,
            deltaY: dy,
            deltaZ: dz,
            vectorX: smoothedNormalized.x,
            vectorY: smoothedNormalized.y,
            vectorZ: smoothedNormalized.z,
            mouthOpenDistance: mouthOpenDistance,
            faceScale: faceScale,
            normalizedMouthOpen: normalizedOpen,
            mouthOpen: isMouthOpen,
            backendName: backendName
        )
    }
}

#if canImport(MediaPipeTasksVision)
private final class MediaPipeFaceDirectionEstimator: FaceDirectionEstimating, FaceDirectionSmoothing {
    let backendName = "MediaPipe Face Mesh"

    var previousSmoothedVector = FaceVector3D(x: 0, y: -1, z: 0)

    private let landmarker: FaceLandmarker

    init?(modelPath: String, maxRange: CGFloat, maxAngleDegrees: CGFloat) {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return nil
        }

        _ = maxRange
        _ = maxAngleDegrees

        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelPath

        let options = FaceLandmarkerOptions()
        options.baseOptions = baseOptions
        options.runningMode = .video
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.45
        options.minFacePresenceConfidence = 0.45
        options.minTrackingConfidence = 0.45
        options.outputFaceBlendshapes = false
        options.outputFacialTransformationMatrixes = false

        guard let detector = try? FaceLandmarker(options: options) else {
            return nil
        }

        landmarker = detector
    }

    func estimateFaceDirection(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        overlayMirrorY: Bool,
        timestampMs: Int64
    ) throws -> FaceDirectionObservation? {
        let image = try MPImage(pixelBuffer: pixelBuffer, orientation: uiOrientationFromCG(orientation))
        let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: Int(timestampMs))

        guard let face = result.faceLandmarks.first,
              face.count > FaceMeshLandmarkIndex.rightMouthCorner else {
            return nil
        }

        let nose = face[FaceMeshLandmarkIndex.noseTip]
        let leftMouth = face[FaceMeshLandmarkIndex.leftMouthCorner]
        let rightMouth = face[FaceMeshLandmarkIndex.rightMouthCorner]
        let upperLip = face[FaceMeshLandmarkIndex.upperLip]
        let lowerLip = face[FaceMeshLandmarkIndex.lowerLip]
        let leftEye = face[FaceMeshLandmarkIndex.leftEyeOuter]
        let rightEye = face[FaceMeshLandmarkIndex.rightEyeOuter]

        return buildObservation(
            nosePointRaw: SIMD3<Float>(nose.x, nose.y, nose.z),
            leftMouthRaw: SIMD3<Float>(leftMouth.x, leftMouth.y, leftMouth.z),
            rightMouthRaw: SIMD3<Float>(rightMouth.x, rightMouth.y, rightMouth.z),
            upperLipRaw: SIMD3<Float>(upperLip.x, upperLip.y, upperLip.z),
            lowerLipRaw: SIMD3<Float>(lowerLip.x, lowerLip.y, lowerLip.z),
            leftEyeRaw: SIMD3<Float>(leftEye.x, leftEye.y, leftEye.z),
            rightEyeRaw: SIMD3<Float>(rightEye.x, rightEye.y, rightEye.z),
            fallbackFaceScale: nil,
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY,
            backendName: backendName
        )
    }

    private func uiOrientationFromCG(_ orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
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
#endif

private final class VisionFaceDirectionEstimator: FaceDirectionEstimating, FaceDirectionSmoothing {
    let backendName = "Vision Face Fallback"

    var previousSmoothedVector = FaceVector3D(x: 0, y: -1, z: 0)

    private let request = VNDetectFaceLandmarksRequest()

    init(maxRange: CGFloat, maxAngleDegrees: CGFloat) {
        _ = maxRange
        _ = maxAngleDegrees
    }

    func estimateFaceDirection(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        isFrontCamera: Bool,
        captureMirrored: Bool,
        previewMirrored: Bool,
        overlayMirrorY: Bool,
        timestampMs: Int64
    ) throws -> FaceDirectionObservation? {
        _ = timestampMs

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try handler.perform([request])

        guard let faces = request.results as? [VNFaceObservation],
              let face = faces.first,
              let landmarks = face.landmarks,
              let mouthRegion = landmarks.outerLips ?? landmarks.innerLips,
              !mouthRegion.normalizedPoints.isEmpty,
              let noseRegion = landmarks.nose,
              !noseRegion.normalizedPoints.isEmpty else {
            return nil
        }

        let mouthPoints = mouthRegion.normalizedPoints
        let leftLocal = mouthPoints.min(by: { $0.x < $1.x }) ?? mouthPoints[0]
        let rightLocal = mouthPoints.max(by: { $0.x < $1.x }) ?? mouthPoints[0]
        let upperLocal = mouthPoints.max(by: { $0.y < $1.y }) ?? mouthPoints[0]
        let lowerLocal = mouthPoints.min(by: { $0.y < $1.y }) ?? mouthPoints[0]

        let noseLocal = average(points: noseRegion.normalizedPoints)

        let leftEyeLocal: CGPoint?
        if let points = landmarks.leftEye?.normalizedPoints, !points.isEmpty {
            leftEyeLocal = average(points: points)
        } else {
            leftEyeLocal = nil
        }

        let rightEyeLocal: CGPoint?
        if let points = landmarks.rightEye?.normalizedPoints, !points.isEmpty {
            rightEyeLocal = average(points: points)
        } else {
            rightEyeLocal = nil
        }

        let leftGlobal = toGlobal(local: leftLocal, bbox: face.boundingBox)
        let rightGlobal = toGlobal(local: rightLocal, bbox: face.boundingBox)
        let upperGlobal = toGlobal(local: upperLocal, bbox: face.boundingBox)
        let lowerGlobal = toGlobal(local: lowerLocal, bbox: face.boundingBox)
        let noseGlobal = toGlobal(local: noseLocal, bbox: face.boundingBox)
        let leftEyeGlobal = leftEyeLocal.map { toGlobal(local: $0, bbox: face.boundingBox) }
        let rightEyeGlobal = rightEyeLocal.map { toGlobal(local: $0, bbox: face.boundingBox) }

        return buildObservation(
            nosePointRaw: SIMD3<Float>(Float(noseGlobal.x), Float(noseGlobal.y), 0),
            leftMouthRaw: SIMD3<Float>(Float(leftGlobal.x), Float(leftGlobal.y), 0),
            rightMouthRaw: SIMD3<Float>(Float(rightGlobal.x), Float(rightGlobal.y), 0),
            upperLipRaw: SIMD3<Float>(Float(upperGlobal.x), Float(upperGlobal.y), 0),
            lowerLipRaw: SIMD3<Float>(Float(lowerGlobal.x), Float(lowerGlobal.y), 0),
            leftEyeRaw: leftEyeGlobal.map { eye in
                SIMD3<Float>(Float(eye.x), Float(eye.y), 0)
            },
            rightEyeRaw: rightEyeGlobal.map { eye in
                SIMD3<Float>(Float(eye.x), Float(eye.y), 0)
            },
            fallbackFaceScale: max(face.boundingBox.height, 1e-6),
            isFrontCamera: isFrontCamera,
            captureMirrored: captureMirrored,
            previewMirrored: previewMirrored,
            overlayMirrorY: overlayMirrorY,
            backendName: backendName
        )
    }

    private func toGlobal(local: CGPoint, bbox: CGRect) -> CGPoint {
        CGPoint(
            x: bbox.origin.x + (local.x * bbox.size.width),
            y: bbox.origin.y + (local.y * bbox.size.height)
        )
    }

    private func average(points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }

        let sx = points.reduce(CGFloat(0)) { $0 + $1.x }
        let sy = points.reduce(CGFloat(0)) { $0 + $1.y }
        return CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count))
    }
}
