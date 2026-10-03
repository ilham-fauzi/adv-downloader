import Foundation

// MARK: - Download Status

enum DownloadStatus: String, Codable {
    case queued
    case analyzing
    case downloading
    case postProcessing
    case completed
    case paused
    case failed
}

// MARK: - Download Item

@Observable
final class DownloadItem: Identifiable {
    let id: UUID
    var url: String
    var videoInfo: VideoInfo?
    var options: DownloadOptions
    var outputDir: String
    var status: DownloadStatus
    var progress: Double
    var speed: String?
    var eta: String?
    var downloadedSize: String?
    var totalSize: String?
    var error: String?
    var outputPath: String?
    var createdAt: Date
    var completedAt: Date?
    /// Which quality row created this item (used to disable that row's button while busy).
    var title: String?
    var optionId: String?
    var qualityLabel: String?

    init(
        id: UUID = UUID(),
        url: String,
        videoInfo: VideoInfo? = nil,
        options: DownloadOptions = DownloadOptions(),
        outputDir: String = NSHomeDirectory() + "/Downloads/Y-Downloader",
        status: DownloadStatus = .queued,
        progress: Double = 0.0,
        speed: String? = nil,
        eta: String? = nil,
        downloadedSize: String? = nil,
        totalSize: String? = nil,
        error: String? = nil,
        outputPath: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.videoInfo = videoInfo
        self.options = options
        self.outputDir = outputDir
        self.status = status
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.downloadedSize = downloadedSize
        self.totalSize = totalSize
        self.error = error
        self.outputPath = outputPath
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
