import SwiftUI

struct SettingsPopoverContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show notifications toggle
            Toggle(isOn: $appState.preferences.notificationsEnabled) {
                Text("Show Notifications")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            // Notification duration
            VStack(alignment: .leading, spacing: 4) {
                Text("Notification Duration")
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Slider(
                        value: $appState.preferences.notificationDuration,
                        in: 3...30,
                        step: 1
                    )
                    .frame(width: 150)
                    .accessibilityLabel("Notification duration")
                    .accessibilityValue("\(Int(appState.preferences.notificationDuration)) seconds")
                    .accessibilityHint("How long the floating comment stays on screen")

                    Text("\(Int(appState.preferences.notificationDuration))s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Text("How long the floating comment stays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Notification position
            VStack(alignment: .leading, spacing: 4) {
                Text("Notification Position")
                    .font(.caption)
                    .fontWeight(.medium)

                Picker("Position", selection: $appState.preferences.notificationPosition) {
                    Text("Top Right").tag(NotificationPosition.topRight)
                    Text("Top Left").tag(NotificationPosition.topLeft)
                    Text("Bottom Right").tag(NotificationPosition.bottomRight)
                    Text("Bottom Left").tag(NotificationPosition.bottomLeft)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Divider()

            // Skip threshold
            VStack(alignment: .leading, spacing: 4) {
                Text("Skip Threshold")
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Slider(
                        value: $appState.preferences.skipThreshold,
                        in: 0...30,
                        step: 1
                    )
                    .frame(width: 150)
                    .accessibilityLabel("Skip threshold")
                    .accessibilityValue("\(Int(appState.preferences.skipThreshold)) seconds")
                    .accessibilityHint("Tracks played less than this duration are ignored")

                    Text("\(Int(appState.preferences.skipThreshold))s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Text("Ignore tracks played less than this")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(12)
        .frame(width: 250)
    }
}
