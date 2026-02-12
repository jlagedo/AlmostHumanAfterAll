import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let setupError = appState.setupError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(setupError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Setup error: \(setupError)")
        } else if let track = appState.currentTrack {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                Group {
                    if let artwork = appState.currentArtwork {
                        Image(nsImage: artwork)
                            .resizable()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Album artwork for \(track.album)")

                // Track info + comment
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        Text("\(track.artist) — \(track.album)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Group {
                        if appState.isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.opacity)
                            .accessibilityLabel("Loading commentary")
                        } else if let comment = appState.currentComment {
                            ScrollView {
                                Text(comment)
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxHeight: 150)
                            .transition(.opacity)
                        } else if let error = appState.errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                                .transition(.opacity)
                                .accessibilityLabel("Error: \(error)")
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: appState.isLoading)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(track.name) by \(track.artist)")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Play something in Apple Music")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityLabel("No track playing. Play something in Apple Music to get started.")
        }
    }
}
