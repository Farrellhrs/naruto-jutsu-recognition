import SwiftUI

/// Anime-style jutsu name callout that slams in when a jutsu triggers.
struct JutsuCastBanner: View {
    let jutsu: JutsuType
    var compact = false

    @State private var appeared = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            Image(systemName: jutsu.icon)
                .font(compact ? .subheadline.weight(.black) : .title3.weight(.black))
            Text(jutsu.title)
                .font(compact ? .subheadline.weight(.black) : .title3.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 6 : 10)
        .background(
            Capsule()
                .fill(accent.opacity(0.85))
                .shadow(color: accent.opacity(0.9), radius: appeared ? 18 : 4)
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
        .scaleEffect(appeared ? 1.0 : 1.6)
        .opacity(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : -6))
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }

    private var accent: Color {
        switch jutsu {
        case .fireball, .fire, .burningAsh:
            return Color(red: 0.95, green: 0.42, blue: 0.12)
        case .lightning:
            return Color(red: 0.30, green: 0.52, blue: 0.95)
        case .rasengan, .wind:
            return Color(red: 0.16, green: 0.62, blue: 0.85)
        case .waterDragon:
            return Color(red: 0.12, green: 0.45, blue: 0.85)
        case .kuchiyose:
            return Color(red: 0.72, green: 0.5, blue: 0.2)
        }
    }
}
