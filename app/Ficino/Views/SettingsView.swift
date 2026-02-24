import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show Notifications", isOn: $appState.preferences.notificationsEnabled)

                HStack {
                    Slider(
                        value: $appState.preferences.notificationDuration,
                        in: 3...30,
                        step: 1
                    )
                    .accessibilityLabel("Notification duration")
                    .accessibilityValue("\(Int(appState.preferences.notificationDuration)) seconds")

                    Text("\(Int(appState.preferences.notificationDuration))s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Picker("Position", selection: $appState.preferences.notificationPosition) {
                    Text("Top Right").tag(NotificationPosition.topRight)
                    Text("Top Left").tag(NotificationPosition.topLeft)
                    Text("Bottom Right").tag(NotificationPosition.bottomRight)
                    Text("Bottom Left").tag(NotificationPosition.bottomLeft)
                }
            }

            Section("Last.fm") {
                if let username = appState.preferences.lastFmUsername {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected as")
                        Link(username, destination: URL(string: "https://www.last.fm/user/\(username)")!)
                    }

                    Toggle("Scrobbling", isOn: $appState.preferences.lastFmEnabled)

                    Button("Disconnect") {
                        appState.disconnectLastFm()
                    }
                    .foregroundStyle(.red)
                } else {
                    Button("Connect to Last.fm") {
                        appState.connectLastFm()
                    }

                    if appState.lastFmAuthInProgress {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for authorization...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = appState.lastFmAuthError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Playback") {
                HStack {
                    Slider(
                        value: $appState.preferences.skipThreshold,
                        in: 0...30,
                        step: 1
                    )
                    .accessibilityLabel("Skip threshold")
                    .accessibilityValue("\(Int(appState.preferences.skipThreshold)) seconds")

                    Text("\(Int(appState.preferences.skipThreshold))s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Text("Tracks played less than \(Int(appState.preferences.skipThreshold)) seconds are ignored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
    }
}
