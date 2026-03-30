import AVFoundation
import CoreVideo
import Pretext
import PretextUI
import SwiftUI

private let chikaDanceVideoAspect = 1920.0 / 1080.0

private final class VideoFrameProvider: @unchecked Sendable {
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var loopObserver: Any?
    var currentFrame: ChromaKeyFrame?
    var isMuted: Bool = false
    var debugInfo: String = "not started"

    func start() {
        guard let url = Bundle.module.url(forResource: "dance", withExtension: "mp4") else {
            debugInfo = "dance.mp4 not found"
            return
        }
        debugInfo = "loading..."

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let attributes: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        videoOutput = output

        let p = AVPlayer(playerItem: item)
        isMuted = UserDefaults.standard.bool(forKey: "chikaDanceMuted")
        p.isMuted = isMuted
        player = p

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        p.play()
        debugInfo = "playing"
    }

    func stop() {
        player?.pause()
        if let obs = loopObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        UserDefaults.standard.set(isMuted, forKey: "chikaDanceMuted")
    }

    func grabFrame() -> ChromaKeyFrame? {
        guard let output = videoOutput else {
            return currentFrame
        }

        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else {
            if currentFrame == nil {
                debugInfo = "waiting for frames (status=\(player?.status.rawValue ?? -1))"
            }
            return currentFrame
        }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        debugInfo = "frame \(w)x\(h)"

        if let frame = processChromaKeyFrame(buffer) {
            debugInfo = "hull=\(frame.hull.count)pts bounds=\(Int(frame.boundsFraction.width * 100))%x\(Int(frame.boundsFraction.height * 100))%"
            currentFrame = frame
        } else {
            debugInfo = "processChromaKeyFrame returned nil"
        }

        return currentFrame
    }
}

