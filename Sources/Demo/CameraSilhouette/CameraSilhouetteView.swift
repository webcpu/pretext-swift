import SwiftUI
import Pretext
import PretextUI

struct CameraSilhouetteView: View {
    var body: some View {
        CameraSilhouetteLiveView()
    }
}

enum CameraSilhouetteOverlayState: Equatable {
    case requestingPermission
    case permissionDenied
    case restricted
    case cameraUnavailable(String)
    case runningNoPerson
    case runningWithPerson
}

struct CameraSilhouetteOverlayPanel: Equatable {
    let title: String
    let body: String
}

func cameraSilhouetteOverlayStatusText(for state: CameraSilhouetteOverlayState) -> String {
    switch state {
    case .requestingPermission:
        "Waiting for Permission"
    case .permissionDenied:
        "Camera Access Off"
    case .restricted:
        "Camera Restricted"
    case .cameraUnavailable:
        "Camera Unavailable"
    case .runningNoPerson:
        "Step into Frame"
    case .runningWithPerson:
        "Silhouette Live"
    }
}

func cameraSilhouetteOverlayPanel(for state: CameraSilhouetteOverlayState) -> CameraSilhouetteOverlayPanel? {
    switch state {
    case .requestingPermission:
        CameraSilhouetteOverlayPanel(
            title: "Allow Camera Access",
            body: "The article already lays out in fallback mode. Grant front-camera access to make the text flow around your live silhouette."
        )
    case .permissionDenied:
        CameraSilhouetteOverlayPanel(
            title: "Turn Camera Access Back On",
            body: "Open Settings for this app, allow Camera, then return here. The article will keep rendering normally until the live silhouette is available."
        )
    case .restricted:
        CameraSilhouetteOverlayPanel(
            title: "Camera Access Is Restricted",
            body: "This device currently blocks camera access. The article remains readable, but live silhouette wrapping cannot start in this state."
        )
    case let .cameraUnavailable(message):
        CameraSilhouetteOverlayPanel(
            title: "Camera Session Failed",
            body: message
        )
    case .runningNoPerson, .runningWithPerson:
        nil
    }
}

enum CameraSilhouettePalette {
    static let paperRGB = SituationalAwarenessPalette.paperRGB
    static let inkRGB = SituationalAwarenessPalette.inkRGB
    static let paper = SituationalAwarenessPalette.paper
    static let ink = SituationalAwarenessPalette.ink
    static let label = Color.white.opacity(0.88)
    static let secondaryLabel = Color.white.opacity(0.68)
    static let chipBackground = Color.black.opacity(0.34)
    static let panelBackground = Color.black.opacity(0.44)
    static let panelStroke = Color.white.opacity(0.12)
}

private enum CameraSilhouetteTypography {
    static let bodyFamily = "Iowan Old Style"
    static let bodyWeight = 0.1
    static let chromeFamily = "Helvetica Neue"

    static func articleFont(size: Double) -> Font {
        FontDescriptor(
            familyName: bodyFamily,
            size: size,
            weightValue: bodyWeight
        ).makeDisplayFont()
    }

    static let chipFont = FontDescriptor(
        familyName: chromeFamily,
        size: 12,
        weightValue: 0.2
    ).makeDisplayFont()

    static let panelTitleFont = FontDescriptor(
        familyName: chromeFamily,
        size: 16,
        weightValue: 0.32
    ).makeDisplayFont()

    static let panelBodyFont = FontDescriptor(
        familyName: chromeFamily,
        size: 13,
        weightValue: 0.05
    ).makeDisplayFont()
}

@MainActor
private final class CameraSilhouetteSceneModel: ObservableObject {
    @Published private(set) var captureState: CameraSilhouetteCaptureState = .requestingPermission
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var snapshot: CameraSilhouetteSnapshot?

    private let capture = CameraSilhouetteCapture()
    private let segmentation = CameraSilhouetteSegmentation()
    private let article = CameraSilhouetteResources.article

    private var latestSegmentation: CameraSilhouetteSegmentationResult?
    private var latestProjectedRows: [CameraSilhouetteMaskRow] = []
    private var viewportSize: CGSize = .zero
    private var topInset: Double = 0
    private var bottomInset: Double = 0
    private var hasStarted = false

    init() {
        let segmentation = self.segmentation

        capture.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            self.captureState = state
            if state != .running {
                self.latestSegmentation = nil
                self.latestProjectedRows = []
                self.previewImage = nil
            }
            self.recomputeSnapshot(force: true)
        }

        capture.onPixelBuffer = { pixelBuffer in
            segmentation.process(pixelBuffer: pixelBuffer)
        }

