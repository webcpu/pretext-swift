#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

struct CameraSilhouettePreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let maskImage: CGImage?

    func makeUIView(context _: Context) -> CameraSilhouettePreviewContainerView {
        let view = CameraSilhouettePreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.maskImage = maskImage
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return view
    }

    func updateUIView(_ uiView: CameraSilhouettePreviewContainerView, context _: Context) {
        uiView.previewLayer.session = session
        uiView.maskImage = maskImage
        if let connection = uiView.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class CameraSilhouettePreviewContainerView: UIView {
    private let maskLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = maskLayer
        maskLayer.contentsGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var maskImage: CGImage? {
        didSet {
            maskLayer.contents = maskImage
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLayer.frame = bounds
    }
}
#endif
