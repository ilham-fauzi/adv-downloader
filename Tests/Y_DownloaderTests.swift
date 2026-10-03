import XCTest
import WebKit
@testable import Y_Downloader

final class ParsingTests: XCTestCase {
    func testProgressParse() throws {
        let u = try XCTUnwrap(ProgressUpdate.parse("YDLP|||  58.1%|||   2.62MiB/s|||00:03|||130048|||223779"))
        XCTAssertEqual(u.percent, 58.1, accuracy: 0.001)
        XCTAssertEqual(u.speed, "2.62MiB/s")
        XCTAssertEqual(u.eta, "00:03")
        XCTAssertNotNil(u.totalBytes)
    }

    func testProgressParseHandlesNA() throws {
        let u = try XCTUnwrap(ProgressUpdate.parse("YDLP|||100.0%|||1.38MiB/s|||NA|||223779|||NA"))
        XCTAssertEqual(u.eta, "")
        XCTAssertNil(u.totalBytes)
    }

    func testProgressParseIgnoresOtherLines() {
        XCTAssertNil(ProgressUpdate.parse("[download] Destination: x.mp4"))
    }

    func testOutputPath() {
        XCTAssertEqual(OutputPathParser.path(from: "[Merger] Merging formats into \"/tmp/a b.mp4\""), "/tmp/a b.mp4")
        XCTAssertEqual(OutputPathParser.path(from: "[ExtractAudio] Destination: /tmp/a.mp3"), "/tmp/a.mp3")
        XCTAssertEqual(OutputPathParser.path(from: "[download] /tmp/a.mp4 has already been downloaded"), "/tmp/a.mp4")
        XCTAssertNil(OutputPathParser.path(from: "[info] something"))
    }

    func testErrorMapper() {
        XCTAssertTrue(ErrorMapper.message(for: "ERROR: Unsupported URL: https://x.com").contains("doesn’t lead to a video"))
        XCTAssertTrue(ErrorMapper.message(for: "ERROR: HTTP Error 503").contains("Connection lost"))
        XCTAssertTrue(ErrorMapper.message(for: "ERROR: Private video").contains("private"))
        XCTAssertTrue(ErrorMapper.message(for: "ERROR: Sign in to confirm you’re not a bot").contains("not a bot"))
    }

    func testURLCheck() {
        XCTAssertEqual(ErrorMapper.check("  "), .empty)
        XCTAssertEqual(ErrorMapper.check("hello"), .invalid)
        XCTAssertEqual(ErrorMapper.check("https://vimeo.com/823415907"), .ok)
        XCTAssertEqual(ErrorMapper.check("youtu.be/abc"), .ok)
    }
}

final class QualityTests: XCTestCase {
    private func info(_ json: String) throws -> VideoInfo {
        try JSONDecoder().decode(VideoInfo.self, from: Data(json.utf8))
    }

    func testVideoOptionsAndRecommended() throws {
        let i = try info("""
        {"id":"x","duration":100,"formats":[
         {"format_id":"a","vcodec":"none","acodec":"opus","filesize":1000},
         {"format_id":"v1","vcodec":"avc1","acodec":"none","height":2160,"filesize":9000},
         {"format_id":"v2","vcodec":"avc1","acodec":"none","height":1080,"filesize":5000},
         {"format_id":"v3","vcodec":"avc1","acodec":"none","height":720,"filesize":2000},
         {"format_id":"v4","vcodec":"avc1","acodec":"none","height":144,"filesize":100}]}
        """)
        let v = QualityOptions.video(from: i)
        XCTAssertEqual(v.map(\.quality), ["2160p", "1080p", "720p"])   // 144p dropped
        XCTAssertEqual(v.first(where: \.isRecommended)?.quality, "1080p")
        XCTAssertEqual(v[1].estimatedBytes, 6000)                        // video + best audio
        XCTAssertEqual(v[0].label, "4K Ultra HD")
    }

    func testAudioOptionsApplyBitrate() throws {
        let i = try info(#"{"id":"x","duration":60}"#)
        let a = QualityOptions.audio(from: i)
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.first(where: \.isRecommended)?.quality, "320 kbps")
        let opts = a[0].options(basedOn: DownloadOptions())
        XCTAssertTrue(opts.extractAudio)
        let args = opts.toArgs()
        XCTAssertTrue(args.contains("320K"))
    }

