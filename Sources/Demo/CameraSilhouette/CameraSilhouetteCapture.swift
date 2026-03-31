import Foundation

#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
#endif

func cameraSilhouetteShouldProcessFrame(
    currentTimestamp: Double,
    lastProcessedTimestamp: Double?,
    minimumInterval: Double
) -> Bool {
    guard currentTimestamp.isFinite else {
        return true
    }
    guard let lastProcessedTimestamp else {
        return true
    }
    return currentTimestamp - lastProcessedTimestamp >= minimumInterval
}

struct CameraSilhouetteCapturePolicy: Equatable {
    var prefersFrontCamera: Bool
    var usesPortraitOrientation: Bool
}

func cameraSilhouetteCapturePolicy(
    for platform: DemoNavigationPlatform = .current
) -> CameraSilhouetteCapturePolicy {
    switch platform {
    case .ios:
        CameraSilhouetteCapturePolicy(
            prefersFrontCamera: true,
            usesPortraitOrientation: true
        )
    case .macOS:
        CameraSilhouetteCapturePolicy(
            prefersFrontCamera: false,
            usesPortraitOrientation: false
        )
    }
}

#if canImport(AVFoundation)
func cameraSilhouetteShouldMirrorCapture(
    devicePosition: AVCaptureDevice.Position,
    platform: DemoNavigationPlatform = .current
) -> Bool {
    switch platform {
    case .ios:
        true
    case .macOS:
        devicePosition == .front
    }
}

enum CameraSilhouetteCaptureState: Equatable {
    case requestingPermission
    case permissionDenied
    case restricted
    case sessionUnavailable(String)
    case running
}

final class CameraSilhouetteCapture: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    var onStateChange: (@MainActor @Sendable (CameraSilhouetteCaptureState) -> Void)?
    var onPixelBuffer: (@Sendable (CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.silhouette.capture.session")
    private let videoOutputQueue = DispatchQueue(label: "camera.silhouette.capture.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let minimumSegmentationFrameInterval = 1.0 / 30.0
    private var isConfigured = false
    private var lastProcessedTimestamp: Double?
    private let policy = cameraSilhouetteCapturePolicy()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            notifyStateChange(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }
                if granted {
                    self.configureAndRun()
                } else {
                    self.notifyStateChange(.permissionDenied)
                }
            }
        case .denied:
            notifyStateChange(.permissionDenied)
        case .restricted:
            notifyStateChange(.restricted)
        @unknown default:
            notifyStateChange(.sessionUnavailable("Unknown camera permission state."))
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
        videoOutputQueue.async {
            self.lastProcessedTimestamp = nil
        }
    }

    private func configureAndRun() {
        sessionQueue.async {
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                guard !self.session.isRunning else {
                    self.notifyStateChange(.running)
                    return
                }

                self.session.startRunning()
                self.notifyStateChange(.running)
            } catch let error as CameraSilhouetteCaptureConfigurationError {
                self.notifyStateChange(.sessionUnavailable(error.message))
            } catch {
                self.notifyStateChange(.sessionUnavailable(error.localizedDescription))
            }
        }
    }

    private func notifyStateChange(_ state: CameraSilhouetteCaptureState) {
        let onStateChange = self.onStateChange
        Task { @MainActor in
            onStateChange?(state)
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let camera = cameraSilhouettePreferredCamera(policy: policy) else {
            throw CameraSilhouetteCaptureConfigurationError(message: "No compatible camera is available.")
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraSilhouetteCaptureConfigurationError(message: "Unable to attach the front camera.")
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CameraSilhouetteCaptureConfigurationError(message: "Unable to read camera frames.")
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            #if os(iOS)
            if policy.usesPortraitOrientation, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            #endif
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = cameraSilhouetteShouldMirrorCapture(
                    devicePosition: camera.position,
                    platform: .current
                )
            }
        }
    }
}

extension CameraSilhouetteCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard cameraSilhouetteShouldProcessFrame(
            currentTimestamp: timestamp,
            lastProcessedTimestamp: lastProcessedTimestamp,
            minimumInterval: minimumSegmentationFrameInterval
        ) else {
            return
        }
        lastProcessedTimestamp = timestamp
        onPixelBuffer?(pixelBuffer)
    }
}

private struct CameraSilhouetteCaptureConfigurationError: Error {
    var message: String
}

private func cameraSilhouettePreferredCamera(
    policy: CameraSilhouetteCapturePolicy
) -> AVCaptureDevice? {
    if policy.prefersFrontCamera {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    return AVCaptureDevice.default(for: .video)
        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
}
#endif
