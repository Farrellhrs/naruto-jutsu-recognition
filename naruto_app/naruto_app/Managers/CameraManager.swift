import AVFoundation
import ImageIO
import Foundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    struct CameraOption: Identifiable, Equatable {
        let id: String
        let name: String
        let position: AVCaptureDevice.Position
    }

    @Published var cameraReady = false
    @Published var previewOrientation: AVCaptureVideoOrientation = .landscapeRight
    @Published var previewMirrored = true
    @Published var statusText: String = "Starting..."
    @Published var availableCameras: [CameraOption] = []
    @Published var selectedCameraID: String?

    let session = AVCaptureSession()
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "jutsu.master.camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "jutsu.master.camera.output.queue")

    private(set) var isFrontCamera = true
    private(set) var visionOrientation: CGImagePropertyOrientation = .up
    private(set) var captureStreamOrientation: AVCaptureVideoOrientation = .landscapeRight
    private(set) var captureStreamMirrored = false

    func start() {
#if targetEnvironment(simulator)
        statusText = "Use a real iPhone for camera mode."
        cameraReady = false
        return
#else
        checkCameraPermissionAndConfigure()
#endif
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func selectCamera(id: String) {
        selectedCameraID = id
        configureSession(preferredCameraID: id)
    }

    private func checkCameraPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureSession()
                } else {
                    DispatchQueue.main.async {
                        self.statusText = "Camera permission denied."
                        self.cameraReady = false
                    }
                }
            }
        case .denied, .restricted:
            statusText = "Camera permission denied."
        @unknown default:
            statusText = "Unknown camera permission state."
        }
    }

    private func configureSession(preferredCameraID: String? = nil) {
        let preferredCameraID = preferredCameraID ?? selectedCameraID
        sessionQueue.async { [weak self] in
            self?.configureSessionOnSessionQueue(preferredCameraID: preferredCameraID)
        }
    }

    private func configureSessionOnSessionQueue(preferredCameraID: String?) {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        DispatchQueue.main.async { [weak self] in
            self?.refreshAvailableCameras(from: devices)
        }

        guard let camera = chooseCamera(from: devices, preferredCameraID: preferredCameraID) else {
            DispatchQueue.main.async { [weak self] in
                self?.statusText = "No camera available."
                self?.cameraReady = false
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)

            session.beginConfiguration()
            session.sessionPreset = .high

            for existingInput in session.inputs {
                session.removeInput(existingInput)
            }

            for existingOutput in session.outputs {
                session.removeOutput(existingOutput)
            }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            let streamOrientation: AVCaptureVideoOrientation = .landscapeRight
            let shouldMirrorPreview = (camera.position != .back)
            var actualCaptureOrientation = streamOrientation
            var actualCaptureMirrored = false

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = streamOrientation
                    actualCaptureOrientation = connection.videoOrientation
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = shouldMirrorPreview
                    actualCaptureMirrored = connection.isVideoMirrored
                }
            }

            let computedVisionOrientation = makeImageOrientation(from: actualCaptureOrientation, mirrored: actualCaptureMirrored)
            let selectedID = camera.uniqueID

            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureStreamOrientation = actualCaptureOrientation
                self.captureStreamMirrored = actualCaptureMirrored
                self.isFrontCamera = shouldMirrorPreview
                self.previewOrientation = streamOrientation
                self.previewMirrored = shouldMirrorPreview
                self.visionOrientation = computedVisionOrientation
                self.selectedCameraID = selectedID
                self.cameraReady = true
                self.statusText = "Camera: \(camera.localizedName)"
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusText = "Camera setup failed"
                self?.cameraReady = false
            }
        }
    }

    private func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera,
        ]

        if #available(iOS 17.0, *) {
            types.append(.external)
            types.append(.continuityCamera)
        }

        return types
    }

    private func refreshAvailableCameras(from devices: [AVCaptureDevice]) {
        let options = devices.map {
            CameraOption(id: $0.uniqueID, name: $0.localizedName, position: $0.position)
        }
        availableCameras = options
    }

    private func chooseCamera(from devices: [AVCaptureDevice], preferredCameraID: String?) -> AVCaptureDevice? {
        if let preferredCameraID,
           let selected = devices.first(where: { $0.uniqueID == preferredCameraID }) {
            return selected
        }

        if let namedExternal = devices.first(where: {
            let lower = $0.localizedName.lowercased()
            return lower.contains("studio") || lower.contains("display") || lower.contains("monitor") || lower.contains("webcam")
        }) {
            return namedExternal
        }

        if #available(iOS 17.0, *) {
            if let continuity = devices.first(where: { $0.deviceType == .continuityCamera }) {
                return continuity
            }
            if let external = devices.first(where: { $0.deviceType == .external }) {
                return external
            }
        }

        if let front = devices.first(where: { $0.position == .front }) {
            return front
        }

        return devices.first(where: { $0.position == .back }) ?? devices.first
    }

    private func makeImageOrientation(
        from videoOrientation: AVCaptureVideoOrientation,
        mirrored: Bool
    ) -> CGImagePropertyOrientation {
        switch videoOrientation {
        case .portrait:
            return mirrored ? .leftMirrored : .right
        case .portraitUpsideDown:
            return mirrored ? .rightMirrored : .left
        case .landscapeLeft:
            return mirrored ? .upMirrored : .down
        case .landscapeRight:
            return mirrored ? .downMirrored : .up
        @unknown default:
            return mirrored ? .leftMirrored : .right
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer?(sampleBuffer)
    }
}
