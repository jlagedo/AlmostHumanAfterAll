import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 8) {
            // Pause toggle
            Button {
                appState.isPaused.toggle()
            } label: {
                Image(systemName: appState.isPaused ? "pause.circle.fill" : "pause.circle")
                    .font(.body)
                    .foregroundStyle(appState.isPaused ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.isPaused ? "Resume" : "Pause")
            .accessibilityLabel(appState.isPaused ? "Resume commentary" : "Pause commentary")
            .accessibilityHint("Toggles whether the app comments on track changes")

            // Settings popover
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    // Notification duration
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Duration")
                            .font(.caption)
                            .fontWeight(.medium)

                        HStack {
                            Slider(
                                value: $appState.notificationDuration,
                                in: 3...30,
                                step: 1
                            )
                            .frame(width: 120)
                            .accessibilityLabel("Notification duration")
                            .accessibilityValue("\(Int(appState.notificationDuration)) seconds")
                            .accessibilityHint("How long the floating comment stays on screen")

                            Text("\(Int(appState.notificationDuration))s")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 30, alignment: .trailing)
                        }

                        Text("How long the floating comment stays")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Skip threshold
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skip Threshold")
                            .font(.caption)
                            .fontWeight(.medium)

                        HStack {
                            Slider(
                                value: $appState.skipThreshold,
                                in: 0...30,
                                step: 1
                            )
                            .frame(width: 120)
                            .accessibilityLabel("Skip threshold")
                            .accessibilityValue("\(Int(appState.skipThreshold)) seconds")
                            .accessibilityHint("Tracks played less than this duration are ignored")

                            Text("\(Int(appState.skipThreshold))s")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 30, alignment: .trailing)
                        }

                        Text("Ignore tracks played less than this")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Model picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Claude Model")
                            .font(.caption)
                            .fontWeight(.medium)

                        Picker("", selection: $appState.claudeModel) {
                            Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                            Text("Sonnet 4.5").tag("claude-sonnet-4-5-20250929")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Claude model")

                        Text("Haiku is faster, Sonnet is more expressive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Button {
                        appState.stop()
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit AlmostHumanAfterAll")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(width: 220)
            }
        }
    }
}
