import Foundation

/// Saves the download list so it survives quitting the app.
struct QueueStore {
    struct Record: Codable {
        var id: UUID
        var url: String
        var title: String?
        var options: DownloadOptions
        var outputDir: String
        var status: DownloadStatus
        var progress: Double
        var error: String?
        var outputPath: String?
        var createdAt: Date
        var completedAt: Date?
        var optionId: String?
        var qualityLabel: String?
    }

    let fileURL: URL

    init(fileURL: URL = QueueStore.defaultURL) { self.fileURL = fileURL }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Y-Downloader/queue.json")
    }

    func save(_ records: [Record]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            try enc.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; never block downloads on it.
        }
    }

    func load() -> [Record] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Record].self, from: data)) ?? []
    }
}
