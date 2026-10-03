import SwiftUI
import WebKit

private struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Experimental browser tab. Video pages go to the downloader; plain files download right here.
struct BrowserView: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(AppState.self) private var appState
    @Environment(QueueManager.self) private var queueManager
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            if browser.isLoading {
                ProgressView(value: browser.progress).progressViewStyle(.linear).controlSize(.mini)
            } else {
                Divider()
            }
            ZStack {
                WebViewContainer(webView: browser.webView)
                if browser.currentURL == nil && !browser.isLoading && browser.loadError == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "globe").font(.system(size: 40)).foregroundStyle(Theme.text3)
                        Text("Open any website").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Type an address or a search above. Video pages and files can be downloaded from here.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.center).frame(maxWidth: 360)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
                }
                if let error = browser.loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 28)).foregroundStyle(Theme.text3)
                        Text(error).font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.center).frame(maxWidth: 420)
                        Button("Try again") { browser.reload() }.buttonStyle(SecondaryButtonStyle(height: 34))
                    }
                    .padding(24)
                    .background(Theme.bg)
                }
            }
            if let message = browser.statusMessage {
                HStack {
                    Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button { browser.dismissStatus() } label: { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle())
                }
                .padding(.horizontal, 12).padding(.vertical, 4).background(Theme.surface2)
            }
            if !browser.downloads.isEmpty { downloadsStrip }
        }

        .onAppear {
            syncAddress()
            if browser.currentURL == nil { addressFocused = true }
        }
        .onChange(of: browser.currentURL) { _, _ in if !addressFocused { syncAddress() } }
    }

    // MARK: Address bar

    /// Drops the button labels when the window is narrow.
    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(compact: false)
            barContent(compact: true)
        }
    }

    private func barContent(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack).accessibilityLabel("Back")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward).accessibilityLabel("Forward")
            Button { browser.isLoading ? browser.stop() : browser.reload() } label: {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
            .accessibilityLabel(browser.isLoading ? "Stop" : "Reload")

            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Theme.text3)
                TextField("Search or enter an address", text: $address)
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .onSubmit { browser.go(address); addressFocused = false }
            }
            .padding(.horizontal, 12).frame(minWidth: 140, minHeight: 36, maxHeight: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(addressFocused ? Theme.accent : Theme.border, lineWidth: 1.5))

            Button { browser.setAdBlock(!browser.adBlockEnabled) } label: {
                Image(systemName: browser.adBlockEnabled ? "shield.lefthalf.filled" : "shield.slash")
                    .foregroundStyle(browser.adBlockEnabled ? Theme.accentText : Theme.text3)
            }
            .help(browser.adBlockEnabled
                  ? "Ad blocking is on. \(browser.adBlockDetail ?? "") Click to turn off"
                  : "Ad blocking is off. Click to turn on")
            .accessibilityLabel(browser.adBlockEnabled ? "Turn ad blocking off" : "Turn ad blocking on")

            Menu {
                Toggle("Mute all sites by default", isOn: Binding(
                    get: { browser.muteByDefault }, set: { browser.setMuteByDefault($0) }))
                Button("Reset choices for individual sites") { browser.resetSiteMuteChoices() }
                    .disabled(browser.siteMuteOverrides.isEmpty)
            } label: {
                Image(systemName: browser.isCurrentSiteMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(browser.isCurrentSiteMuted ? Theme.dangerText : Theme.text3)
            } primaryAction: {
                browser.toggleMute()
            }
            .menuStyle(.borderlessButton)
            .frame(width: 46)
            .disabled(browser.currentHost == nil || !browser.canMute)
            .help(muteHelp)
            .accessibilityLabel(browser.isCurrentSiteMuted ? "Unmute this site" : "Mute this site")

            Button { Task { await browser.clearEverything() } } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Clear browser: close the page and delete cookies and site data")
            .accessibilityLabel("Clear browser")

            actionButton(compact: compact)
        }
        .buttonStyle(IconButtonStyle())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { WindowSizer.toggleFill() }
    }

    private var muteHelp: String {
        guard let host = browser.currentHost else { return "Open a site to mute it" }
        if !browser.canMute { return "Muting is not available on this macOS version" }
        let action = browser.isCurrentSiteMuted ? "Unmute \(host)" : "Mute \(host)"
        return action + ". Click the arrow to mute every site by default."
    }

    private enum PageAction { case video, list, tryPage, none }

    private var pageAction: PageAction {
        guard let url = browser.currentURL, let host = url.host?.lowercased() else { return .none }
        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com")
        if ListingSource.detect(url.absoluteString) != nil { return .list }
        if host == "youtu.be" { return .video }
        if isYouTube {
            let path = url.path
            return path.hasPrefix("/watch") || path.hasPrefix("/shorts/") || path.hasPrefix("/live/") ? .video : .none
        }
        return url.path.count > 1 && url.scheme?.hasPrefix("http") == true ? .tryPage : .none
    }

    @ViewBuilder
    private func actionButton(compact: Bool) -> some View {
        switch pageAction {
        case .video:
            Button { send() } label: { actionLabel("Download video", "arrow.down.circle.fill", compact) }
                .buttonStyle(PrimaryButtonStyle(height: 36))
                .help("Download this video")
        case .list:
            Button { send() } label: { actionLabel("Show as list", "square.grid.2x2", compact) }
                .buttonStyle(PrimaryButtonStyle(height: 36))
                .help("Show the videos on this page as a list")
        case .tryPage:
            Button { send() } label: { actionLabel("Try to download", "arrow.down.circle", compact) }
                .buttonStyle(SecondaryButtonStyle(height: 36))
                .help("Ask yt-dlp to find a video on this page")
        case .none:
            Button {} label: { actionLabel("Download video", "arrow.down.circle", compact) }
                .buttonStyle(SecondaryButtonStyle(height: 36))
                .disabled(true)
                .help("Open a video page to download it")
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, _ icon: String, _ compact: Bool) -> some View {
        if compact { Image(systemName: icon).accessibilityLabel(title) } else { Label(title, systemImage: icon) }
    }

    private func send() {
        guard let url = browser.currentURL else { return }
        Task { await appState.downloadFromBrowser(url.absoluteString, using: queueManager.ytdlpService) }
    }

    private func syncAddress() { address = browser.currentURL?.absoluteString ?? "" }

    // MARK: Direct file downloads

    private var downloadsStrip: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Files").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text3)
                Spacer()
                Button("Clear") { browser.clearFinishedDownloads() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Theme.accentText)
            }
            .padding(.horizontal, 12).padding(.top, 6)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(browser.downloads) { BrowserFileRow(item: $0) }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .frame(maxHeight: 130)
        }
        .background(Theme.surface)
    }
}

private struct BrowserFileRow: View {
    let item: BrowserDownload
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                switch item.state {
                case .running: ProgressView(value: item.progress).controlSize(.small)
                case .finished: Text("Saved").font(.system(size: 12)).foregroundStyle(Theme.successText)
                case .failed(let m): Text(m).font(.system(size: 12)).foregroundStyle(Theme.dangerText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.state == .running {
                Button { browser.cancel(item) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).accessibilityLabel("Cancel download")
            } else if item.state == .finished, let path = item.path {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentText)
            }
        }
    }

    private var icon: String {
        switch item.state {
        case .running: return "arrow.down.circle"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    private var color: Color {
        switch item.state {
        case .running: return Theme.accent
        case .finished: return Theme.success
        case .failed: return Theme.danger
        }
    }
}
