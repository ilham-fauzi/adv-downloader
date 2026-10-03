import Foundation
import SwiftUI

enum UpdateChannel: String, CaseIterable, Codable {
    case stable, nightly, master
}

enum AppMode: String, CaseIterable, Codable {
    case simple, advanced
}

@Observable
class SettingsStore {
    var ytdlpPath: String {
        get {
            access(keyPath: \.ytdlpPath)
            return UserDefaults.standard.string(forKey: "ytdlpPath") ?? ""
        }
        set {
            withMutation(keyPath: \.ytdlpPath) { UserDefaults.standard.set(newValue, forKey: "ytdlpPath") }
        }
    }
    
    var ffmpegPath: String {
        get {
            access(keyPath: \.ffmpegPath)
            return UserDefaults.standard.string(forKey: "ffmpegPath") ?? ""
        }
        set {
            withMutation(keyPath: \.ffmpegPath) { UserDefaults.standard.set(newValue, forKey: "ffmpegPath") }
        }
    }
    
    var defaultOutputDir: String {
        get {
            access(keyPath: \.defaultOutputDir)
            return UserDefaults.standard.string(forKey: "defaultOutputDir") ?? (NSHomeDirectory() + "/Downloads/Y-Downloader")
        }
        set {
            withMutation(keyPath: \.defaultOutputDir) { UserDefaults.standard.set(newValue, forKey: "defaultOutputDir") }
        }
    }
    
    var defaultPresetId: UUID? {
        get { 
            access(keyPath: \.defaultPresetId)
            if let str = UserDefaults.standard.string(forKey: "defaultPresetId") {
                return UUID(uuidString: str)
            }
            return nil
        }
        set {
            withMutation(keyPath: \.defaultPresetId) { UserDefaults.standard.set(newValue?.uuidString, forKey: "defaultPresetId") }
        }
    }
    
    var maxConcurrentDownloads: Int {
        get {
            access(keyPath: \.maxConcurrentDownloads)
            return UserDefaults.standard.integer(forKey: "maxConcurrentDownloads") == 0 ? 3 : UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
        }
        set {
            withMutation(keyPath: \.maxConcurrentDownloads) { UserDefaults.standard.set(newValue, forKey: "maxConcurrentDownloads") }
        }
    }
    
    var autoStartQueue: Bool {
        get {
            access(keyPath: \.autoStartQueue)
            return UserDefaults.standard.object(forKey: "autoStartQueue") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.autoStartQueue) { UserDefaults.standard.set(newValue, forKey: "autoStartQueue") }
        }
    }
    
    var updateChannel: UpdateChannel {
        get { 
            access(keyPath: \.updateChannel)
            if let str = UserDefaults.standard.string(forKey: "updateChannel"), let channel = UpdateChannel(rawValue: str) {
                return channel
            }
            return .stable
        }
        set {
            withMutation(keyPath: \.updateChannel) { UserDefaults.standard.set(newValue.rawValue, forKey: "updateChannel") }
        }
    }
    
    var autoUpdateYtdlp: Bool {
        get {
            access(keyPath: \.autoUpdateYtdlp)
            return UserDefaults.standard.object(forKey: "autoUpdateYtdlp") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.autoUpdateYtdlp) { UserDefaults.standard.set(newValue, forKey: "autoUpdateYtdlp") }
        }
    }
    
    var appMode: AppMode {
        get {
            access(keyPath: \.appMode)
            if let str = UserDefaults.standard.string(forKey: "appMode"), let mode = AppMode(rawValue: str) {
                return mode
            }
            return .simple
        }
        set {
            withMutation(keyPath: \.appMode) { UserDefaults.standard.set(newValue.rawValue, forKey: "appMode") }
        }
    }
    
    var clipboardMonitoring: Bool {
        get {
            access(keyPath: \.clipboardMonitoring)
            return UserDefaults.standard.object(forKey: "clipboardMonitoring") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.clipboardMonitoring) { UserDefaults.standard.set(newValue, forKey: "clipboardMonitoring") }
        }
    }
    
    var showMenuBarExtra: Bool {
        get {
            access(keyPath: \.showMenuBarExtra)
            return UserDefaults.standard.object(forKey: "showMenuBarExtra") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showMenuBarExtra) { UserDefaults.standard.set(newValue, forKey: "showMenuBarExtra") }
        }
    }
    
    var showNotifications: Bool {
        get {
            access(keyPath: \.showNotifications)
            return UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showNotifications) { UserDefaults.standard.set(newValue, forKey: "showNotifications") }
        }
    }
    
    /// Show the video thumbnail in the video info box. Stored property so SwiftUI
    /// observes changes immediately; persisted to UserDefaults.
    var showThumbnail: Bool = UserDefaults.standard.object(forKey: "showThumbnail") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showThumbnail, forKey: "showThumbnail") }
    }

    /// Experimental: show the Browser tab.
    var showBrowserTab: Bool = UserDefaults.standard.object(forKey: "showBrowserTab") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBrowserTab, forKey: "showBrowserTab") }
    }

    var appearance: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    var defaultOutputTemplate: String {
        get {
            access(keyPath: \.defaultOutputTemplate)
            return UserDefaults.standard.string(forKey: "defaultOutputTemplate") ?? "%(title)s [%(id)s].%(ext)s"
        }
        set {
            withMutation(keyPath: \.defaultOutputTemplate) { UserDefaults.standard.set(newValue, forKey: "defaultOutputTemplate") }
        }
    }
}
