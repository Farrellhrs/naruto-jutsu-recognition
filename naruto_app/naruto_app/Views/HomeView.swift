import SwiftUI

struct HomeView: View {
    let onSelect: (AppMode) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.16, green: 0.06, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)

                Text("Jutsu Master")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Button {
                            onSelect(mode)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 28, weight: .bold))
                                Text(mode.title)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

#Preview {
    HomeView { _ in }
}
