import SwiftUI

struct ModeSetupView: View {
    let mode: AppMode
    let onStart: (GameConfig) -> Void

    @State private var speedTarget: JutsuType = JutsuType.allCases.randomElement() ?? .fire
    @State private var tutorialSummon: SummonAnimal = .kyuubi
    @State private var battleEnemyHP: Double = 120

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.10, green: 0.10, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Label(mode.title, systemImage: mode.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                switch mode {
                case .battle:
                    battleContent
                case .tutorial:
                    tutorialContent
                case .free:
                    freeContent
                case .speed:
                    speedContent
                }
            }
            .padding(20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tutorialContent: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summon Animal")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SummonAnimal.allCases, id: \.self) { animal in
                            Button {
                                tutorialSummon = animal
                            } label: {
                                Text(animal.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(animal == tutorialSummon ? Color.orange.opacity(0.78) : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(JutsuType.allCases, id: \.self) { jutsu in
                    Button {
                        onStart(GameConfig(mode: .tutorial, selectedJutsu: jutsu, selectedSummon: tutorialSummon))
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: jutsu.icon)
                                .font(.system(size: 30, weight: .bold))
                            Text(jutsu.title)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var freeContent: some View {
        Button {
            onStart(GameConfig(mode: .free, selectedJutsu: nil))
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42, weight: .bold))
                Text("Start")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Color.orange.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .foregroundStyle(.white)
    }

    private var speedContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: speedTarget.icon)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.orange)
                Text(speedTarget.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button {
                    speedTarget = JutsuType.allCases.randomElement() ?? .fire
                } label: {
                    Image(systemName: "shuffle")
                        .padding(12)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                }

                Button {
                    onStart(GameConfig(mode: .speed, selectedJutsu: speedTarget))
                } label: {
                    Label("Start", systemImage: "timer")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.75))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var battleContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.orange)
                Text("Sasuke Initial HP")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(Int(battleEnemyHP))")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 8) {
                Slider(value: $battleEnemyHP, in: 80...220, step: 5)
                    .tint(.orange)
                HStack {
                    Text("80")
                    Spacer()
                    Text("220")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            }

            Button {
                onStart(GameConfig(mode: .battle, selectedJutsu: nil, initialSasukeHP: Int(battleEnemyHP)))
            } label: {
                Label("Start Battle", systemImage: "shield.fill")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.75))
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    ModeSetupView(mode: .tutorial) { _ in }
}
