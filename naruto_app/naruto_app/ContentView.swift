//
//  ContentView.swift
//  naruto_app
//
//  Created by Farrell Habibie Putra Haris on 26/03/26.
//

import SwiftUI

struct ContentView: View {
    @State private var path: [Route] = []

    enum Route: Hashable {
        case mode(AppMode)
        case game(GameConfig)
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView { mode in
                path.append(.mode(mode))
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .mode(let mode):
                    ModeSetupView(mode: mode) { config in
                        path.append(.game(config))
                    }
                case .game(let config):
                    if config.mode == .battle {
                        BattleGameView(config: config)
                    } else {
                        CameraGameView(config: config)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
