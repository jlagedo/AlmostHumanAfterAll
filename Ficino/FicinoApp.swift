import SwiftUI

@main
struct FicinoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 380, height: 400)
        } label: {
            Label("Ficino", systemImage: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
