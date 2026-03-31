import Foundation

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

#if os(iOS)
import AVFoundation
import CoreVideo

enum CameraSilhouetteCaptureState: Equatable {
    case requestingPermission
    case permissionDenied
    case restricted
    case sessionUnavailable(String)
    case running
}

final class CameraSilhouetteCapture: NSObject {
    let session = AVCaptureSession()

    var onStateChange: ((CameraSilhouetteCaptureState) -> Void)?
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.silhouette.capture.session")
    private let videoOutputQueue = DispatchQueue(label: "camera.silhouette.capture.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let minimumSegmentationFrameInterval = 1.0 / 30.0
    private var isConfigured = false
    private var lastProcessedTimestamp: Double?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            onStateChange?(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.onStateChange?(.permissionDenied)
                    }
                }
            }
        case .denied:
            onStateChange?(.permissionDenied)
        case .restricted:
            onStateChange?(.restricted)
        @unknown default:
            onStateChange?(.sessionUnavailable("Unknown camera permission state."))
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
                    DispatchQueue.main.async {
                        self.onStateChange?(.running)
                    }
                    return
                }

                self.session.startRunning()
                DispatchQueue.main.async {
                    self.onStateChange?(.running)
                }
            } catch let error as CameraSilhouetteCaptureConfigurationError {
                DispatchQueue.main.async {
                    self.onStateChange?(.sessionUnavailable(error.message))
                }
            } catch {
                DispatchQueue.main.async {
                    self.onStateChange?(.sessionUnavailable(error.localizedDescription))
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraSilhouetteCaptureConfigurationError(message: "Front camera unavailable.")
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
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
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
#endif
