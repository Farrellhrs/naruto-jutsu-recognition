import Combine
import SwiftUI

/// Sign school: master each of the twelve seals with live camera feedback.
/// Progress persists across launches.
struct AcademyScreen: View {
    @AppStorage("academy.mastered") private var masteredRaw = ""
    @State private var selectedSign: HandSign?

    private var mastered: Set<HandSign> {
        Set(masteredRaw.split(separator: ",").compactMap { HandSign(rawValue: String($0)) })
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.paper, Color(red: 0.05, green: 0.09, blue: 0.13)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    progressHeader

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(HandSign.allCases) { sign in
                            Button {
                                selectedSign = sign
                            } label: {
                                signTile(sign)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Academy")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedSign) { sign in
            SignPracticeScreen(sign: sign) { didMaster in
                if didMaster {
                    markMastered(sign)
                }
                selectedSign = nil
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text("\(mastered.count) / \(HandSign.allCases.count) seals mastered")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)

            ProgressView(value: Double(mastered.count), total: Double(HandSign.allCases.count))
                .tint(Ink.chakra)
                .padding(.horizontal, 40)

            if mastered.count == HandSign.allCases.count {
                Label("All twelve seals — true shinobi", systemImage: "crown.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ink.gold)
            }
        }
        .padding(.top, 8)
    }

    private func signTile(_ sign: HandSign) -> some View {
        let isMastered = mastered.contains(sign)
        return VStack(spacing: 8) {
            Image(systemName: isMastered ? "checkmark.seal.fill" : sign.glyph)
                .font(.title2.weight(.bold))
                .foregroundStyle(isMastered ? Ink.gold : Ink.chakra)

            Text(sign.displayName)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Ink.paperHigh.opacity(isMastered ? 1 : 0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isMastered ? Ink.gold.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1.2)
                )
        )
    }

    private func markMastered(_ sign: HandSign) {
        var set = mastered
        set.insert(sign)
        masteredRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }
}

// MARK: - Single-sign practice

private struct SignPracticeScreen: View {
    let sign: HandSign
    let onFinish: (Bool) -> Void

    @State private var session = ShinobiSession()
    @State private var matchTime: Double = 0
    @State private var completed = false

    private let requiredMatchTime = 1.5
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraSurface(feed: session.feed)
                .ignoresSafeArea()

            HandConstellation(hands: session.overlayHands, videoSize: session.videoFrameSize, fillsCanvas: session.feed.usesFillGravity)
                .ignoresSafeArea()

            VStack {
                VStack(spacing: 8) {
                    Text(sign.displayName)
                        .font(.system(size: 34, weight: .black, design: .serif))
                        .foregroundStyle(.white)

                    Text(sign.howTo)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }
                .padding(.top, 24)
                .shadow(color: .black, radius: 6)

                Spacer()

                if completed {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Ink.gold)
                            .shadow(color: Ink.gold, radius: 18)
                        Text("Mastered!")
                            .font(.title.weight(.black))
                            .foregroundStyle(.white)
                        Button {
                            onFinish(true)
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 12)
                                .background(Ink.gold)
                                .foregroundStyle(Ink.paper)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 60)
                } else {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: matchTime / requiredMatchTime)
                                .stroke(Ink.chakra, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.1), value: matchTime)
                            Text(isMatching ? "Hold it…" : "Show the seal")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 110, height: 110)
                        .background(Circle().fill(Color.black.opacity(0.45)))

                        if let current = session.currentSign, current != sign {
                            Text("Seeing: \(current.displayName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.crimson)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 46)
                }
            }

            VStack {
                HStack {
                    Button {
                        onFinish(false)
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
            guard !completed else { return }
            if isMatching {
                matchTime += 0.1
                if matchTime >= requiredMatchTime {
                    completed = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } else {
                matchTime = max(0, matchTime - 0.2)
            }
        }
    }

    private var isMatching: Bool {
        session.currentSign == sign
    }
}
