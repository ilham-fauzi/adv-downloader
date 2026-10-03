import Foundation
import SwiftUI

@Observable
@MainActor
class QueueManager {
    private(set) var items: [DownloadItem] = []
    private(set) var activeCount: Int = 0

    /// Number of simultaneous downloads (1–5), driven by Settings when available.
    var maxConcurrent: Int {
        get { min(max(settings?.maxConcurrentDownloads ?? _maxConcurrent, 1), 5) }
        set { _maxConcurrent = min(max(newValue, 1), 5) }
    }
    @ObservationIgnored private var _maxConcurrent: Int = 3

    let ytdlpService: YTDLPService
    @ObservationIgnored var settings: SettingsStore?
    /// Receives every yt-dlp log line (hook up to `LogStore`).
    @ObservationIgnored var onLog: ((LogEntry) -> Void)?

    @ObservationIgnored var onCompleted: ((DownloadItem) -> Void)?
    @ObservationIgnored var onFailed: ((DownloadItem) -> Void)?

    private let store: QueueStore
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var handles: [UUID: DownloadHandle] = [:]

    init(ytdlpService: YTDLPService = YTDLPService(), settings: SettingsStore? = nil, store: QueueStore = QueueStore()) {
        self.ytdlpService = ytdlpService
        self.settings = settings
        self.store = store
        items = store.load().map { r in
            let item = DownloadItem(id: r.id, url: r.url, options: r.options, outputDir: r.outputDir,
                                    status: r.status, progress: r.progress, error: r.error,
                                    outputPath: r.outputPath, createdAt: r.createdAt, completedAt: r.completedAt)
            item.title = r.title
            item.optionId = r.optionId
            item.qualityLabel = r.qualityLabel
            // A download interrupted by quitting is restored as paused; resume continues the partial file.
            if [.queued, .analyzing, .downloading, .postProcessing].contains(item.status) { item.status = .paused }
            return item
        }
    }

    private func save() {
        store.save(items.map { i in
            QueueStore.Record(id: i.id, url: i.url, title: i.title, options: i.options, outputDir: i.outputDir,
                              status: i.status, progress: i.progress, error: i.error, outputPath: i.outputPath,
                              createdAt: i.createdAt, completedAt: i.completedAt,
                              optionId: i.optionId, qualityLabel: i.qualityLabel)
        })
    }

    // MARK: - Public API

    /// Add item to queue
    func enqueue(url: String, options: DownloadOptions, outputDir: String, videoInfo: VideoInfo? = nil,
                 optionId: String? = nil, qualityLabel: String? = nil) {
        // DownloadOptions is a reference type: copy it so later edits don't change queued items.
        let snapshot = Self.copy(options)
        if snapshot.ffmpegLocation == nil, let path = settings?.ffmpegPath, !path.isEmpty {
            snapshot.ffmpegLocation = path
        }
        let item = DownloadItem(url: url, videoInfo: videoInfo, options: snapshot, outputDir: outputDir)
        item.optionId = optionId
        item.qualityLabel = qualityLabel
        item.title = videoInfo?.title
        items.append(item)
        save()
        processNext()
    }

    /// Start processing the queue
    func startQueue() {
        processNext()
    }

    /// Pause a specific download
    func pause(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .paused
        cancelTask(for: id)
        save()
    }

    /// Resume a paused download
    func resume(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .queued
        processNext()
    }

    /// Cancel and remove from queue
    func cancel(_ id: UUID) {
        cancelTask(for: id)
        items.removeAll(where: { $0.id == id })
        save()
        processNext()
    }

    /// Retry a failed download
    func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .queued
        items[index].progress = 0
        items[index].error = nil
        save()
        processNext()
    }

    /// Remove completed/failed items
    func clearCompleted() {
        items.removeAll { $0.status == .completed || $0.status == .failed }
        save()
    }

    /// Reorder items
    func move(from offsets: IndexSet, to offset: Int) {
        items.move(fromOffsets: offsets, toOffset: offset)
    }

    // MARK: - Private

    private static func copy(_ options: DownloadOptions) -> DownloadOptions {
        guard let data = try? JSONEncoder().encode(options),
              let copy = try? JSONDecoder().decode(DownloadOptions.self, from: data) else { return options }
        return copy
    }

    private func processNext() {
        while activeCount < maxConcurrent,
              let nextIndex = items.firstIndex(where: { $0.status == .queued }) {
            items[nextIndex].status = .downloading
            let item = items[nextIndex]
            activeCount += 1

            let task = Task { [weak self] in
                guard let self else { return }
                await self.processItem(item)
                self.activeCount -= 1
                self.runningTasks.removeValue(forKey: item.id)
                self.handles.removeValue(forKey: item.id)
                self.processNext()
            }

            runningTasks[item.id] = task
        }
    }

    private func processItem(_ item: DownloadItem) async {
        let (handle, stream) = await ytdlpService.download(
            url: item.url,
            options: item.options,
            outputDir: item.outputDir
        )
        handles[item.id] = handle
        // The user may have cancelled/paused while the process was starting.
        if Task.isCancelled || item.status != .downloading { handle.cancel() }

        defer { save() }
        for await event in stream {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }

            switch event {
            case .progress(let update):
                items[index].status = .downloading
                items[index].progress = update.percent
                items[index].speed = update.speed
                items[index].eta = update.eta
                items[index].downloadedSize = update.downloadedBytes
                items[index].totalSize = update.totalBytes
            case .log(let entry):
                onLog?(entry)
            case .postProcessing:
                items[index].status = .postProcessing
                items[index].progress = 100
                items[index].speed = nil
                items[index].eta = nil
            case .completed(let path):
                items[index].status = .completed
                items[index].progress = 100
                items[index].outputPath = path
                items[index].completedAt = Date()
                save()
                onCompleted?(items[index])
            case .error(let msg):
                items[index].status = .failed
                items[index].error = msg
                save()
                onFailed?(items[index])
            }
        }
    }

    private func cancelTask(for id: UUID) {
        handles[id]?.cancel()
        handles.removeValue(forKey: id)
        runningTasks[id]?.cancel()
    }
}
