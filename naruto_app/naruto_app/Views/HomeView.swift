import SwiftUI

struct HomeView: View {
    let onSelect: (AppMode) -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 20) {
                header
                    .padding(.top, 12)

                VStack(spacing: 12) {
                    ForEach(Array(AppMode.allCases.enumerated()), id: \.element) { index, mode in
                        ModeCard(mode: mode) {
                            Haptics.select()
                            onSelect(mode)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07),
                            value: appeared
                        )
                    }
                }

                Text("Perform hand signs in front of the camera to cast jutsu")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .orange.opacity(0.55), radius: 16)
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.spring(response: 0.55, dampingFraction: 0.65), value: appeared)

            Text("Jutsu Master")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 1.0, green: 0.82, blue: 0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.6), radius: 8, y: 3)

            Text("Master the signs. Unleash the power.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.16, green: 0.06, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Slow-drifting chakra embers.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for i in 0..<14 {
                        let seed = Double(i)
                        let speed = 12.0 + seed.truncatingRemainder(dividingBy: 5) * 6
                        let x = size.width * (0.08 + (seed * 0.073).truncatingRemainder(dividingBy: 0.86))
                            + sin(t * 0.4 + seed) * 18
                        let y = size.height - ((t * speed + seed * 97).truncatingRemainder(dividingBy: size.height + 60)) + 30
                        let radius = 2.0 + seed.truncatingRemainder(dividingBy: 3)
                        let opacity = 0.10 + 0.12 * (0.5 + 0.5 * sin(t * 0.8 + seed * 2))
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                            with: .color(Color.orange.opacity(opacity))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ModeCard: View {
    let mode: AppMode
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: accent.opacity(0.5), radius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accent.opacity(0.35), lineWidth: 1)
                    )
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { pressed = false } }
        )
    }

    private var accent: Color {
        switch mode {
        case .battle: return .red
        case .free: return .orange
        case .speed: return .yellow
        case .tutorial: return .blue
        }
    }

    private var subtitle: String {
        switch mode {
        case .battle: return "Duel Sasuke — block his jutsu, counter with your own"
        case .free: return "Sandbox: chain any signs and unleash every jutsu"
        case .speed: return "Race the clock to complete a target sequence"
        case .tutorial: return "Learn each hand sign step by step"
        }
    }
}

#Preview {
    HomeView { _ in }
}
