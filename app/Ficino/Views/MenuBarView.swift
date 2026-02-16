import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Now Playing
            NowPlayingView()
                .padding(16)

            Divider()

            // Controls
            HStack {
                Button {
                    appState.stop()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit Ficino")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")

                Spacer()
                SettingsView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // History
            HistoryView()
        }
        .task {
            appState.startIfNeeded()
        }
    }
}
