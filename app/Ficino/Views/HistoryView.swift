import SwiftUI
import TipKit
import FicinoCore

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFavoritesOnly = false
    private let historyTip = HistoryInteractionTip()

    private var filteredHistory: [CommentaryRecord] {
        showFavoritesOnly ? appState.history.filter(\.isFavorited) : appState.history
    }

    var body: some View {
        if appState.history.isEmpty {
            VStack(spacing: 4) {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Filter bar
                HStack {
                    Text(showFavoritesOnly ? "Favorites" : "History")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showFavoritesOnly.toggle()
                    } label: {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(showFavoritesOnly ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showFavoritesOnly ? "Show all" : "Show favorites")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                if filteredHistory.isEmpty {
                    VStack(spacing: 4) {
                        Text("No favorites yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredHistory) { entry in
                                HistoryEntryView(
                                    entry: entry,
                                    tip: entry.id == filteredHistory.first?.id ? historyTip : nil
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

struct HistoryEntryView: View {
    let entry: CommentaryRecord
    var tip: HistoryInteractionTip? = nil
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Thumbnail
                Group {
                    if let thumbnail = entry.thumbnailImage {
                        Image(nsImage: thumbnail)
                            .resizable()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.trackName)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Hover action icons
                HStack(spacing: 4) {
                    // Favorite
                    Button {
                        appState.toggleFavorite(id: entry.id)
                    } label: {
                        Image(systemName: entry.isFavorited ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(entry.isFavorited ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(entry.isFavorited ? "Unfavorite" : "Favorite")

                    // Copy
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.commentary, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy commentary")

                    // Apple Music link
                    if let url = entry.appleMusicURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open in Apple Music")
                    }
                }
                .opacity(isHovered ? 1 : 0)
                .accessibilityHidden(false)

                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: 0.3, bounce: 0.1), value: isExpanded)
            }

            Text(entry.commentary)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .animation(.spring(duration: 0.3, bounce: 0.1), value: isExpanded)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
        )
        .popoverTip(tip, arrowEdge: .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Copy Comment") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.commentary, forType: .string)
            }

            Button(entry.isFavorited ? "Unfavorite" : "Favorite") {
                appState.toggleFavorite(id: entry.id)
            }

            if let url = entry.appleMusicURL {
                Button("Open in Apple Music") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                appState.deleteHistoryRecord(id: entry.id)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.trackName) by \(entry.artist): \(entry.commentary)")
        .accessibilityAction(named: entry.isFavorited ? "Unfavorite" : "Favorite") {
            appState.toggleFavorite(id: entry.id)
        }
        .accessibilityAction(named: "Copy commentary") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.commentary, forType: .string)
        }
    }
}
