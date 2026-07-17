import SwiftUI
import UIKit

struct CameraGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameViewModel
    @State private var showTutorialIntro = false
    @State private var castBannerJutsu: JutsuType?
    @State private var flashJutsu: JutsuType?

    init(config: GameConfig) {
        _viewModel = StateObject(wrappedValue: GameViewModel(config: config))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraView(
                session: viewModel.session,
                hands: viewModel.overlayHands,
                faceDebugPoints: viewModel.faceDebugPoints,
                fireHands: viewModel.fireHands,
                fireScales: viewModel.fireScales,
                mouthPoint: viewModel.mouthPoint,
                fireballDirectionVector: viewModel.fireballDirectionVector,
                fireballDirectionVector3D: viewModel.fireballDirectionVector3D,
                fireballMouthOpen: viewModel.fireballMouthOpen,
                fireballMouthOpenNormalized: viewModel.fireballMouthOpenNormalized,
                fireballDepthScale: viewModel.fireballDepthScale,
                fireActive: viewModel.fireActive,
                activeJutsu: viewModel.activeEffectJutsu,
                selectedSummon: viewModel.selectedSummon,
                orientation: viewModel.previewOrientation,
                mirrored: viewModel.previewMirrored
            )
            .ignoresSafeArea()

            OverlayView(
                targetJutsu: viewModel.targetJutsu,
                activeJutsu: viewModel.activeEffectJutsu,
                sequenceProgressCount: viewModel.sequenceProgressCount,
                showGuidance: viewModel.config.mode != .free
            )

            if let flashJutsu {
                jutsuFlashColor(flashJutsu)
                    .opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if let castBannerJutsu {
                VStack {
                    JutsuCastBanner(jutsu: castBannerJutsu)
                        .padding(.top, 84)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if showTutorialIntro,
               viewModel.config.mode == .tutorial,
               let targetJutsu = viewModel.targetJutsu,
               let firstSign = targetJutsu.signSequence.first {
                TutorialIntroOverlay(jutsu: targetJutsu, sign: firstSign)
                    .transition(.opacity)
            }

            if viewModel.showResult, let jutsu = viewModel.resultJutsu {
                JutsuEffectView(
                    jutsu: jutsu,
                    elapsedText: viewModel.elapsedText,
                    showTime: viewModel.config.mode == .speed,
                    onRetry: { viewModel.retry() },
                    onBack: { dismiss() }
                )
            }

            if !viewModel.cameraReady {
                VStack {
                    Spacer()
                    Label("Camera", systemImage: "camera.fill")
                        .font(.headline)
                        .padding(12)
                        .background(.black.opacity(0.62))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            viewModel.start()
            if viewModel.config.mode == .tutorial {
                showTutorialIntro = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showTutorialIntro = false
                    }
                }
            }
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.resultJutsu) { _, newJutsu in
            guard let newJutsu else { return }
            presentCastEffects(for: newJutsu)
        }
    }

    private func presentCastEffects(for jutsu: JutsuType) {
        withAnimation(.easeOut(duration: 0.12)) {
            flashJutsu = jutsu
            castBannerJutsu = jutsu
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.4)) {
                flashJutsu = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                castBannerJutsu = nil
            }
            // In free mode nothing else consumes resultJutsu; clearing it lets
            // the next cast of the same jutsu re-fire onChange.
            if viewModel.config.mode == .free {
                viewModel.resultJutsu = nil
            }
        }
    }

    private func jutsuFlashColor(_ jutsu: JutsuType) -> Color {
        switch jutsu {
        case .fireball, .fire, .burningAsh: return .orange
        case .lightning: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .rasengan, .wind: return Color(red: 0.45, green: 0.85, blue: 1.0)
        case .waterDragon: return Color(red: 0.3, green: 0.6, blue: 1.0)
        case .kuchiyose: return Color(red: 0.9, green: 0.75, blue: 0.5)
        }
    }
}

private struct TutorialIntroOverlay: View {
    let jutsu: JutsuType
    let sign: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.46).ignoresSafeArea()

            VStack(spacing: 14) {
                Text(jutsu.title)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)

                Text("Follow this hand sign")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                TutorialHandsignImage(sign: sign)
                    .frame(width: 230, height: 230)
            }
            .padding(22)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct TutorialHandsignImage: View {
    let sign: String

    var body: some View {
        if let image = TutorialHandsignImageResolver.image(for: sign) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

private enum TutorialHandsignImageResolver {
    static func image(for sign: String) -> UIImage? {
        let base = normalize(sign)
        if let direct = Bundle.main.url(forResource: base, withExtension: "webp"),
           let data = try? Data(contentsOf: direct),
           let image = UIImage(data: data) {
            return image
        }

        if let inFolder = Bundle.main.url(forResource: base, withExtension: "png", subdirectory: "handsign_image"),
           let data = try? Data(contentsOf: inFolder),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(named: base)
    }

    private static func normalize(_ sign: String) -> String {
        let normalized = sign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch normalized {
        case "hare":
            return "Rabbit"
        default:
            return normalized.capitalized
        }
    }
}

#Preview {
    CameraGameView(config: GameConfig(mode: .free, selectedJutsu: nil))
}