struct ChikaDanceView: View {
    @State private var video = VideoFrameProvider()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: false)) { _ in
                let pageWidth = Double(proxy.size.width)
                let pageHeight = Double(proxy.size.height)

                let frame = video.grabFrame()
                let characterRect = computeCharacterRect(
                    frame: frame, pageWidth: pageWidth, pageHeight: pageHeight
                )
                let hull = frame?.hull ?? []
                let snapshot = evaluateChikaDanceLayout(
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    characterHull: hull,
                    characterRect: characterRect
                )

                Canvas(opaque: true) { context, size in
                    // Dark background
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(ChikaDancePalette.background)
                    )

                    // Character (drawn in isolated layer so clip doesn't affect text)
                    if let cgImage = frame?.image {
                        let screenHull = transformWrapPoints(hull, rect: characterRect, angle: 0)
                        if screenHull.count >= 3 {
                            let destRect = CGRect(
                                x: characterRect.x, y: characterRect.y,
                                width: characterRect.width, height: characterRect.height
                            )
                            context.drawLayer { layer in
                                layer.clip(to: Path { path in
                                    path.move(to: CGPoint(x: screenHull[0].x, y: screenHull[0].y))
                                    for p in screenHull.dropFirst() {
                                        path.addLine(to: CGPoint(x: p.x, y: p.y))
                                    }
                                    path.closeSubpath()
                                })
                                layer.draw(
                                    Image(decorative: cgImage, scale: 1),
                                    in: destRect
                                )
                            }
                        }
                    }

                    // Drop cap
                    let dcText = Text(String(OrbEditorialText.body.prefix(1)))
                        .font(Font(ChikaDanceMetrics.dropCapFont()))
                    var dcResolved = context.resolve(dcText)
                    dcResolved.shading = .color(ChikaDancePalette.dropCap)
                    context.draw(dcResolved,
                                 at: CGPoint(x: snapshot.dropCapPosition.x, y: snapshot.dropCapPosition.y),
                                 anchor: .topLeading)

                    // Body text lines
                    let bodyFont = ChikaDanceMetrics.bodyFontDescriptor.makeDisplayFont()
                    for line in snapshot.bodyLines {
                        let t = Text(line.text).font(bodyFont)
                        var r = context.resolve(t)
                        r.shading = .color(ChikaDancePalette.bodyText)
                        context.draw(r, at: CGPoint(x: line.x, y: line.y), anchor: .topLeading)
                    }

                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(alignment: .bottom) {
                    ChikaDanceStatsBar(
                        lineCount: snapshot.bodyLines.count,
                        reflowMs: snapshot.reflowMilliseconds,
                        columnCount: snapshot.columnCount,
                        isMuted: video.isMuted,
                        onToggleMute: { video.toggleMute() }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { video.start() }
        .onDisappear { video.stop() }
    }

    private func computeCharacterRect(
        frame: ChromaKeyFrame?,
        pageWidth: Double,
        pageHeight: Double
    ) -> WrapRect {
        computeChikaCharacterRect(
            boundsFraction: frame?.boundsFraction,
            pageWidth: pageWidth,
            pageHeight: pageHeight
        )
    }
}

func computeChikaCharacterRect(
    boundsFraction: WrapRect?,
    pageWidth: Double,
    pageHeight: Double
) -> WrapRect {
    guard let bounds = boundsFraction else {
        return WrapRect(x: pageWidth * 0.3, y: 50, width: pageWidth * 0.4, height: pageHeight - 150)
    }

    let videoAspect = bounds.width / bounds.height * chikaDanceVideoAspect
    let maxHeight = pageHeight - ChikaDanceMetrics.gutter - ChikaDanceMetrics.statsBarHeight - 16
    let baseHeight = min(maxHeight, pageHeight * 0.5)
    let baseWidth = baseHeight * videoAspect
    let widthCap = pageWidth * 0.45
    let scale = min(1, widthCap / max(baseWidth, 1))
    let characterWidth = baseWidth * scale
    let characterHeight = baseHeight * scale

    let videoCenterX = bounds.x + bounds.width / 2
    let videoCenterY = bounds.y + bounds.height / 2
    let screenX = videoCenterX * pageWidth - characterWidth / 2
    let screenY = videoCenterY * pageHeight - characterHeight / 2

    let clampedX = max(0, min(screenX, pageWidth - characterWidth))
    let clampedY = max(ChikaDanceMetrics.gutter, min(screenY, pageHeight - ChikaDanceMetrics.statsBarHeight - characterHeight))

    return WrapRect(
        x: clampedX,
        y: clampedY,
        width: characterWidth,
        height: characterHeight
    )
}

// MARK: - Stats bar

private struct ChikaDanceStatsBar: View {
    let lineCount: Int
    let reflowMs: Double
    let columnCount: Int
    let isMuted: Bool
    let onToggleMute: () -> Void

    private static let labelFont = FontDescriptor(
        familyName: "Helvetica Neue", size: 10
    ).makeDisplayFont()

    private static let valueFont = FontDescriptor(
        familyName: "Helvetica Neue", size: 12, weightValue: 0.23
    ).makeDisplayFont()

    var body: some View {
        HStack(spacing: 18) {
            statItem("Lines", value: "\(lineCount)")
            statItem("Reflow", value: String(format: "%.1fms", reflowMs))
            statItem("Columns", value: "\(columnCount)")

            Button(action: onToggleMute) {
                Text(isMuted ? "Unmute" : "Mute")
                    .font(Self.valueFont)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: ChikaDanceMetrics.statsBarHeight)
        .background(.ultraThinMaterial)
        .background(ChikaDancePalette.statsBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChikaDancePalette.statsBorder)
                .frame(height: 1)
        }
    }

    private func statItem(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(Self.labelFont)
                .tracking(0.5)
                .foregroundStyle(ChikaDancePalette.statsLabel)
            Text(value)
                .font(Self.valueFont)
                .foregroundStyle(ChikaDancePalette.statsValue)
        }
    }
}
