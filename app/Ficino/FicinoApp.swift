import SwiftUI
import TipKit

@main
struct FicinoApp: App {
    @StateObject private var appState = AppState()

    init() {
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 380, height: 540)
        } label: {
            Label("Ficino", systemImage: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
