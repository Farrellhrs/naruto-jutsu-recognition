import AVFoundation
import SwiftUI

// MARK: - Theme

enum Ink {
    static let paper = Color(red: 0.07, green: 0.06, blue: 0.09)
    static let paperHigh = Color(red: 0.12, green: 0.10, blue: 0.15)
    static let crimson = Color(red: 0.86, green: 0.22, blue: 0.20)
    static let gold = Color(red: 0.95, green: 0.76, blue: 0.38)
    static let chakra = Color(red: 0.45, green: 0.80, blue: 1.0)
    static let faded = Color.white.opacity(0.6)
}

// MARK: - Camera preview

struct CameraSurface: UIViewRepresentable {
    let feed: CameraFeed

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
        var display: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        // Fill on iPhone; fit on Mac where windows have arbitrary aspect
        // ratios. HandConstellation.displayedVideoRect uses the same rule,
        // and the layer renders the very buffers recognition analyzes, so
        // overlay and video are always in exact agreement.
        view.display.videoGravity = CameraFeed.runningOnMac ? .resizeAspect : .resizeAspectFill
        feed.attach(displayLayer: view.display)
        return view
    }

    func updateUIView(_ uiView: Surface, context: Context) {
        feed.attach(displayLayer: uiView.display)
    }
}

// MARK: - Chakra constellation (hand skeleton overlay)

struct HandConstellation: View {
    let hands: [[CGPoint]]
    var videoSize: CGSize = .zero

    /// Bone connections in MediaPipe/Vision 21-landmark ordering.
    private static let bones: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),        // thumb
        (0, 5), (5, 6), (6, 7), (7, 8),        // index
        (5, 9), (9, 10), (10, 11), (11, 12),   // middle
        (9, 13), (13, 14), (14, 15), (15, 16), // ring
        (13, 17), (0, 17), (17, 18), (18, 19), (19, 20), // pinky + palm edge
    ]

    var body: some View {
        Canvas { context, size in
            // The camera video does not necessarily cover the whole canvas:
            // aspect-fit letterboxes it (Mac), aspect-fill crops it (iPhone).
            // Landmarks are normalized to the video frame, so map them into
            // the rectangle the video actually occupies on screen.
            let target = Self.displayedVideoRect(videoSize: videoSize, in: size)

            for hand in hands {
                guard hand.count == 21 else { continue }

                func pt(_ index: Int) -> CGPoint? {
                    let p = hand[index]
                    guard p.x >= 0 else { return nil }
                    return CGPoint(
                        x: target.minX + p.x * target.width,
                        y: target.minY + p.y * target.height
                    )
                }

                var bonePath = Path()
                for (a, b) in Self.bones {
                    guard let pa = pt(a), let pb = pt(b) else { continue }
                    bonePath.move(to: pa)
                    bonePath.addLine(to: pb)
                }
                context.stroke(bonePath, with: .color(Ink.chakra.opacity(0.55)), lineWidth: 2)

                for index in 0..<21 {
                    guard let p = pt(index) else { continue }
                    let radius: CGFloat = index == 0 ? 5 : 3
                    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Ink.chakra.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    static func displayedVideoRect(videoSize: CGSize, in canvas: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0,
              canvas.width > 0, canvas.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scaleFit = min(canvas.width / videoSize.width, canvas.height / videoSize.height)
        let scaleFill = max(canvas.width / videoSize.width, canvas.height / videoSize.height)
        let scale = CameraFeed.runningOnMac ? scaleFit : scaleFill
        let width = videoSize.width * scale
        let height = videoSize.height * scale
        return CGRect(
            x: (canvas.width - width) / 2,
            y: (canvas.height - height) / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Sign chip + hold ring

struct SignChip: View {
    let sign: HandSign
    var highlighted = false

    var body: some View {
        Text(sign.displayName)
            .font(.caption.weight(.black))
            .foregroundStyle(highlighted ? Ink.paper : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlighted ? Ink.gold : Color.white.opacity(0.14))
            .clipShape(Capsule())
    }
}

/// The current sign with a circular charge ring driven by hold progress.
struct HoldRing: View {
    let sign: HandSign?
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress >= 1 ? Ink.gold : Ink.chakra,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: progress)

            Text(sign?.displayName ?? "—")
                .font(.footnote.weight(.black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .frame(width: 52)
        }
        .frame(width: 74, height: 74)
        .background(Circle().fill(Color.black.opacity(0.45)))
    }
}

// MARK: - Cast callout

struct CastCallout: View {
    let jutsu: Jutsu

    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: jutsu.nature.symbol)
                .font(.title.weight(.black))
            Text(jutsu.name)
                .font(.title3.weight(.black))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(jutsu.nature.color.opacity(0.82))
                .shadow(color: jutsu.nature.color, radius: shown ? 22 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.7), lineWidth: 1.5)
        )
        .scaleEffect(shown ? 1 : 1.5)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                shown = true
            }
        }
    }
}

// MARK: - Brush title

struct BrushTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 40, weight: .black, design: .serif))
            .foregroundStyle(
                LinearGradient(colors: [.white, Ink.gold], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: Ink.crimson.opacity(0.65), radius: 14)
    }
}
