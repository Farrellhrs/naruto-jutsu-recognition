import AVFoundation
import CoreMedia

/// Thin AVFoundation wrapper: front camera in, sample buffers out.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let runningOnMac = ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp

    let session = AVCaptureSession()

    /// Called on the capture queue for every frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// Set on the main queue once the session is running.
    var onReadyChange: ((Bool) -> Void)?

    /// The on-screen video surface. It is fed the exact buffers that go to
    /// recognition, so the preview and the landmark overlay can never
    /// disagree about rotation, mirroring, or aspect.
    private weak var displayLayer: AVSampleBufferDisplayLayer?

    func attach(displayLayer layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        layer.videoGravity = usesFillGravity ? .resizeAspectFill : .resizeAspect
    }

    private let sessionQueue = DispatchQueue(label: "camera.feed.session")
    private let outputQueue = DispatchQueue(label: "camera.feed.output", qos: .userInitiated)
    private var configured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var videoConnection: AVCaptureConnection?

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configure()
            }
            guard self.configured else { return }
            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async { self.onReadyChange?(running) }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.onReadyChange?(false) }
        }
    }

    /// True when frames should aspect-fill the screen (landscape sources);
    /// false for portrait sources, where fill would crop-zoom drastically.
    private(set) var usesFillGravity = !CameraFeed.runningOnMac

    private func configure() {
        var pickedCamera: AVCaptureDevice?
        var usingExternal = false

        if Self.runningOnMac {
            // On a Mac, the "front camera" is an emulated iPad camera whose
            // upright orientation is portrait. The real webcam is exposed as
            // an external device and delivers native landscape — prefer it.
            let external = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            ).devices.first
            if let external, external.deviceType == .external {
                pickedCamera = external
                usingExternal = true
            }
        }
        if pickedCamera == nil {
            pickedCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        guard let camera = pickedCamera,
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            videoConnection = connection

            if Self.runningOnMac {
                // The emulated iPad camera's synthetic orientation metadata
                // makes RotationCoordinator report 0 even though upright is
                // 90 (verified empirically). The real external webcam is
                // native landscape and needs no rotation.
                let angle: CGFloat = usingExternal ? 0 : 90
                applyRotation(angle)
                usesFillGravity = usingExternal
            } else {
                // Real devices: let AVFoundation report the upright angle
                // (iPhone portrait 90°, Continuity Camera any mount) and
                // track changes.
                let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
                rotationCoordinator = coordinator
                applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
                rotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelCapture,
                    options: [.new]
                ) { [weak self] _, change in
                    guard let angle = change.newValue else { return }
                    self?.sessionQueue.async {
                        self?.applyRotation(angle)
                    }
                }
            }

            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        // Push the gravity decision to the display layer once it is known.
        let fill = usesFillGravity
        DispatchQueue.main.async { [weak self] in
            self?.displayLayer?.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        }

        session.commitConfiguration()
        configured = true
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection = videoConnection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if let layer = displayLayer {
            markDisplayImmediately(sampleBuffer)
            let renderer = layer.sampleBufferRenderer
            if renderer.requiresFlushToResumeDecoding {
                renderer.flush()
            }
            if renderer.isReadyForMoreMediaData {
                renderer.enqueue(sampleBuffer)
            }
        }
        onFrame?(sampleBuffer)
    }

    /// Live camera buffers carry device-clock timestamps the display layer
    /// has no timebase for; mark them to render as soon as they arrive.
    private func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }
}
