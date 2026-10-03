import XCTest
@testable import Y_Downloader

/// Hits the network and the real yt-dlp. Run with: LIVE=1 swift test --filter LiveTests
final class LiveTests: XCTestCase {
    func testAnalyzeAndDownloadRealVideo() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE"] == "1", "set LIVE=1 to run")
        let service = YTDLPService()
        let url = "https://archive.org/details/BigBuckBunny_124"
        let info = try await service.analyze(url: url)
        XCTAssertEqual(info.title, "Big Buck Bunny")
        XCTAssertFalse(QualityOptions.video(from: info).isEmpty)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID())").path
        let opt = QualityOptions.video(from: info).last!.options(basedOn: DownloadOptions())
        let (_, events) = await service.download(url: url, options: opt, outputDir: dir)
        var last: DownloadEvent?
        var sawProgress = false
        for await e in events { if case .progress = e { sawProgress = true }; last = e }
        XCTAssertTrue(sawProgress)
        guard case .completed(let path)? = last else { return XCTFail("not completed: \(String(describing: last))") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(path)), "output path \(path ?? "nil") missing")
    }
}
