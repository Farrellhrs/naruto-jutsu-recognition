import SwiftUI

struct JutsuEffectView: View {
    let jutsu: JutsuType
    let elapsedText: String
    let showTime: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: jutsu.icon)
                .font(.system(size: 54, weight: .black))
                .foregroundStyle(.orange)
                .scaleEffect(pulse ? 1.08 : 0.92)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            Text(jutsu.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

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
                        .background(Color.orange.opacity(0.7))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { pulse = true }
    }
}
