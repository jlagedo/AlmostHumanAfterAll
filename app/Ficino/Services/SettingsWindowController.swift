import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func showSettings() {
        // Dismiss the MenuBarExtra panel
        NSApp.keyWindow?.close()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ficino Settings"
        window.contentViewController = hostingController
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