    func testVideoOptionDoesNotMutateBase() throws {
        let i = try info(#"{"id":"x","formats":[{"format_id":"v","vcodec":"avc1","acodec":"none","height":720}]}"#)
        let base = DownloadOptions()
        let before = base.format
        let o = QualityOptions.video(from: i)[0].options(basedOn: base)
        XCTAssertEqual(base.format, before)
        XCTAssertTrue(o.format?.contains("height<=720") == true)
        XCTAssertFalse(o.toArgs().contains("--embed-thumbnail"))   // would fail on non-mp4 containers
    }
}

final class QueueStoreTests: XCTestCase {
    @MainActor
    func testRoundTripAndInterruptedRestore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = QueueStore(fileURL: url)
        store.save([QueueStore.Record(id: UUID(), url: "https://a.com/v", title: "T", options: DownloadOptions(),
                                      outputDir: "/tmp", status: .downloading, progress: 42, error: nil, outputPath: nil,
                                      createdAt: Date(), completedAt: nil, optionId: "video-1080", qualityLabel: "1080p")])
        XCTAssertEqual(store.load().first?.title, "T")

        let restored = QueueManager(store: store).items
        XCTAssertEqual(restored.first?.status, .paused)    // interrupted downloads come back paused
        XCTAssertEqual(restored.first?.progress, 42)
    }
}

