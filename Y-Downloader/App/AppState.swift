import Foundation
import SwiftUI

// MARK: - Enums

enum OptionsTab: String, CaseIterable, Identifiable, Codable {
    case format
    case postProcessing
    case subtitles
    case network
    case filesystem
    case advanced
    var id: String { rawValue }
}

// AppMode is defined in Stores/SettingsStore.swift

enum AppError: Error, LocalizedError {
    case binaryNotFound
    case analysisError(String)
    case downloadError(String)
    case vpnUnavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "yt-dlp binary not found"
        case .analysisError(let msg): return msg
        case .downloadError(let msg): return msg
        case .vpnUnavailable: return "VPN is turned on but not connected, so nothing was sent. Reconnect the VPN or turn it off."
        case .unknown: return "An unknown error occurred"
        }
    }
}

/// "Download complete" toast content.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String?
}

/// A channel / playlist / search result list being browsed.
struct ListingState {
    let source: ListingSource
    /// What the user typed, restored in the link box when coming back from a video.
    let input: String
    var title: String?
    var entries: [ListingEntry] = []
    var isLoading = true
    var error: String?
    var canLoadMore = false
    var nextStart = 1
}

/// Top-level tab: the downloader, or the experimental browser.
enum AppSection: String, CaseIterable, Identifiable {
    case downloader, browser
    var id: String { rawValue }
}

// MARK: - App State

@Observable
final class AppState {
    var currentURL: String = ""
    var currentVideoInfo: VideoInfo? = nil
    var downloadOptions: DownloadOptions = DownloadOptions()
    var isAnalyzing: Bool = false
    var selectedTab: OptionsTab = .format
    var mode: AppMode = .simple
    var error: AppError? = nil
    var showSetupAssistant: Bool = false
    var resultsTab: QualityOption.Kind = .video
    var clipboardDismissed: Bool = false
    var showSettings: Bool = false
    var toast: Toast?
    var listing: ListingState?
    var section: AppSection = .downloader
    private var listingToken = UUID()
    private var lastAnalyzedURL: String?
    private var autoAnalyzeTask: Task<Void, Never>?
    var outputDirectory: String = NSHomeDirectory() + "/Downloads/Y-Downloader"

    /// Called whenever the link text changes. A pasted link is analyzed immediately;
    /// a typed one after a short pause, so half-typed addresses are not sent to yt-dlp.
    @MainActor
    func linkChanged(from old: String, to new: String, using service: YTDLPService) {
        autoAnalyzeTask?.cancel()
        let url = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { lastAnalyzedURL = nil; return }
        guard Self.looksComplete(url), url != lastAnalyzedURL else { return }

        let pasted = new.count - old.count > 5
        autoAnalyzeTask = Task { [weak self] in
            if !pasted { try? await Task.sleep(for: .milliseconds(800)) }
            guard !Task.isCancelled, let self else { return }
            await self.analyze(using: service)
        }
    }

    /// Valid link with a path (e.g. `site.com/watch?v=1`), not just a bare domain.
    private static func looksComplete(_ s: String) -> Bool {
        guard ErrorMapper.check(s) == .ok else { return false }
        let candidate = s.contains("://") ? s : "https://" + s
        guard let u = URL(string: candidate) else { return false }
        return u.path.count > 1 || u.query != nil
    }

    // MARK: Browsing lists

    /// Show a channel / playlist / search as a list of videos. Opening the same list again is a no-op.
    @MainActor
    func openListing(_ source: ListingSource, input: String, using service: YTDLPService) async {
        if let l = listing, l.source == source, l.error == nil { return }
        autoAnalyzeTask?.cancel()
        let token = UUID()
        listingToken = token
        listing = ListingState(source: source, input: input)
        currentVideoInfo = nil
        error = nil
        await loadPage(token: token, using: service)
    }

    @MainActor
    func loadMore(using service: YTDLPService) async {
        guard let l = listing, !l.isLoading, l.canLoadMore else { return }
        listing?.isLoading = true
        listing?.error = nil
        await loadPage(token: listingToken, using: service)
    }

    @MainActor
    func retryListing(using service: YTDLPService) async {
        guard let l = listing, !l.isLoading else { return }
        listing?.isLoading = true
        listing?.error = nil
        await loadPage(token: listingToken, using: service)
    }

    @MainActor
    private func loadPage(token: UUID, using service: YTDLPService) async {
        guard let l = listing else { return }
        let start = l.nextStart
        let end = start + ListingSource.pageSize - 1
        do {
            let page = try await service.list(source: l.source, start: start, end: end)
            guard token == listingToken, listing != nil else { return }
            var seen = Set(listing!.entries.map(\.id))
            let fresh = page.entries.filter { seen.insert($0.id).inserted }
            listing!.entries += fresh
            listing!.title = listing!.title ?? page.title
            listing!.nextStart = end + 1
            listing!.canLoadMore = page.rawCount >= ListingSource.pageSize && end < ListingSource.maxItems
            listing!.isLoading = false
        } catch {
            guard token == listingToken, listing != nil else { return }
            listing!.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            listing!.isLoading = false
        }
    }

    /// Open a list entry: a video goes to the quality picker, a playlist opens as another list.
    @MainActor
    func open(_ entry: ListingEntry, using service: YTDLPService) async {
        currentURL = entry.url
        await analyze(using: service)
    }

    /// Leave a video's quality picker and return to the list it came from.
    @MainActor
    func backToList() {
        guard let l = listing else { return }
        autoAnalyzeTask?.cancel()
        lastAnalyzedURL = nil
        currentVideoInfo = nil
        isAnalyzing = false
        error = nil
        currentURL = l.input
    }

    /// Send the page open in the browser tab to the downloader.
    @MainActor
    func downloadFromBrowser(_ url: String, using service: YTDLPService) async {
        section = .downloader
        currentVideoInfo = nil
        error = nil
        currentURL = url
        await analyze(using: service)
    }

    @MainActor
    func closeListing() {
        listingToken = UUID()
        listing = nil
        currentURL = ""
        currentVideoInfo = nil
        error = nil
    }

    /// Validate the current URL, then fetch its metadata with yt-dlp.
    @MainActor
    func analyze(using service: YTDLPService) async {
        if let source = ListingSource.detect(currentURL) {
            await openListing(source, input: currentURL.trimmingCharacters(in: .whitespacesAndNewlines), using: service)
            return
        }
        switch ErrorMapper.check(currentURL) {
        case .empty:
            error = .analysisError("Paste a link first.")
            return
        case .invalid:
            error = .analysisError("This link doesn’t lead to a video.")
            return
        case .ok:
            break
        }

        let url = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAnalyzing && url == lastAnalyzedURL { return }   // already running for this link
        lastAnalyzedURL = url
        error = nil
        isAnalyzing = true
        currentVideoInfo = nil
        resultsTab = .video
        defer { isAnalyzing = false }

        do {
            let info = try await service.analyze(url: url)
            // Ignore stale results if the user changed the link meanwhile.
            guard url == currentURL.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            currentVideoInfo = info
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .analysisError(error.localizedDescription)
        }
    }
}
