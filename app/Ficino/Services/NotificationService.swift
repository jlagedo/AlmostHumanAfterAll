import AppKit
import SwiftUI
import MusicModel

@Observable
@MainActor
final class NotificationState {
    var isDismissing = false
}

@MainActor
final class NotificationService {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var notificationState: NotificationState?

    var duration: TimeInterval = 30.0

    func send(track: TrackInfo, comment: String, personality: Personality, artwork: NSImage?) {
        NSLog("[Notification] Showing floating notification for: %@ (duration: %.0fs)", track.name, duration)

        let state = NotificationState()
        self.notificationState = state

        let content = FloatingNotificationView(
            track: track,
            comment: comment,
            personality: personality,
            artwork: artwork,
            state: state,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        showPanel(content)
    }

    private func showPanel<V: View>(_ content: V) {
        dismiss()

        let hostingController = NSHostingController(rootView: content)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
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
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Hide the titlebar buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentViewController = hostingController

        // Let the hosting controller size itself
        let fittingSize = hostingController.view.fittingSize
        let width: CGFloat = 380

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let maxHeight = screenFrame.height - 32
        let height = min(max(fittingSize.height, 140), min(450, maxHeight))
        let x = screenFrame.maxX - width - 16
        let y = screenFrame.maxY - height - 16

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        panel.alphaValue = 1
        panel.orderFrontRegardless()

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

        // Signal the SwiftUI view to animate out
        notificationState?.isDismissing = true
        notificationState = nil

        // Delay panel teardown to let the slide-out animation complete
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            panel.orderOut(nil)
        }
    }
}

// MARK: - Floating Notification View

struct FloatingNotificationView: View {
    let track: TrackInfo
    let comment: String
    let personality: Personality
    let artwork: NSImage?
    let state: NotificationState
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0

    private var slideOffset: CGFloat {
        if state.isDismissing {
            return 400
        } else if appeared {
            return dragOffset
        } else {
            return 400
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: artwork, track info, dismiss button
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(.headline, weight: .semibold))
                        .lineLimit(2)

                    Text("\(track.artist) — \(track.album)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Dismiss button — always visible
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary.opacity(isHovering ? 0.8 : 0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }

            // Comment at full width
            Text(comment)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .offset(x: slideOffset)
        .animation(.spring(duration: 0.5, bounce: 0.15), value: appeared)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: state.isDismissing)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow rightward drag
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let distance = value.translation.width
                    let velocity = value.velocity.width
                    if distance > 100 || velocity > 300 {
                        onDismiss()
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                appeared = true
            }
        }
    }
}
