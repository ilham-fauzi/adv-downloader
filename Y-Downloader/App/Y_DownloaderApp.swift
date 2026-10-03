import SwiftUI
import AppKit

/// A SwiftPM-built executable starts as a background process: it has no focus and no working
/// keyboard shortcuts (⌘C/⌘V/⌘A). Promote it to a regular, active app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct Y_DownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - State

    @State private var appState = AppState()
    @State private var ytdlpService = YTDLPService()
    @State private var queueManager: QueueManager
    @State private var commandBuilder: CommandBuilder
    @State private var settingsStore = SettingsStore()
    @State private var logStore = LogStore()
    @State private var presetManager = PresetManager()
    @State private var clipboardMonitor = ClipboardMonitor()
    @State private var tunnel: SSHTunnelManager
    @State private var browser: BrowserModel

    // MARK: - Init

    init() {
        let service = YTDLPService()
        let settings = SettingsStore()
        let logs = LogStore()
        let queue = QueueManager(ytdlpService: service, settings: settings)
        queue.onLog = { logs.append($0) }
        let vpnSettings = VPNSettings()
        let tunnel = SSHTunnelManager(settings: vpnSettings)
        let browser = BrowserModel()
        browser.downloadDirectory = { settings.defaultOutputDir }
        tunnel.onUpdate = { required, proxy in
            Task { await service.setVPN(required: required, proxy: proxy) }
            Task { @MainActor in browser.applyProxy(required: required, port: vpnSettings.localPort) }
        }
        _browser = State(initialValue: browser)
        _tunnel = State(initialValue: tunnel)
        _ytdlpService = State(initialValue: service)
        _settingsStore = State(initialValue: settings)
        _logStore = State(initialValue: logs)
        _queueManager = State(initialValue: queue)
        _commandBuilder = State(initialValue: CommandBuilder(
            options: DownloadOptions(),
            url: "",
            outputDir: NSHomeDirectory() + "/Downloads/Y-Downloader"
        ))
    }

    /// Show the toast and optional macOS notification when downloads finish or fail.
    private func wireQueueEvents() {
        let appState = appState, settings = settingsStore
        queueManager.onCompleted = { item in
            let name = item.videoInfo?.title ?? item.title ?? item.url
            appState.toast = Toast(name: name, path: item.outputPath)
            if settings.showNotifications { Notifier.notify(title: "Download complete", body: name) }
        }
        queueManager.onFailed = { item in
            if settings.showNotifications {
                Notifier.notify(title: "Download failed", body: item.error ?? (item.videoInfo?.title ?? item.title ?? item.url))
            }
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup("ADV Downloader") {
            ContentView()
                .environment(appState)
                .environment(queueManager)
                .environment(commandBuilder)
                .environment(settingsStore)
                .environment(logStore)
                .environment(presetManager)
                .environment(clipboardMonitor)
                .environment(tunnel)
                .environment(browser)
                .preferredColorScheme(settingsStore.appearance.colorScheme)
                .frame(minWidth: 900, minHeight: 650)
                .background(WindowSizer())
                .onAppear {
                    wireQueueEvents()
                    appState.outputDirectory = settingsStore.defaultOutputDir
                    appState.mode = settingsStore.appMode
                    let outputDir = appState.outputDirectory
                    try? FileManager.default.createDirectory(
                        atPath: outputDir,
                        withIntermediateDirectories: true
                    )
                }
        }
        .defaultSize(width: 900, height: 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Paste URL") {
                    if let content = NSPasteboard.general.string(forType: .string) {
                        appState.currentURL = content
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Start Download") {
                    guard !appState.currentURL.isEmpty else { return }
                    queueManager.enqueue(
                        url: appState.currentURL,
                        options: appState.downloadOptions,
                        outputDir: appState.outputDirectory,
                        videoInfo: appState.currentVideoInfo
                    )
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Analyze URL") {
                    Task { await appState.analyze(using: queueManager.ytdlpService) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Mode") {
                    appState.mode = appState.mode == .simple ? .advanced : .simple
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("ADV Downloader Help") {
                    // Open help
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settingsStore)
                .environment(queueManager)
                .environment(tunnel)
        }

        MenuBarExtra("ADV Downloader", systemImage: "arrow.down.circle.fill") {
            MenuBarView()
                .environment(appState)
                .environment(queueManager)
                .environment(settingsStore)
        }
    }
}
