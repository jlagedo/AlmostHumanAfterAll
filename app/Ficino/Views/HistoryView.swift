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
                Group {
                    if let thumbnail = entry.thumbnailImage {
                        Image(nsImage: thumbnail)
                            .resizable()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.track.name)
                        .font(.system(.body, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(entry.comment)
                .font(.callout)
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
        .accessibilityLabel("\(entry.track.name) by \(entry.track.artist): \(entry.comment)")
    }
}
