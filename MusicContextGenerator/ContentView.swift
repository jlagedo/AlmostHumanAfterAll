import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .imageScale(.large)
                .font(.largeTitle)
            Text("MusicContextGenerator")
                .font(.headline)
            Text("Run from the command line with arguments.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(40)
    }
}
