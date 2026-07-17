import SwiftUI

struct JutsuEffectView: View {
    let jutsu: JutsuType
    let elapsedText: String
    let showTime: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .stroke(accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: jutsu.icon)
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.8), radius: 12)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            }
            .frame(height: 120)

            Text(jutsu.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if showTime {
                Label(elapsedText, systemImage: "timer")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Capsule())
                }

                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.7))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accent.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            pulse = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private var accent: Color {
        switch jutsu {
        case .fireball, .fire, .burningAsh:
            return .orange
        case .lightning:
            return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .rasengan, .wind:
            return Color(red: 0.45, green: 0.85, blue: 1.0)
        case .waterDragon:
            return Color(red: 0.35, green: 0.7, blue: 1.0)
        case .kuchiyose:
            return Color(red: 0.9, green: 0.75, blue: 0.5)
        }
    }
}
