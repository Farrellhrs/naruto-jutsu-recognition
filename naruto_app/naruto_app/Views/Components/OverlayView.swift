import SwiftUI
import UIKit

struct OverlayView: View {
    let targetJutsu: JutsuType?
    let activeJutsu: JutsuType?
    let sequenceProgressCount: Int
    let showGuidance: Bool

    private var guideJutsu: JutsuType? {
        targetJutsu ?? activeJutsu
    }

    private var guideSequence: [String] {
        guideJutsu?.signSequence ?? []
    }

    private var currentGuideIndex: Int {
        guard !guideSequence.isEmpty else { return 0 }
        return min(max(0, sequenceProgressCount), max(0, guideSequence.count - 1))
    }

    private var currentGuideSign: String? {
        guard !guideSequence.isEmpty else { return nil }
        return guideSequence[currentGuideIndex]
    }

    private var hasCompletedSequence: Bool {
        !guideSequence.isEmpty && sequenceProgressCount >= guideSequence.count
    }

    private var showWindThrowNote: Bool {
        guideJutsu == .wind || activeJutsu == .wind
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if let guideJutsu {
                    VStack(spacing: 4) {
                        Text(guideJutsu.title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)

                        Text(guideJutsu.originContext)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.top, 16)
                    .shadow(color: .black.opacity(0.65), radius: 7, x: 0, y: 2)
                }

                Spacer()

                if showGuidance, let currentGuideSign {
                    VStack(spacing: 10) {

                        if !guideSequence.isEmpty {
                            sequenceStripView
                        }

                        HandsignGuideImage(sign: currentGuideSign)
                            .frame(width: 220, height: 220)
                            .opacity(0.64)
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)

                        Text(hasCompletedSequence ? "Perform the jutsu" : "Follow this hand sign")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)

                        Text("Hold the sign briefly")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                    }
                    .padding(.bottom, 18)
                }
            }

            if showWindThrowNote {
                Text("Wind Style tip: Flick your hand fast to throw")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.46))
                    .clipShape(Capsule())
                    .padding(.top, 14)
                    .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .allowsHitTesting(false)
    }

    private var sequenceStripView: some View {
        HStack(spacing: 6) {
            ForEach(Array(guideSequence.enumerated()), id: \.offset) { index, sign in
                let reached = index < sequenceProgressCount
                let current = index == currentGuideIndex && !hasCompletedSequence

                HStack(spacing: 4) {
                    Text(sign.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(current ? Color.blue.opacity(0.62) : (reached ? Color.orange.opacity(0.58) : Color.black.opacity(0.34)))
                .clipShape(Capsule())

                if index < guideSequence.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
}

private struct HandsignGuideImage: View {
    let sign: String

    var body: some View {
        if let uiImage = HandsignGuideImageResolver.image(for: sign) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                )
        }
    }
}

private enum HandsignGuideImageResolver {
    static func image(for sign: String) -> UIImage? {
        let fileBaseName = normalizedAssetName(for: sign)

        if let image = image(named: fileBaseName, ext: "webp") {
            return image
        }
        if let image = image(named: fileBaseName, ext: "png") {
            return image
        }
        return nil
    }

    private static func normalizedAssetName(for sign: String) -> String {
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

    private static func image(named name: String, ext: String) -> UIImage? {
        if let directURL = Bundle.main.url(forResource: name, withExtension: ext),
           let data = try? Data(contentsOf: directURL),
           let image = UIImage(data: data) {
            return image
        }

        if let folderURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "handsign_image"),
           let data = try? Data(contentsOf: folderURL),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(named: name)
    }
}
