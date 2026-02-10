import SwiftUI

@main
struct AlmostHumanAfterAllApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 380, height: 400)
        } label: {
            Label("AlmostHumanAfterAll", systemImage: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
