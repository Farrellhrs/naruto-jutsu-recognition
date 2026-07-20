import Combine
import SwiftUI

/// Timed challenges: pick a jutsu, weave its full sequence as fast as you can.
struct TrialsScreen: View {
    @State private var activeTrial: Jutsu?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.paper, Color(red: 0.12, green: 0.09, blue: 0.03)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Jutsu.allCases) { jutsu in
                        Button {
                            activeTrial = jutsu
                        } label: {
                            trialRow(jutsu)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Trials")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeTrial) { jutsu in
            TrialRunScreen(jutsu: jutsu) {
                activeTrial = nil
            }
        }
    }

    private func trialRow(_ jutsu: Jutsu) -> some View {
        let best = TrialRecords.best(for: jutsu)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(jutsu.nature.color.opacity(0.2))
                Circle().stroke(jutsu.nature.color, lineWidth: 1.4)
                Text(jutsu.rank)
                    .font(.headline.weight(.black))
                    .foregroundStyle(jutsu.nature.color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(jutsu.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(jutsu.sequence.count) seals · \(jutsu.sequence.map(\.displayName).joined(separator: " → "))")
                    .font(.caption2)
                    .foregroundStyle(Ink.faded)
                    .lineLimit(2)
            }

            Spacer()

            if let best {
                VStack(spacing: 2) {
                    Text(String(format: "%.2fs", best))
                        .font(.caption.weight(.black))
                        .foregroundStyle(Ink.gold)
                    Text(TrialRecords.grade(for: jutsu, time: best))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Ink.gold.opacity(0.8))
                }
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Ink.faded)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Ink.paperHigh.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(jutsu.nature.color.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Records

enum TrialRecords {
    static func best(for jutsu: Jutsu) -> Double? {
        let value = UserDefaults.standard.double(forKey: "trial.best.\(jutsu.rawValue)")
        return value > 0 ? value : nil
    }

    static func record(_ time: Double, for jutsu: Jutsu) -> Bool {
        let key = "trial.best.\(jutsu.rawValue)"
        let previous = UserDefaults.standard.double(forKey: key)
        if previous == 0 || time < previous {
            UserDefaults.standard.set(time, forKey: key)
            return true
        }
        return false
    }

    /// Par: ~1.6s per seal for S, scaling down.
    static func grade(for jutsu: Jutsu, time: Double) -> String {
        let perSeal = time / Double(jutsu.sequence.count)
        switch perSeal {
        case ..<1.6: return "S"
        case ..<2.4: return "A"
        case ..<3.4: return "B"
        default: return "C"
        }
    }
}

// MARK: - Trial run

private struct TrialRunScreen: View {
    let jutsu: Jutsu
    let onClose: () -> Void

    @State private var session = ShinobiSession()
    @State private var startedAt: Date?
    @State private var finishTime: Double?
    @State private var isNewBest = false
    @State private var countdown = 3

    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraSurface(session: session.session)
                .ignoresSafeArea()

            HandConstellation(hands: session.overlayHands)
                .ignoresSafeArea()

            JutsuEffectsView(castID: session.castCount, jutsu: session.lastCast)
                .ignoresSafeArea()

            if countdown > 0 {
                Text("\(countdown)")
                    .font(.system(size: 110, weight: .black, design: .serif))
                    .foregroundStyle(Ink.gold)
                    .shadow(color: Ink.gold.opacity(0.8), radius: 24)
                    .transition(.scale)
            } else if let finishTime {
                resultCard(finishTime)
            } else {
                runningHUD
            }

            VStack {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onReceive(ticker) { _ in
            guard countdown > 0 else { return }
            countdown -= 1
            if countdown == 0 {
                session.resetSequence()
                startedAt = Date()
            }
        }
        .onChange(of: session.castCount) { _, _ in
            guard finishTime == nil, session.lastCast == jutsu, let startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            finishTime = elapsed
            isNewBest = TrialRecords.record(elapsed, for: jutsu)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var runningHUD: some View {
        VStack {
            VStack(spacing: 8) {
                Text(jutsu.name)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)

                // Live progress against the target sequence.
                HStack(spacing: 6) {
                    let done = matchedPrefixCount
                    ForEach(Array(jutsu.sequence.enumerated()), id: \.offset) { index, sign in
                        SignChip(sign: sign, highlighted: index < done)
                            .opacity(index < done ? 1 : 0.55)
                    }
                }
            }
            .padding(.top, 20)
            .shadow(color: .black, radius: 6)

            Spacer()

            HStack {
                HoldRing(sign: session.currentSign, progress: session.holdProgress)
                Spacer()
                if let startedAt {
                    TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                        Text(String(format: "%.1fs", timeline.date.timeIntervalSince(startedAt)))
                            .font(.system(.title2, design: .monospaced).weight(.black))
                            .foregroundStyle(Ink.gold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var matchedPrefixCount: Int {
        let history = session.recentSigns
        var best = 0
        for length in stride(from: min(history.count, jutsu.sequence.count), through: 1, by: -1) {
            if Array(history.suffix(length)) == Array(jutsu.sequence.prefix(length)) {
                best = length
                break
            }
        }
        return best
    }

    private func resultCard(_ time: Double) -> some View {
        VStack(spacing: 12) {
            Text(TrialRecords.grade(for: jutsu, time: time))
                .font(.system(size: 76, weight: .black, design: .serif))
                .foregroundStyle(Ink.gold)
                .shadow(color: Ink.gold.opacity(0.8), radius: 20)

            Text(String(format: "%.2f seconds", time))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            if isNewBest {
                Label("New record", systemImage: "crown.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Ink.gold)
            }

            HStack(spacing: 12) {
                Button {
                    finishTime = nil
                    countdown = 3
                    session.resetSequence()
                } label: {
                    Label("Again", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Ink.gold)
                        .foregroundStyle(Ink.paper)
                        .clipShape(Capsule())
                }

                Button {
                    onClose()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .font(.headline)
        }
        .padding(26)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
