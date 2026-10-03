import SwiftUI
import AppKit

/// Keeps the main window between the app's normal size and the visible area of the display it is on.
/// Native full-screen mode is turned off. Double-clicking the title bar (or the browser's address bar
/// background) fills the desktop; double-clicking again restores the previous size.
struct WindowSizer: NSViewRepresentable {
    static let normalSize = NSSize(width: 900, height: 650)

    func makeNSView(context: Context) -> NSView { SizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Fill the desktop, or go back to the size the window had before.
    @MainActor
    static func toggleFill(_ window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let isFilled = abs(window.frame.width - visible.width) < 3 && abs(window.frame.height - visible.height) < 3
        if isFilled {
            let target = savedFrames[ObjectIdentifier(window)] ?? NSRect(
                x: visible.midX - normalSize.width / 2, y: visible.midY - normalSize.height / 2,
                width: normalSize.width, height: normalSize.height)
            window.setFrame(target, display: true, animate: true)
            savedFrames[ObjectIdentifier(window)] = nil
        } else {
            savedFrames[ObjectIdentifier(window)] = window.frame
            window.setFrame(visible, display: true, animate: true)
        }
    }

    @MainActor private static var savedFrames: [ObjectIdentifier: NSRect] = [:]

    private final class SizerView: NSView {
        private var observers: [NSObjectProtocol] = []
        private var clickMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
            guard let window else { return }
            apply(to: window)

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reapply() }
                },
                center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reapply() }
                },
            ]
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return swallow ? nil : event
            }
        }

        private func reapply() { if let window { apply(to: window) } }

        private func apply(to window: NSWindow) {
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 3000, height: 2000)
            let normal = WindowSizer.normalSize
            window.minSize = normal
            window.maxSize = NSSize(width: max(visible.width, normal.width), height: max(visible.height, normal.height))
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
        }

        /// A double-click on empty title-bar space toggles fill/restore. Clicks on toolbar controls pass through.
        /// Returns true when the click was used (and should not reach the system).
        private func handle(_ event: NSEvent) -> Bool {
            guard event.clickCount == 2, let window, event.window === window,
                  event.locationInWindow.y >= window.contentLayoutRect.maxY,
                  let frameView = window.contentView?.superview else { return false }
            var view = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil))
            while let v = view {
                if v is NSControl { return false }
                view = v.superview
            }
            WindowSizer.toggleFill(window)
            return true
        }
    }
}
