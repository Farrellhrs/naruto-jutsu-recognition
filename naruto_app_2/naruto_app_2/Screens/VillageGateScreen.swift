import SwiftUI

/// Home: an ink-and-scroll themed gate into the three practice halls.
struct VillageGateScreen: View {
    enum Hall: String, CaseIterable, Identifiable {
        case dojo, academy, trials

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dojo: return "Dojo"
            case .academy: return "Academy"
            case .trials: return "Trials"
            }
        }

        var blurb: String {
            switch self {
            case .dojo: return "Free practice — weave any sequence and unleash every jutsu"
            case .academy: return "Master all twelve hand seals, one at a time"
            case .trials: return "Timed jutsu challenges. Chase the S rank"
            }
        }

        var symbol: String {
            switch self {
            case .dojo: return "flame.fill"
            case .academy: return "graduationcap.fill"
            case .trials: return "stopwatch.fill"
            }
        }

        var accent: Color {
            switch self {
            case .dojo: return Ink.crimson
            case .academy: return Ink.chakra
            case .trials: return Ink.gold
            }
        }
    }

    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ZStack {
                gateBackground

                VStack(spacing: 26) {
                    Spacer(minLength: 20)

                    VStack(spacing: 8) {
                        Image(systemName: "hands.and.sparkles.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Ink.crimson)
                            .shadow(color: Ink.crimson.opacity(0.8), radius: 14)

                        BrushTitle(text: "Sign Weaver")

                        Text("十二印 — twelve seals, eight jutsu")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Ink.faded)
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : -16)

                    VStack(spacing: 14) {
                        ForEach(Array(Hall.allCases.enumerated()), id: \.element) { index, hall in
                            NavigationLink(value: hall) {
                                hallCard(hall)
                            }
                            .buttonStyle(.plain)
                            .opacity(revealed ? 1 : 0)
                            .offset(x: revealed ? 0 : (index.isMultiple(of: 2) ? -40 : 40))
                            .animation(
                                .spring(response: 0.55, dampingFraction: 0.8).delay(0.1 + Double(index) * 0.08),
                                value: revealed
                            )
                        }
                    }
                    .padding(.horizontal, 22)

                    Spacer()

                    Text("On-device hand-sign recognition · no network needed")
                        .font(.caption2)
                        .foregroundStyle(Ink.faded.opacity(0.7))
                        .padding(.bottom, 14)
                }
            }
            .navigationDestination(for: Hall.self) { hall in
                switch hall {
                case .dojo: DojoScreen()
                case .academy: AcademyScreen()
                case .trials: TrialsScreen()
                }
            }
        }
        .tint(Ink.gold)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                revealed = true
            }
        }
    }

    private func hallCard(_ hall: Hall) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(hall.accent.opacity(0.22))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(hall.accent, lineWidth: 1.5)
                Image(systemName: hall.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(hall.accent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(hall.title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Text(hall.blurb)
                    .font(.caption)
                    .foregroundStyle(Ink.faded)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Ink.faded.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Ink.paperHigh.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(hall.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var gateBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Ink.paper, Color(red: 0.14, green: 0.05, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Falling ink petals.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for i in 0..<10 {
                        let seed = Double(i)
                        let fall = 20.0 + seed.truncatingRemainder(dividingBy: 4) * 9
                        let x = size.width * (0.05 + (seed * 0.11).truncatingRemainder(dividingBy: 0.9))
                            + sin(t * 0.6 + seed * 2) * 26
                        let y = ((t * fall + seed * 131).truncatingRemainder(dividingBy: size.height + 40)) - 20
                        var petal = Path(ellipseIn: CGRect(x: x, y: y, width: 7, height: 4))
                        petal = petal.applying(CGAffineTransform(rotationAngle: sin(t + seed) * 0.9))
                        context.fill(petal, with: .color(Ink.crimson.opacity(0.35)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    VillageGateScreen()
}
