import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Ficino")
                    .font(.headline)

                Spacer()

                // Regenerate
                Button {
                    appState.regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(appState.currentTrack == nil || appState.isLoading)
                .help("Regenerate commentary")

                // Pause toggle
                Button {
                    appState.preferences.isPaused.toggle()
                } label: {
                    Image(systemName: appState.preferences.isPaused ? "pause.circle.fill" : "pause.circle")
                        .font(.body)
                        .foregroundStyle(appState.preferences.isPaused ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(appState.preferences.isPaused ? "Resume" : "Pause")

                // Settings gear
                Button {
                    appState.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Now Playing
            NowPlayingView()
                .padding(16)

            Divider()

            // History
            HistoryView()

            Divider()

            // Footer
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                    appState.openSettings()
                    return nil
                }
                return event
            }
        }
        .task {
            appState.startIfNeeded()
        }
    }
}