/// Runs the real YTDLPService against a stub "yt-dlp" shell script.
final class ServiceStubTests: XCTestCase {
    private func stub(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stub-\(UUID()).sh")
        try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private func collect(_ path: String) async -> [DownloadEvent] {
        let service = YTDLPService()
        await service.setCustomPath(path)
        let (_, events) = await service.download(url: "https://x.com/v", options: DownloadOptions(), outputDir: "/tmp")
        var out: [DownloadEvent] = []
        for await e in events { out.append(e) }
        return out
    }

    func testSuccessScalesTwoStreamsAndReportsPath() async throws {
        let path = try stub("""
        echo '[info] x: Downloading 1 format(s): 1+2'
        echo '[download] Destination: /tmp/a.f1.mp4'
        echo 'YDLP|||100.0%|||1MiB/s|||00:00|||10|||10'
        echo '[download] Destination: /tmp/a.f2.m4a'
        echo 'YDLP|||50.0%|||1MiB/s|||00:00|||5|||10'
        echo '[Merger] Merging formats into "/tmp/a.mp4"'
        exit 0
        """)
        let events = await collect(path)
        let percents = events.compactMap { if case .progress(let u) = $0 { return u.percent } else { return nil } }
        XCTAssertEqual(percents, [50, 75])
        XCTAssertTrue(events.contains { if case .postProcessing = $0 { return true } else { return false } })
        guard case .completed(let p)? = events.last else { return XCTFail("expected completed, got \(String(describing: events.last))") }
        XCTAssertEqual(p, "/tmp/a.mp4")
    }

    func testNonZeroExitIsFailureWithFriendlyMessage() async throws {
        let path = try stub("echo 'ERROR: [x] HTTP Error 503: Service Unavailable'; exit 1")
        let events = await collect(path)
        guard case .error(let msg)? = events.last else { return XCTFail("expected error") }
        XCTAssertTrue(msg.contains("Connection lost"))
        XCTAssertFalse(events.contains { if case .completed = $0 { return true } else { return false } })
    }

    func testCancelKillsProcessAndEmitsNoCompletion() async throws {
        let path = try stub("echo 'YDLP|||1.0%|||1MiB/s|||00:99|||1|||100'; sleep 30")
        let service = YTDLPService()
        await service.setCustomPath(path)
        let (handle, events) = await service.download(url: "https://x.com/v", options: DownloadOptions(), outputDir: "/tmp")
        var seen: [DownloadEvent] = []
        let start = Date()
        for await e in events {
            seen.append(e)
            if case .progress = e { handle.cancel() }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertFalse(seen.contains { if case .completed = $0 { return true } else { return false } })
        XCTAssertFalse(seen.contains { if case .error = $0 { return true } else { return false } })
    }
}

final class VPNTests: XCTestCase {
    func testKeyNormalizationAddsTrailingNewlineAndFixesCRLF() throws {
        let raw = "  -----BEGIN OPENSSH PRIVATE KEY-----\r\nabc\r\n-----END OPENSSH PRIVATE KEY-----  "
        let key = try VPNSettings.normalizedKey(raw)
        XCTAssertTrue(key.hasSuffix("-----END OPENSSH PRIVATE KEY-----\n"))
        XCTAssertFalse(key.contains("\r"))
    }

    func testPublicKeyAndGarbageAreRejected() {
        XCTAssertThrowsError(try VPNSettings.normalizedKey("ssh-ed25519 AAAA user@host"))
        XCTAssertThrowsError(try VPNSettings.normalizedKey("hello"))
        XCTAssertThrowsError(try VPNSettings.normalizedKey("   "))
    }

    func testSSHErrorsAreMapped() {
        XCTAssertTrue(SSHTunnelManager.friendlyError(from: "user@h: Permission denied (publickey).", code: 255).contains("Login failed"))
        XCTAssertTrue(SSHTunnelManager.friendlyError(from: "ssh: connect to host h port 22: Connection refused", code: 255).contains("refused"))
        XCTAssertTrue(SSHTunnelManager.friendlyError(from: "Could not resolve hostname x", code: 255).contains("not found"))
    }
}

final class ListingTests: XCTestCase {
    func testDetectSearchAndLinks() {
        XCTAssertEqual(ListingSource.detect("swift tutorial"), .search("swift tutorial"))
        XCTAssertEqual(ListingSource.detect("music"), .search("music"))
        XCTAssertEqual(ListingSource.detect("https://www.youtube.com/results?search_query=cats"), .search("cats"))
        XCTAssertEqual(ListingSource.detect("https://www.youtube.com/@Apple"), .url("https://www.youtube.com/@Apple/videos"))
        XCTAssertEqual(ListingSource.detect("youtube.com/@Apple/shorts"), .url("https://www.youtube.com/@Apple/shorts"))
        XCTAssertEqual(ListingSource.detect("https://www.youtube.com/channel/UC123"), .url("https://www.youtube.com/channel/UC123/videos"))
        XCTAssertEqual(ListingSource.detect("https://www.youtube.com/playlist?list=PL1"), .url("https://www.youtube.com/playlist?list=PL1"))
    }

    func testSingleVideoLinksAreNotLists() {
        XCTAssertNil(ListingSource.detect("https://www.youtube.com/watch?v=abc12345678"))
        XCTAssertNil(ListingSource.detect("https://www.youtube.com/watch?v=abc12345678&list=PL1"))
        XCTAssertNil(ListingSource.detect("https://youtu.be/abc12345678"))
        XCTAssertNil(ListingSource.detect("https://vimeo.com/12345"))
        XCTAssertNil(ListingSource.detect(""))
    }

    func testParseFlattensChannelTabsAndDropsPrivate() throws {
        let json = """
        {"_type":"playlist","title":"Apple - Videos","entries":[
          {"_type":"playlist","title":"Videos","entries":[
            {"id":"aaaaaaaaaaa","title":"One","url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","ie_key":"Youtube","duration":3725,"view_count":1500000,"channel":"Apple"},
            {"id":"bbbbbbbbbbb","title":"[Private video]","url":"https://www.youtube.com/watch?v=bbbbbbbbbbb","ie_key":"Youtube"}]}]}
        """
        let page = try ListingParser.parse(Data(json.utf8))
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.rawCount, 2)
        XCTAssertEqual(page.entries[0].durationText, "1:02:05")
        XCTAssertEqual(page.entries[0].viewsText, "1.5M views")
        XCTAssertEqual(page.entries[0].thumbnail, "https://i.ytimg.com/vi/aaaaaaaaaaa/mqdefault.jpg")
    }

    func testLiveSearchReturnsVideos() async throws {
        let service = YTDLPService()
        guard await service.findBinary() != nil else { throw XCTSkip("yt-dlp not installed") }
        let page = try await service.list(source: .search("swift tutorial"), start: 1, end: 5)
        XCTAssertFalse(page.entries.isEmpty)
        XCTAssertTrue(page.entries.allSatisfy { $0.url.hasPrefix("http") })
    }
}

final class BrowserTests: XCTestCase {
    /// Heavy: converts a real EasyList copy and compiles it in WebKit. Skipped unless YDL_EASYLIST points to a file.
    @MainActor
    func testEasyListConvertsAndCompiles() async throws {
        guard let path = ProcessInfo.processInfo.environment["YDL_EASYLIST"] else { throw XCTSkip("set YDL_EASYLIST") }
        let start = Date()
        let rules = await FilterLists.convertedRules(from: URL(fileURLWithPath: path))
        let converted = try XCTUnwrap(rules)
        print("CONVERTED \(converted.count) rules in \(Date().timeIntervalSince(start))s")
        let compileStart = Date()
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ydl-test-easylist", encodedContentRuleList: converted.json)
        print("COMPILED in \(Date().timeIntervalSince(compileStart))s")
        XCTAssertNotNil(list)
        try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "ydl-test-easylist")
    }

    @MainActor
    func testAdBlockRulesCompile() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ydl-test-rules", encodedContentRuleList: AdBlocker.rulesJSON())
        XCTAssertNotNil(list)
        try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "ydl-test-rules")
    }

    func testAddressResolution() {
        XCTAssertEqual(BrowserModel.resolve("example.com/a")?.absoluteString, "https://example.com/a")
        XCTAssertEqual(BrowserModel.resolve("http://example.com")?.absoluteString, "http://example.com")
        XCTAssertEqual(BrowserModel.resolve("swift tutorial")?.absoluteString, "https://duckduckgo.com/?q=swift%20tutorial")
        XCTAssertNil(BrowserModel.resolve("  "))
    }
}
