import SwiftUI
import AppKit

struct DownloadsPanel: View {
    @Environment(QueueManager.self) private var queueManager
    @Environment(AppState.self) private var appState

    private var summary: String {
        let c = Dictionary(grouping: queueManager.items, by: \.status).mapValues(\.count)
        var parts: [String] = []
        if let n = c[.downloading] { parts.append("\(n) downloading") }
        if let n = c[.postProcessing] { parts.append("\(n) merging") }
        if let n = (c[.queued] ?? 0) + (c[.analyzing] ?? 0) + (c[.paused] ?? 0) as Int?, n > 0 { parts.append("\(n) queued") }
        if let n = c[.completed] { parts.append("\(n) completed") }
        if let n = c[.failed] { parts.append("\(n) failed") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads").font(.system(size: 14, weight: .semibold))
                Text(summary).font(.system(size: 12.5)).foregroundStyle(Theme.text3)
                Spacer()
                if queueManager.items.contains(where: { $0.status == .completed || $0.status == .failed }) {
                    Button("Clear finished") { queueManager.clearCompleted() }
                        .buttonStyle(.plain).foregroundStyle(Theme.text2).font(.system(size: 13, weight: .semibold))
                }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: appState.outputDirectory))
                } label: {
                    Label("Open downloads folder", systemImage: "folder")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accentText).font(.system(size: 13, weight: .semibold))
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(queueManager.items) { item in DownloadRow(item: item) }
                }
            }
            .frame(maxHeight: 4 * 56)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    @Environment(QueueManager.self) private var queueManager

    private var title: String {
        let base = item.videoInfo?.title ?? item.title ?? item.url
        return item.qualityLabel.map { "\(base) (\($0))" } ?? base
    }

    private var statusText: String {
        switch item.status {
        case .queued, .analyzing: return "Queued"
        case .downloading: return "Downloading"
        case .postProcessing: return "Merging files…"
        case .completed: return "Completed"
        case .paused: return "Paused"
        case .failed: return "Failed"
        }
    }

    private var color: Color {
        switch item.status {
        case .downloading, .postProcessing: return Theme.accentText
        case .queued, .analyzing, .paused: return Theme.warnText
        case .completed: return Theme.successText
        case .failed: return Theme.dangerText
        }
    }

    private var tint: Color {
        switch item.status {
        case .downloading, .postProcessing: return Theme.accentSoft
        case .queued, .analyzing, .paused: return Theme.warnSoft
        case .completed: return Theme.successSoft
        case .failed: return Theme.dangerSoft
        }
    }

    private var icon: String {
        switch item.status {
        case .downloading: return "arrow.down.to.line"
        case .postProcessing: return "gearshape"
        case .queued, .analyzing: return "clock"
        case .paused: return "pause"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }

    private var meta: String {
        switch item.status {
        case .downloading:
            var parts: [String] = []
            if let d = item.downloadedSize, let t = item.totalSize { parts.append("\(d) / \(t)") }
            if let s = item.speed, !s.isEmpty { parts.append(s) }
            if let e = item.eta, !e.isEmpty { parts.append("\(e) left") }
            return parts.isEmpty ? "Starting…" : parts.joined(separator: " • ")
        case .postProcessing: return "Combining video and sound, almost done"
        case .queued, .analyzing: return "Starts when another download finishes"
        case .paused: return "Interrupted — press Resume to continue"
        case .completed: return "Saved to \((item.outputDir as NSString).lastPathComponent)"
        case .failed: return item.error ?? "Something went wrong. Please try again."
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text(meta).font(.system(size: 12)).foregroundStyle(item.status == .failed ? Theme.dangerText : Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(statusText).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                if item.status == .postProcessing {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                } else {
                    ProgressView(value: min(max(item.progress, 0), 100), total: 100).tint(color)
                }
            }
            .frame(width: 170)
            Text("\(Int(item.progress))%")
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(item.status == .failed ? Theme.dangerText : (item.status == .completed ? Theme.successText : Theme.text))
                .frame(width: 56, alignment: .trailing)
            actions.frame(width: 190, alignment: .trailing)
        }
        .padding(.horizontal, 10).frame(height: 50)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.status == .failed ? Theme.dangerBorder : Color.clear))
    }

    @ViewBuilder private var actions: some View {
        switch item.status {
        case .downloading, .queued, .analyzing:
            Button("Cancel") { queueManager.cancel(item.id) }.buttonStyle(SecondaryButtonStyle(height: 32))
        case .paused:
            HStack(spacing: 6) {
                Button("Resume") { queueManager.resume(item.id) }.buttonStyle(PrimaryButtonStyle(height: 32))
                Button("Cancel") { queueManager.cancel(item.id) }.buttonStyle(SecondaryButtonStyle(height: 32))
            }
        case .postProcessing:
            Button("Cancel") {}.buttonStyle(SecondaryButtonStyle(height: 32)).disabled(true)
        case .completed:
            HStack(spacing: 6) {
                Button("Open File") { openFile() }.buttonStyle(PrimaryButtonStyle(height: 32))
                Button("Open Folder") { openFolder() }.buttonStyle(SecondaryButtonStyle(height: 32))
            }
        case .failed:
            HStack(spacing: 6) {
                Button { queueManager.retry(item.id) } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                Button { queueManager.cancel(item.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    .accessibilityLabel("Remove from list")
            }
        }
    }

    private func openFile() {
        if let path = item.outputPath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            openFolder()
        }
    }

    private func openFolder() {
        if let path = item.outputPath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.outputDir))
        }
    }
}
