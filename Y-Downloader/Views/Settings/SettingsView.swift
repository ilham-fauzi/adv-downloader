import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            
            BinariesSettingsTab()
                .tabItem { Label("Binaries", systemImage: "terminal") }
            
            OutputSettingsTab()
                .tabItem { Label("Output", systemImage: "folder") }

            VPNSettingsView()
                .tabItem { Label("VPN", systemImage: "network.badge.shield.half.filled") }
            
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .preferredColorScheme(settingsStore.appearance.colorScheme)
    }
}

struct GeneralSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    
    var body: some View {
        @Bindable var s = settings
        Form {
            HStack {
                TextField("Default Output:", text: $s.defaultOutputDir)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK {
                        settings.defaultOutputDir = panel.url?.path ?? ""
                    }
                }
            }
            Picker("Default App Mode:", selection: $s.appMode) {
                Text("Simple").tag(AppMode.simple)
                Text("Advanced").tag(AppMode.advanced)
            }
            Toggle("Monitor Clipboard for URLs", isOn: $s.clipboardMonitoring)
            Picker("Appearance:", selection: $s.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show Video Thumbnail", isOn: $s.showThumbnail)
            Toggle("Show Notifications", isOn: $s.showNotifications)
            Toggle("Show Menu Bar Icon", isOn: $s.showMenuBarExtra)
            Toggle("Experimental: Browser tab", isOn: $s.showBrowserTab)
            Stepper("Max Concurrent Downloads: \(settings.maxConcurrentDownloads)", value: $s.maxConcurrentDownloads, in: 1...5)
        }
        .formStyle(.grouped)
    }
}

struct BinariesSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(QueueManager.self) private var queueManager
    @State private var message: String = ""
    @State private var busy = false
    
    var body: some View {
        @Bindable var s = settings
        Form {
            Section("yt-dlp") {
                HStack {
                    TextField("Path:", text: $s.ytdlpPath)
                    Button("Detect") {
                        Task {
                            if let url = await DependencyChecker.findExecutable(named: "yt-dlp") {
                                settings.ytdlpPath = url.path
                                await queueManager.ytdlpService.setCustomPath(url.path)
                                message = "Found yt-dlp at \(url.path)"
                            } else {
                                message = "yt-dlp was not found. Install it with Homebrew: brew install yt-dlp"
                            }
                        }
                    }
                }
                Picker("Update Channel", selection: $s.updateChannel) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Nightly").tag(UpdateChannel.nightly)
                    Text("Master").tag(UpdateChannel.master)
                }
                Toggle("Auto-update", isOn: $s.autoUpdateYtdlp)
                HStack {
                    Button("Update Now") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                message = try await queueManager.ytdlpService.updateBinary(channel: settings.updateChannel.rawValue)
                            } catch { message = error.localizedDescription }
                        }
                    }
                    Button("Check Version") {
                        Task {
                            do { message = "yt-dlp " + (try await queueManager.ytdlpService.getVersion()) }
                            catch { message = error.localizedDescription }
                        }
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                }
            }
            
            Section("FFmpeg") {
                HStack {
                    TextField("Path:", text: $s.ffmpegPath)
                    Button("Detect") {
                        Task {
                            if let url = await DependencyChecker.findExecutable(named: "ffmpeg") {
                                settings.ffmpegPath = url.path
                                message = "Found ffmpeg at \(url.path)"
                            } else {
                                message = "ffmpeg was not found. Install it with Homebrew: brew install ffmpeg"
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct OutputSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    
    var body: some View {
        @Bindable var s = settings
        Form {
            TextField("Default Output Template", text: $s.defaultOutputTemplate)
            Button("Template Variables Reference") {
                // show reference
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("ADV Downloader").font(.title).bold()
            Text("Version 0.1.0").foregroundColor(.secondary)
            
            HStack {
                Link("GitHub", destination: URL(string: "https://github.com")!)
                Text("•")
                Link("Report Issue", destination: URL(string: "https://github.com/issues")!)
            }
            
            Text("License: GPL-3.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