        segmentation.onResult = { [weak self] result in
            guard let self else {
                return
            }
            self.latestSegmentation = result
            self.previewImage = result?.cutoutImage
            self.recomputeSnapshot()
        }
    }

    var overlayState: CameraSilhouetteOverlayState {
        switch captureState {
        case .requestingPermission:
            .requestingPermission
        case .permissionDenied:
            .permissionDenied
        case .restricted:
            .restricted
        case let .sessionUnavailable(message):
            .cameraUnavailable(message)
        case .running:
            if latestSegmentation?.rows.isEmpty == false {
                .runningWithPerson
            } else {
                .runningNoPerson
            }
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        capture.start()
    }

    func stop() {
        hasStarted = false
        capture.stop()
    }

    func setViewport(size: CGSize, topInset: Double, bottomInset: Double) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        guard
            size != viewportSize ||
                topInset != self.topInset ||
                bottomInset != self.bottomInset
        else {
            return
        }

        viewportSize = size
        self.topInset = topInset
        self.bottomInset = bottomInset
        recomputeSnapshot(force: true)
    }

    private func recomputeSnapshot(force: Bool = false) {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            snapshot = nil
            latestProjectedRows = []
            return
        }

        let metrics = cameraSilhouettePageMetrics(
            viewportWidth: viewportSize.width,
            viewportHeight: viewportSize.height,
            topInset: topInset,
            bottomInset: bottomInset
        )
        let previewFrame = cameraSilhouettePreviewFrame(
            viewportWidth: viewportSize.width,
            viewportHeight: viewportSize.height,
            topInset: topInset,
            bottomInset: bottomInset
        )
        let previewRect = latestSegmentation.map {
            let localPreviewRect = cameraSilhouetteAspectFitRect(
                sourceSize: $0.imageSize,
                viewportSize: CGSize(width: previewFrame.width, height: previewFrame.height)
            )
            return WrapRect(
                x: previewFrame.x + localPreviewRect.x,
                y: previewFrame.y + localPreviewRect.y,
                width: localPreviewRect.width,
                height: localPreviewRect.height
            )
        } ?? previewFrame

        let projectedRows = latestSegmentation.map {
            projectCameraSilhouetteRows(
                $0.rows,
                from: previewRect,
                into: metrics.contentRect
            )
        } ?? []

        guard force || projectedRows != latestProjectedRows || snapshot == nil else {
            return
        }
        latestProjectedRows = projectedRows

        snapshot = evaluateCameraSilhouetteSnapshot(
            article: article,
            viewportWidth: viewportSize.width,
            viewportHeight: viewportSize.height,
            topInset: topInset,
            bottomInset: bottomInset,
            silhouetteRows: projectedRows
        )
    }
}

private struct CameraSilhouetteLiveView: View {
    @StateObject private var model = CameraSilhouetteSceneModel()

    var body: some View {
        GeometryReader { proxy in
            let previewFrame = cameraSilhouettePreviewFrame(
                viewportWidth: proxy.size.width,
                viewportHeight: proxy.size.height,
                topInset: proxy.safeAreaInsets.top,
                bottomInset: proxy.safeAreaInsets.bottom
            )
            ZStack(alignment: .topLeading) {
                CameraSilhouetteBackdrop()

                CameraSilhouetteSurfaceWash()

                CameraSilhouettePreviewWell(
                    state: model.captureState,
                    cutoutImage: model.previewImage,
                    frame: previewFrame
                )

                if let snapshot = model.snapshot {
                    CameraSilhouetteTextOverlay(snapshot: snapshot)
                }

                CameraSilhouetteChrome(state: model.overlayState)
            }
            .ignoresSafeArea()
            .onAppear { model.start() }
            .onDisappear { model.stop() }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                model.setViewport(
                    size: newSize,
                    topInset: proxy.safeAreaInsets.top,
                    bottomInset: proxy.safeAreaInsets.bottom
                )
            }
            .onChange(of: proxy.safeAreaInsets, initial: true) { _, insets in
                model.setViewport(
                    size: proxy.size,
                    topInset: insets.top,
                    bottomInset: insets.bottom
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CameraSilhouetteBackdrop: View {
    var body: some View {
        CameraSilhouettePalette.paper
        .ignoresSafeArea()
    }
}

private struct CameraSilhouetteSurfaceWash: View {
    var body: some View {
        Color.clear
        .ignoresSafeArea()
    }
}

private struct CameraSilhouettePreviewWell: View {
    let state: CameraSilhouetteCaptureState
    let cutoutImage: CGImage?
    let frame: WrapRect

    var body: some View {
        ZStack {
            if case .running = state, let cutoutImage {
                Image(decorative: cutoutImage, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.x, y: frame.y)
        .allowsHitTesting(false)
    }
}

private struct CameraSilhouetteTextOverlay: View {
    let snapshot: CameraSilhouetteSnapshot

    var body: some View {
        let metrics = snapshot.pageMetrics
        let articleFont = CameraSilhouetteTypography.articleFont(size: metrics.fontSize)

        ZStack(alignment: .topLeading) {
            ForEach(Array(snapshot.lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(articleFont)
                    .foregroundStyle(CameraSilhouettePalette.ink)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: line.x, y: line.y)
            }
        }
    }
}

private struct CameraSilhouetteChrome: View {
    let state: CameraSilhouetteOverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                chip("Live Camera")
                chip(statusText)
            }
            .padding(.top, 12)

            Spacer()

            if let panel = panelCopy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(panel.title)
                        .font(CameraSilhouetteTypography.panelTitleFont)
                        .foregroundStyle(CameraSilhouettePalette.label)

                    Text(panel.body)
                        .font(CameraSilhouetteTypography.panelBodyFont)
                        .foregroundStyle(CameraSilhouettePalette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CameraSilhouettePalette.panelBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(CameraSilhouettePalette.panelStroke, lineWidth: 1)
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(20)
    }

    private var statusText: String {
        cameraSilhouetteOverlayStatusText(for: state)
    }

    private var panelCopy: CameraSilhouetteOverlayPanel? {
        cameraSilhouetteOverlayPanel(for: state)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(CameraSilhouetteTypography.chipFont)
            .foregroundStyle(CameraSilhouettePalette.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(CameraSilhouettePalette.chipBackground))
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
    }
}

private enum CameraSilhouetteResources {
    static let article = loadArticle()

    private static func loadArticle() -> String {
        guard
            let url = Bundle.module.url(forResource: "article", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return """
            The camera feed stays live beneath the page while the article waits for a silhouette to interrupt the column.
            """
        }
        return text
    }
}
