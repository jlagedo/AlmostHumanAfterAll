import AppKit
import SwiftUI
import TipKit
import os

@Observable
@MainActor
final class NotificationState {
    var isDismissing = false
}

private let logger = Logger(subsystem: "com.ficino", category: "Notification")

// MARK: - FicinoPanel

private final class FicinoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

// MARK: - NotificationService

@MainActor
final class NotificationService {
    private static let dismissAnimationDuration: UInt64 = 400_000_000 // 0.4s, matches .spring(duration: 0.4)

    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var notificationState: NotificationState?

    var duration: TimeInterval = 30.0
    var position: NotificationPosition = .topRight

    func send(track: TrackInfo, comment: String, artwork: NSImage?) {
        logger.info("Showing floating notification for: \(track.name) (duration: \(self.duration, format: .fixed(precision: 0))s)")

        // Cancel any pending teardown and immediately remove old panel
        teardownTask?.cancel()
        teardownTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        if let panel = window {
            panel.orderOut(nil)
            window = nil
        }
        notificationState = nil

        let state = NotificationState()
        self.notificationState = state

        let content = FloatingNotificationView(
            track: track,
            comment: comment,
            artwork: artwork,
            state: state,
            position: position,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        showPanel(content)
    }

    private func showPanel<V: View>(_ content: V) {

        let hostingController = NSHostingController(rootView: content)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)

        let panel = FicinoPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.hidesOnDeactivate = false
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

        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topRight:
            x = screenFrame.maxX - width - 16
            y = screenFrame.maxY - height - 16
        case .topLeft:
            x = screenFrame.minX + 16
            y = screenFrame.maxY - height - 16
        case .bottomRight:
            x = screenFrame.maxX - width - 16
            y = screenFrame.minY + 16
        case .bottomLeft:
            x = screenFrame.minX + 16
            y = screenFrame.minY + 16
        }

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
        logger.debug("Dismissing floating notification")
        self.window = nil

        // Signal the SwiftUI view to animate out
        notificationState?.isDismissing = true
        notificationState = nil

        // Delay panel teardown to let the slide-out animation complete
        teardownTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.dismissAnimationDuration)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

// MARK: - Floating Notification View

struct FloatingNotificationView: View {
    let track: TrackInfo
    let comment: String
    let artwork: NSImage?
    let state: NotificationState
    let position: NotificationPosition
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    private let dismissTip = DismissNotificationTip()

    private var slidesFromRight: Bool {
        position == .topRight || position == .bottomRight
    }

    private var offscreenOffset: CGFloat {
        slidesFromRight ? 400 : -400
    }

    private var slideOffset: CGFloat {
        if state.isDismissing {
            return offscreenOffset
        } else if appeared {
            return dragOffset
        } else {
            return offscreenOffset
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: artwork, track info
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
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.name)
                        .font(.system(.title3, weight: .semibold))
                        .lineLimit(2)

                    Text("\(track.artist) — \(track.album)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Comment at full width
            Text(comment)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .popoverTip(dismissTip, arrowEdge: slidesFromRight ? .trailing : .leading)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .offset(x: slideOffset)
        .animation(.spring(duration: 0.5, bounce: 0.15), value: appeared)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: state.isDismissing)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.width
                    if slidesFromRight {
                        if translation > 0 { dragOffset = translation }
                    } else {
                        if translation < 0 { dragOffset = translation }
                    }
                }
                .onEnded { value in
                    let distance = value.translation.width
                    let velocity = value.velocity.width
                    if slidesFromRight {
                        if distance > 100 || velocity > 300 {
                            onDismiss()
                        } else {
                            dragOffset = 0
                        }
                    } else {
                        if distance < -100 || velocity < -300 {
                            onDismiss()
                        } else {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                appeared = true
            }
        }
    }
}
