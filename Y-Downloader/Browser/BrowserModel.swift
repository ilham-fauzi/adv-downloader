import Foundation
import WebKit
import Network
import Observation

/// A file the browser is saving directly (not through yt-dlp).
@Observable
@MainActor
final class BrowserDownload: Identifiable {
    enum State: Equatable { case running, finished, failed(String) }
    let id = UUID()
    var name: String
    var progress: Double = 0
    var state: State = .running
    var path: String?
    @ObservationIgnored var download: WKDownload?
    @ObservationIgnored var progressObservation: NSKeyValueObservation?

    init(name: String) { self.name = name }
}

/// Experimental in-app browser. One WKWebView kept alive for the whole app session.
@Observable
@MainActor
final class BrowserModel: NSObject {
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    let webView: WKWebView
    private(set) var currentURL: URL?
    private(set) var title = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var loadError: String?
    private(set) var downloads: [BrowserDownload] = []
    var vpnBlocking = false
    /// Every site starts muted unless the user unmutes it. Per-site choices are remembered between launches.
    private(set) var muteByDefault = UserDefaults.standard.object(forKey: "browserMuteByDefault") as? Bool ?? true
    private(set) var siteMuteOverrides: [String: Bool] =
        UserDefaults.standard.dictionary(forKey: "browserMuteOverrides") as? [String: Bool] ?? [:]
    private(set) var canMute = true
    /// Block ads and trackers with built-in content-blocker rules.
    private(set) var adBlockEnabled = UserDefaults.standard.object(forKey: "browserAdBlock") as? Bool ?? true
    private(set) var adBlockReady = false
    /// Progress / result of the filter lists, shown as the shield's tooltip.
    private(set) var adBlockDetail: String?
    @ObservationIgnored private var adBlockGeneration = 0
    private(set) var statusMessage: String?

