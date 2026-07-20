import SwiftUI

/// Free practice: camera, chakra constellation, sign trail, live effects.
struct DojoScreen: View {
    @State private var session = ShinobiSession()
    @State private var calloutJutsu: Jutsu?
    @State private var calloutTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraSurface(session: session.session)
                .ignoresSafeArea()

            HandConstellation(hands: session.overlayHands, videoSize: session.videoFrameSize)
                .ignoresSafeArea()

            JutsuEffectsView(castID: session.castCount, jutsu: session.lastCast)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            overlayHUD

            if let calloutJutsu {
                VStack {
                    CastCallout(jutsu: calloutJutsu)
                        .padding(.top, 70)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if !session.cameraReady {
                Label("Starting camera…", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
        .navigationTitle("Dojo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.castCount) { _, _ in
            guard let cast = session.lastCast else { return }
            presentCallout(cast)
        }
    }

    private var overlayHUD: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 14) {
                HoldRing(sign: session.currentSign, progress: session.holdProgress)

                VStack(alignment: .leading, spacing: 8) {
                    if session.recentSigns.isEmpty {
                        Text("Weave hand signs to cast jutsu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.faded)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(Array(session.recentSigns.enumerated()), id: \.offset) { pair in
                                SignChip(sign: pair.element, highlighted: pair.offset == session.recentSigns.count - 1)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(session.castCount)", systemImage: "sparkles")
                        Label("\(session.commitCount)", systemImage: "hand.raised.fill")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Ink.faded)
                }
                .padding(12)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func presentCallout(_ jutsu: Jutsu) {
        calloutTask?.cancel()
        calloutJutsu = jutsu
        calloutTask = Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                calloutJutsu = nil
            }
        }
    }
}

#Preview {
    NavigationStack { DojoScreen() }
}
