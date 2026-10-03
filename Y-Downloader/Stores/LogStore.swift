import AppKit
import Foundation
import SwiftUI

@Observable
class LogStore {
    private(set) var entries: [LogEntry] = []
    var searchText: String = ""
    var filterLevel: LogEntry.LogLevel?
    
    var filteredEntries: [LogEntry] {
        entries.filter { entry in
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = filterLevel == nil || entry.level == filterLevel
            return matchesSearch && matchesLevel
        }
    }
    
    func append(_ entry: LogEntry) {
        entries.append(entry)
    }
    
    func clear() {
        entries.removeAll()
    }
    
    func exportToFile() throws -> URL {
        let text = entries.map { "[\($0.timestamp)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("y-downloader-log-\(Date().timeIntervalSince1970).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// Copy all log entries to the system pasteboard.
    @discardableResult
    func copyAll() -> String {
        let text = entries.map { "[\($0.timestamp)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }
}
