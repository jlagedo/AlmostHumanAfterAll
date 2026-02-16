import AppKit
import SwiftUI
import MusicModel

@MainActor
final class NotificationService {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?

    var duration: TimeInterval = 30.0

    func send(track: TrackInfo, comment: String, personality: Personality, artwork: NSImage?) {
        NSLog("[Notification] Showing floating notification for: %@ (duration: %.0fs)", track.name, duration)

        let content = FloatingNotificationView(
            track: track,
            comment: comment,
            personality: personality,
            artwork: artwork,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        showPanel(content)
    }

    private func showPanel<V: View>(_ content: V) {
        dismiss()

        let hostingController = NSHostingController(rootView: content)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 390, height: 600)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Hide the titlebar buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentViewController = hostingController

        // Let the hosting controller size itself
        let fittingSize = hostingController.view.fittingSize
        let width: CGFloat = 390

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let maxHeight = screenFrame.height - 32
        let height = min(max(fittingSize.height, 120), min(400, maxHeight))
        let x = screenFrame.maxX - width - 16
        let y = screenFrame.maxY - height - 16

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.window = panel

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel = window else { return }
        NSLog("[Notification] Dismissing floating notification")
        self.window = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

// MARK: - Floating Notification View

struct FloatingNotificationView: View {
    let track: TrackInfo
    let comment: String
    let personality: Personality
    let artwork: NSImage?
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Artwork
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()

                    if isHovering {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss notification")
                    }
                }

                Text(track.name)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)

                Text("\(track.artist) — \(track.album)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(comment)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 390)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