    /// Folder for direct file downloads (set by the app).
    @ObservationIgnored var downloadDirectory: () -> String = { NSHomeDirectory() + "/Downloads" }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.customUserAgent = Self.userAgent
        Task { await applyAdBlock() }
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in Task { @MainActor in self?.sync() } },
        ]
    }

    /// Host without "www.", used as the mute key.
    var currentHost: String? { Self.key(for: currentURL) }

    nonisolated static func key(for url: URL?) -> String? {
        guard var h = url?.host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    private func isMuted(host: String?) -> Bool {
        host.flatMap { siteMuteOverrides[$0] } ?? muteByDefault
    }

    var isCurrentSiteMuted: Bool { isMuted(host: currentHost) }

    /// Flip the mute state of the site being shown.
    func toggleMute() {
        guard let host = currentHost else { return }
        let newState = !isCurrentSiteMuted
        if newState == muteByDefault { siteMuteOverrides[host] = nil } else { siteMuteOverrides[host] = newState }
        persistMute()
        applyMute()
    }

    /// Whether sites without their own choice start muted.
    func setMuteByDefault(_ muted: Bool) {
        muteByDefault = muted
        persistMute()
        applyMute()
    }

    /// Forget per-site choices; every site follows the default again.
    func resetSiteMuteChoices() {
        siteMuteOverrides = [:]
        persistMute()
        applyMute()
    }

    private func persistMute() {
        UserDefaults.standard.set(muteByDefault, forKey: "browserMuteByDefault")
        UserDefaults.standard.set(siteMuteOverrides, forKey: "browserMuteOverrides")
    }

    /// Mute state follows the site being shown (or about to be shown).
    private func applyMute(host: String? = nil) {
        canMute = setPageMuted(isMuted(host: host ?? currentHost))
    }

    /// Uses WebKit's page-level mute (what Safari's tab speaker uses). It is an internal selector, so it is
    /// looked up at runtime and the button is disabled if a future macOS removes it.
    private func setPageMuted(_ muted: Bool) -> Bool {
        let selector = NSSelectorFromString("_setPageMuted:")
        guard webView.responds(to: selector), let imp = webView.method(for: selector) else { return false }
        typealias SetMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(imp, to: SetMuted.self)(webView, selector, muted ? 1 : 0)
        return true
    }

    private func sync() {
        let previousHost = currentHost
        let url = webView.url
        currentURL = (url == nil || url?.absoluteString == "about:blank") ? nil : url
        if currentHost != previousHost { applyMute() }
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    // MARK: Navigation

    func go(_ input: String) {
        guard let url = Self.resolve(input) else { return }
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    /// Empty the browser: stop loading, drop the page and show the blank start screen.
    func blank() {
        webView.stopLoading()
        loadError = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    /// One click: blank page, then delete cookies, cache, local storage and other site data
    /// (this also signs you out of every site).
    func clearEverything() async {
        blank()
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        statusMessage = "Browser cleared: page closed, cookies and site data deleted."
    }

    func dismissStatus() { statusMessage = nil }

    func setAdBlock(_ enabled: Bool) {
        adBlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "browserAdBlock")
        Task { await applyAdBlock(reload: true) }
    }

    /// Turn ad blocking on or off. The small built-in rules and the YouTube script apply at once;
    /// EasyList and EasyPrivacy are downloaded in the background the first time and then refreshed weekly.
    func applyAdBlock(reload: Bool = false) async {
        adBlockGeneration += 1
        let generation = adBlockGeneration
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        adBlockReady = false
        adBlockDetail = nil
        guard adBlockEnabled else {
            if reload, currentURL != nil { webView.reload() }
            return
        }

        controller.addUserScript(WKUserScript(source: AdBlocker.youTubeScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        let store = WKContentRuleListStore.default()!
        do {
            if let builtIn = try await store.compileContentRuleList(
                forIdentifier: AdBlocker.identifier, encodedContentRuleList: AdBlocker.rulesJSON()),
               generation == adBlockGeneration { controller.add(builtIn) }
        } catch {
            statusMessage = "Ad blocking could not start: \(error.localizedDescription)"
        }
        adBlockReady = true
        if reload, currentURL != nil { webView.reload() }

        // Cached lists first, then fetch whatever is missing or old.
        var loadedAny = await addCachedLists(to: controller, generation: generation)
        let stale = FilterLists.all.filter(FilterLists.isStale)
        if !stale.isEmpty {
            adBlockDetail = "Downloading ad filter lists…"
            var downloaded = false
            for list in stale {
                do { try await FilterLists.download(list); downloaded = true } catch { /* offline: keep the old copy */ }
                guard generation == adBlockGeneration else { return }
            }
            if downloaded {
                loadedAny = await addCachedLists(to: controller, generation: generation) || loadedAny
                if generation == adBlockGeneration, currentURL != nil { webView.reload() }
            }
        }
        guard generation == adBlockGeneration else { return }
        adBlockDetail = loadedAny ? "EasyList and EasyPrivacy are active." : "Only the basic ad rules are active (filter lists are unavailable)."
    }

    /// Compile (or reuse) the cached filter lists and add them to the page. Returns true if any list was added.
    private func addCachedLists(to controller: WKUserContentController, generation: Int) async -> Bool {
        let store = WKContentRuleListStore.default()!
        var added = false
        for list in FilterLists.all {
            guard generation == adBlockGeneration, let modified = FilterLists.modified(list) else { continue }
            let identifier = "ydl-\(list.id)-\(Int(modified.timeIntervalSince1970))"
            var compiled: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in continuation.resume(returning: list) }
            }
            if compiled == nil {
                adBlockDetail = "Preparing \(list.name)… the first time takes a minute."
                guard let rules = await FilterLists.convertedRules(from: FilterLists.file(for: list)),
                      generation == adBlockGeneration else { continue }
                compiled = try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules.json)
                // Drop older copies of this list.
                for old in await store.availableIdentifiers() ?? [] where old.hasPrefix("ydl-\(list.id)-") && old != identifier {
                    try? await store.removeContentRuleList(forIdentifier: old)
                }
            }
            if let compiled, generation == adBlockGeneration { controller.add(compiled); added = true }
        }
        return added
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { loadError = nil; webView.reload() }
    func stop() { webView.stopLoading() }

    /// URL as typed, a bare domain, or a web search.
    nonisolated static func resolve(_ input: String) -> URL? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.contains("://") { return URL(string: t) }
        if !t.contains(where: \.isWhitespace), t.contains("."), let u = URL(string: "https://" + t), u.host != nil { return u }
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: t)]
        return c.url
    }

    // MARK: Proxy (VPN tunnel)

    /// Route the browser through the SSH tunnel's SOCKS port. While VPN is required but not up, the proxy
    /// points at a port nobody listens on, so pages fail instead of loading outside the tunnel.
    func applyProxy(required: Bool, port: Int) {
        vpnBlocking = required
        if required, let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) {
            webView.configuration.websiteDataStore.proxyConfigurations =
                [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: p))]
        } else {
            webView.configuration.websiteDataStore.proxyConfigurations = []
        }
    }

    // MARK: Downloads

    func clearFinishedDownloads() {
        downloads.removeAll { $0.state != .running }
    }

    func cancel(_ item: BrowserDownload) {
        item.download?.cancel { _ in }
        item.state = .failed("Cancelled")
    }

    private func register(_ download: WKDownload) {
        download.delegate = self
        let item = BrowserDownload(name: "Downloading…")
        item.download = download
        item.progressObservation = download.progress.observe(\.fractionCompleted) { [weak item] p, _ in
            let value = p.fractionCompleted
            Task { @MainActor in item?.progress = value }
        }
        downloads.insert(item, at: 0)
    }

    private func item(for download: WKDownload) -> BrowserDownload? {
        downloads.first { $0.download === download }
    }

    private func uniqueDestination(for name: String) -> URL {
        let dir = URL(fileURLWithPath: downloadDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = (name as NSString).lastPathComponent.isEmpty ? "download" : (name as NSString).lastPathComponent
        let base = (safe as NSString).deletingPathExtension, ext = (safe as NSString).pathExtension
        var candidate = dir.appendingPathComponent(safe)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }
}

// MARK: - WebKit delegates

extension BrowserModel: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        if navigationAction.targetFrame?.isMainFrame ?? false, let host = Self.key(for: navigationAction.request.url) {
            applyMute(host: host)
        }
        // Only web pages load in the view; other schemes (mailto:, app links) are ignored.
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["http", "https", "about", "blob", "data", "file"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if disposition.hasPrefix("attachment") || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadError = nil
        applyMute()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }

    private func report(_ error: Error) {
        let ns = error as NSError
        // -999 = cancelled (a new navigation started); 102 = handed over to a download.
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain", ns.code == 102 { return }
        loadError = vpnBlocking
            ? "The page could not load. VPN is on; if it is not connected, the browser is blocked on purpose. (\(ns.localizedDescription))"
            : ns.localizedDescription
    }

    // Links that open a new window (target=_blank) stay in this view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let url = uniqueDestination(for: suggestedFilename)
        if let item = item(for: download) { item.name = url.lastPathComponent; item.path = url.path }
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.progress = 1
        item.state = .finished
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download), item.state == .running else { return }
        item.state = .failed(error.localizedDescription)
    }
}
