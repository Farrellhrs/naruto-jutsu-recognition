import Combine
import SwiftUI
import UIKit

struct BattleGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraViewModel: GameViewModel
    @StateObject private var battleViewModel: BattleModeViewModel

    private let battleTick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(config: GameConfig) {
        _cameraViewModel = StateObject(wrappedValue: GameViewModel(config: config))
        _battleViewModel = StateObject(wrappedValue: BattleModeViewModel(initialSasukeHP: config.initialSasukeHP))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                CameraView(
                    session: cameraViewModel.session,
                    hands: cameraViewModel.overlayHands,
                    faceDebugPoints: cameraViewModel.faceDebugPoints,
                    fireHands: cameraViewModel.fireHands,
                    fireScales: cameraViewModel.fireScales,
                    mouthPoint: cameraViewModel.mouthPoint,
                    fireballDirectionVector: cameraViewModel.fireballDirectionVector,
                    fireballDirectionVector3D: cameraViewModel.fireballDirectionVector3D,
                    fireballMouthOpen: cameraViewModel.fireballMouthOpen,
                    fireballMouthOpenNormalized: cameraViewModel.fireballMouthOpenNormalized,
                    fireballDepthScale: cameraViewModel.fireballDepthScale,
                    fireActive: cameraViewModel.fireActive,
                    activeJutsu: cameraViewModel.activeEffectJutsu,
                    selectedSummon: cameraViewModel.selectedSummon,
                    orientation: cameraViewModel.previewOrientation,
                    mirrored: cameraViewModel.previewMirrored
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [Color.black.opacity(0.68), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.45)
                .ignoresSafeArea()

                sasukeColumn(in: geometry.size)

                battleHUD(in: geometry.size)

                projectileLayer

                floatingFeedbackLayer

                if battleViewModel.state == .playerDefend,
                   let defendTarget = battleViewModel.defendTargetJutsu {
                    OverlayView(
                        targetJutsu: defendTarget,
                        activeJutsu: cameraViewModel.activeEffectJutsu,
                        sequenceProgressCount: cameraViewModel.sequenceProgressCount,
                        showGuidance: true
                    )
                }

                if battleViewModel.state == .gameOver {
                    gameOverOverlay
                }

                if !cameraViewModel.cameraReady {
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
            .onAppear {
                battleViewModel.updateArenaSize(geometry.size)
                cameraViewModel.start()
                battleViewModel.startBattle()
                cameraViewModel.setBattleDefendTarget(battleViewModel.defendTargetJutsu)
            }
            .onChange(of: geometry.size) { _, newSize in
                battleViewModel.updateArenaSize(newSize)
            }
            .onChange(of: battleViewModel.defendTargetJutsu) { _, newTarget in
                cameraViewModel.setBattleDefendTarget(newTarget)
            }
            .onReceive(battleTick) { _ in
                battleViewModel.tick(deltaTime: 1.0 / 30.0)
            }
            .onReceive(cameraViewModel.$resultJutsu) { jutsu in
                battleViewModel.registerPlayerJutsuTrigger(jutsu)
            }
            .onDisappear {
                cameraViewModel.setBattleDefendTarget(nil)
                cameraViewModel.stop()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func sasukeColumn(in size: CGSize) -> some View {
        let isEnemyAttacking = battleViewModel.state == .enemyAttack || battleViewModel.state == .playerDefend

        return VStack {
            Spacer(minLength: size.height * 0.08)

            Image(uiImage: sasukeImage)
                .resizable()
                .scaledToFit()
                .frame(width: max(120, size.width * 0.30), height: max(220, size.height * 0.60))
                .scaleEffect(isEnemyAttacking ? 1.05 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.red.opacity(isEnemyAttacking ? 0.88 : 0), lineWidth: isEnemyAttacking ? 4 : 0)
                )
                .shadow(color: isEnemyAttacking ? .red.opacity(0.55) : .black.opacity(0.48), radius: isEnemyAttacking ? 20 : 12, x: 0, y: 6)
                .animation(.easeInOut(duration: 0.24), value: isEnemyAttacking)

            Spacer()
        }
        .frame(width: max(150, size.width * 0.36), alignment: .leading)
        .padding(.leading, 8)
    }

    private var sasukeImage: UIImage {
        if let directURL = Bundle.main.url(forResource: "sasuke", withExtension: "png", subdirectory: "character"),
           let data = try? Data(contentsOf: directURL),
           let image = UIImage(data: data) {
            return image
        }

        if let directURL = Bundle.main.url(forResource: "sasuke", withExtension: "png"),
           let data = try? Data(contentsOf: directURL),
           let image = UIImage(data: data) {
            return image
        }

        if let directURL = Bundle.main.url(forResource: "sasuke", withExtension: "jpg", subdirectory: "character"),
           let data = try? Data(contentsOf: directURL),
           let image = UIImage(data: data) {
            return image
        }

        if let directURL = Bundle.main.url(forResource: "sasuke", withExtension: "jpg"),
           let data = try? Data(contentsOf: directURL),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(systemName: "person.fill") ?? UIImage()
    }

    private func battleHUD(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatBarView(
                    title: "Player HP",
                    value: battleViewModel.playerHP,
                    maxValue: 100,
                    color: .green,
                    width: max(120, size.width * 0.30)
                )

                StatBarView(
                    title: "Sasuke HP",
                    value: battleViewModel.sasukeHP,
                    maxValue: battleViewModel.sasukeHPMax,
                    color: .red,
                    width: max(120, size.width * 0.30)
                )
            }

            StatBarView(
                title: "Chakra",
                value: battleViewModel.chakra,
                maxValue: 100,
                color: .blue,
                width: max(220, size.width * 0.64)
            )

            Text("State: \(battleViewModel.state.rawValue) | Round \(battleViewModel.round) | Timer \(Int(ceil(battleViewModel.phaseTimeRemaining)))s")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.44))
                .clipShape(Capsule())

            if battleViewModel.state == .playerDefend {
                Text("Follow the counter hand signs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.42))
                    .clipShape(Capsule())
            }

            Text(battleViewModel.feedbackText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.42))
                .clipShape(Capsule())

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var projectileLayer: some View {
        ZStack {
            ForEach(battleViewModel.enemyProjectiles) { projectile in
                enemyProjectileView(projectile)
                    .position(projectile.position)
            }

            ForEach(battleViewModel.projectiles) { projectile in
                Circle()
                    .fill(projectileColor(for: projectile.jutsu))
                    .frame(width: projectile.radius * 2, height: projectile.radius * 2)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.82), lineWidth: 2)
                    )
                    .position(projectile.position)
                    .shadow(color: projectileColor(for: projectile.jutsu).opacity(0.6), radius: 14, x: 0, y: 0)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func enemyProjectileView(_ projectile: BattleModeViewModel.EnemyProjectile) -> some View {
        switch projectile.jutsu {
        case .fireball:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.orange.opacity(0.92), Color.red.opacity(0.82)],
                        center: .center,
                        startRadius: 1,
                        endRadius: projectile.radius
                    )
                )
                .frame(width: projectile.radius * 2, height: projectile.radius * 2)
                .shadow(color: .orange.opacity(0.75), radius: 16, x: 0, y: 0)

        case .burningAsh:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.62), Color.gray.opacity(0.72), Color.orange.opacity(0.34)],
                        center: .center,
                        startRadius: 0,
                        endRadius: projectile.radius
                    )
                )
                .frame(width: projectile.radius * 2, height: projectile.radius * 2)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .gray.opacity(0.42), radius: 10, x: 0, y: 0)

        case .lightning:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.72, green: 0.90, blue: 1.0), Color.blue.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: projectile.radius * 3.2, height: max(4, projectile.radius * 1.1))
                .rotationEffect(.radians(Double(atan2(projectile.velocity.dy, projectile.velocity.dx))))
                .shadow(color: Color(red: 0.62, green: 0.84, blue: 1.0).opacity(0.82), radius: 12, x: 0, y: 0)

        default:
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: projectile.radius * 2, height: projectile.radius * 2)
        }
    }

    private var floatingFeedbackLayer: some View {
        ZStack {
            ForEach(battleViewModel.floatingFeedbacks) { item in
                Text(item.text)
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color(hex: item.colorHex))
                    .position(item.position)
                    .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
            }
        }
        .allowsHitTesting(false)
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Game Over")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)

                Text(battleViewModel.feedbackText)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button {
                        battleViewModel.startBattle()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.78))
                            .clipShape(Capsule())
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(18)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func projectileColor(for jutsu: JutsuType) -> Color {
        switch jutsu {
        case .rasengan:
            return Color(red: 0.70, green: 0.92, blue: 1.0)
        case .wind:
            return Color(red: 0.88, green: 0.98, blue: 1.0)
        case .lightning:
            return Color(red: 0.70, green: 0.82, blue: 1.0)
        case .fireball, .burningAsh, .fire:
            return Color(red: 1.0, green: 0.62, blue: 0.34)
        case .waterDragon:
            return Color(red: 0.58, green: 0.86, blue: 1.0)
        case .kuchiyose:
            return Color(red: 0.90, green: 0.90, blue: 0.90)
        }
    }
}

private struct StatBarView: View {
    let title: String
    let value: Int
    let maxValue: Int
    let color: Color
    let width: CGFloat

    private var fraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(max(0, min(1, Double(value) / Double(maxValue))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(value)/\(maxValue)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(color).frame(width: width * fraction)
            }
            .frame(width: width, height: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    BattleGameView(config: GameConfig(mode: .battle, selectedJutsu: nil, initialSasukeHP: 120))
}
