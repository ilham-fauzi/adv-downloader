import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(QueueManager.self) private var queueManager
    @Environment(SettingsStore.self) private var settingsStore
    @State private var quickURL: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Paste URL here...", text: $quickURL)
                    .textFieldStyle(.roundedBorder)
                Button("Download") {
                    startDownload()
                }
                .disabled(quickURL.isEmpty)
            }
            .padding(.horizontal)
            
            Divider()
            
            Text("Active Downloads: \(queueManager.activeCount)")
                .padding(.horizontal)
            
            if !queueManager.items.isEmpty {
                VStack(alignment: .leading) {
                    Text("Recent:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(queueManager.items.prefix(3)) { item in
                        HStack {
                            Text(item.videoInfo?.title ?? item.url)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(item.progress))%")
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            Button("Open Main Window") {
                openMainWindow()
            }
            .padding(.horizontal)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 300)
    }
    
    private func startDownload() {
        queueManager.enqueue(
            url: quickURL,
            options: DownloadOptions(),
            outputDir: settingsStore.defaultOutputDir
        )
        quickURL = ""
    }
    
    private func openMainWindow() {
        for window in NSApplication.shared.windows {
            if window.title == "ADV Downloader" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
    }
}
