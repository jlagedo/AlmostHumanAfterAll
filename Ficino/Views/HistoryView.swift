import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.history.isEmpty {
            VStack(spacing: 4) {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.history) { entry in
                        HistoryEntryView(entry: entry)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

struct HistoryEntryView: View {
    let entry: CommentEntry
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if entry.isReview {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(width: 24, height: 24)
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("5-Song Review")
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)
                        Text(entry.personality.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if let track = entry.track {
                    if let thumbnail = entry.thumbnailImage {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: entry.personality.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.comment)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(5)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? .tertiary : .quaternary)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Copy Comment") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.comment, forType: .string)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isReview
            ? "5-Song Review. \(entry.personality.rawValue) said: \(entry.comment)"
            : "\(entry.track?.name ?? "") by \(entry.track?.artist ?? ""). \(entry.personality.rawValue) said: \(entry.comment)")
    }
}
