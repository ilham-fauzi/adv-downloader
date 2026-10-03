import Foundation
import AppKit
import SwiftUI

@Observable
@MainActor
class ClipboardMonitor {
    var detectedURL: String?
    var isMonitoring: Bool = false
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    func startMonitoring() {
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        guard isMonitoring, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let string = pasteboard.string(forType: .string), isVideoURL(string) {
            detectedURL = string
        }
    }
    
    /// Check if string looks like a supported URL
    private func isVideoURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let host = url.host?.lowercased() else { return false }
        
        let supportedHosts = [
            "youtube.com", "youtu.be",
            "vimeo.com",
            "tiktok.com",
            "twitter.com", "x.com",
            "instagram.com",
            "facebook.com",
            "twitch.tv"
        ]
        
        // Direct match or subdomain match
        if supportedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }
        
        // Generic fallback for any http/https URL that might be supported by yt-dlp
        return url.scheme == "http" || url.scheme == "https"
    }
}
