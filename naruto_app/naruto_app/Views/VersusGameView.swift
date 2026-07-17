import AVFoundation
import SwiftUI

/// Two-player duel: the screen (and camera frame) is split down the middle.
/// Each player performs signs on their half; completed jutsu fly across
/// at the opponent, who can block by casting the elemental counter in time.
struct VersusGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VersusViewModel()
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                VersusCameraPreview(session: viewModel.session, mirrored: viewModel.previewMirrored)
                    .ignoresSafeArea()

                centerDivider(in: geometry.size)

                attackLayer(in: geometry.size)

                burstLayer

                hud(in: geometry.size)

                castBannerLayer(in: geometry.size)

                if let winner = viewModel.winner {
                    winnerOverlay(winner)
                }

                if !viewModel.cameraReady {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.headline)
                        .padding(12)
                        .background(.black.opacity(0.62))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }
            .offset(x: shakeOffset)
            .onAppear {
                viewModel.updateArenaSize(geometry.size)
                viewModel.start()
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.updateArenaSize(newSize)
            }
            .onChange(of: viewModel.hitPulse) { _, _ in
                triggerScreenShake()
            }
            .onDisappear { viewModel.stop() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Layers

    private func centerDivider(in size: CGSize) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2)
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
    }

    private func hud(in size: CGSize) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                playerPanel(
                    name: "P1",
                    hp: viewModel.leftHP,
                    detected: viewModel.leftDetectedSign,
                    status: viewModel.leftStatus,
                    accent: .orange,
                    alignment: .leading,
                    width: size.width * 0.42
                )

                Spacer()

                playerPanel(
                    name: "P2",
                    hp: viewModel.rightHP,
                    detected: viewModel.rightDetectedSign,
                    status: viewModel.rightStatus,
                    accent: .cyan,
                    alignment: .trailing,
                    width: size.width * 0.42
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer()

            Text("Block incoming jutsu by casting its counter element")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
                .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
    }

    private func playerPanel(
        name: String,
        hp: Int,
        detected: String,
        status: String,
        accent: Color,
        alignment: HorizontalAlignment,
        width: CGFloat
    ) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(accent)
                Text("\(hp)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: hp)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(hp > 30 ? accent : Color.red)
                    .frame(width: max(0, width * CGFloat(hp) / 100))
                    .animation(.easeOut(duration: 0.3), value: hp)
            }
            .frame(width: width, height: 9)

            if !detected.isEmpty {
                Text("Sign: \(detected.capitalized)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .padding(10)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func attackLayer(in size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            ZStack {
                ForEach(viewModel.attacks) { attack in
                    let progress = CGFloat(attack.progress(at: timeline.date))
                    let fromLeft = attack.from == .left
                    let startX = fromLeft ? size.width * 0.22 : size.width * 0.78
                    let endX = fromLeft ? size.width * 0.84 : size.width * 0.16
                    let x = startX + (endX - startX) * progress
                    let y = size.height * 0.45 + sin(progress * .pi) * -40

                    VersusProjectile(jutsu: attack.jutsu, facingRight: fromLeft)
                        .position(x: x, y: y)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var burstLayer: some View {
        ZStack {
            ForEach(viewModel.bursts) { burst in
                let progress = CGFloat(min(1, burst.age / burst.lifetime))
                Circle()
                    .stroke(
                        Color(hexValue: burst.colorHex).opacity(1 - Double(progress)),
                        lineWidth: 5 * (1 - progress) + 1
                    )
                    .frame(width: burst.maxRadius * 2 * progress, height: burst.maxRadius * 2 * progress)
                    .position(burst.position)
            }
        }
        .allowsHitTesting(false)
    }

    private func castBannerLayer(in size: CGSize) -> some View {
        ZStack {
            ForEach(viewModel.castEvents) { event in
                JutsuCastBanner(jutsu: event.jutsu, compact: true)
                    .position(
                        x: event.side == .left ? size.width * 0.25 : size.width * 0.75,
                        y: size.height * 0.30
                    )
                    .opacity(event.age > 1.0 ? max(0, 1.4 - event.age) / 0.4 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func winnerOverlay(_ winner: VersusViewModel.Side) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.7), radius: 16)

                Text("\(winner.rawValue) Wins!")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Button {
                        viewModel.rematch()
                    } label: {
                        Label("Rematch", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func triggerScreenShake() {
        let sequence: [CGFloat] = [10, -9, 7, -5, 3, 0]
        for (index, offset) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                withAnimation(.linear(duration: 0.04)) {
                    shakeOffset = offset
                }
            }
        }
    }
}

// MARK: - Projectile visual

private struct VersusProjectile: View {
    let jutsu: JutsuType
    let facingRight: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.95), accent, accent.opacity(0.25)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 22
                    )
                )
                .frame(width: 40, height: 40)

            // Trailing streak.
            Capsule()
                .fill(LinearGradient(
                    colors: facingRight ? [accent.opacity(0), accent.opacity(0.7)] : [accent.opacity(0.7), accent.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 60, height: 10)
                .offset(x: facingRight ? -40 : 40)
        }
        .shadow(color: accent.opacity(0.85), radius: 16)
    }

    private var accent: Color {
        switch jutsu {
        case .fireball, .fire, .burningAsh: return .orange
        case .lightning: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .rasengan, .wind: return Color(red: 0.45, green: 0.85, blue: 1.0)
        case .waterDragon: return Color(red: 0.3, green: 0.6, blue: 1.0)
        case .kuchiyose: return Color(red: 0.9, green: 0.75, blue: 0.5)
        }
    }
}

// MARK: - Minimal camera preview

private struct VersusCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let connection = uiView.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}

private extension Color {
    init(hexValue: UInt32) {
        let r = Double((hexValue >> 16) & 0xFF) / 255.0
        let g = Double((hexValue >> 8) & 0xFF) / 255.0
        let b = Double(hexValue & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    VersusGameView()
}
