import SwiftUI

struct PersonalityPickerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Picker(selection: $appState.personality) {
            ForEach(Personality.allCases) { personality in
                Label(personality.rawValue, systemImage: personality.icon)
                    .tag(personality)
            }
        } label: {
            Label(appState.personality.rawValue, systemImage: appState.personality.icon)
                .font(.subheadline)
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Commentary personality")
        .accessibilityValue(appState.personality.rawValue)
        .accessibilityHint("Choose a personality for track commentary")
    }
}
