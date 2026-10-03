import SwiftUI
import AppKit

/// In-window settings from the design: folder, appearance, simultaneous downloads.
struct SettingsModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(SSHTunnelManager.self) private var tunnel
    @State private var showVPNSetup = false

    var body: some View {
        @Bindable var s = settings
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Close settings")
            }
            .padding(.leading, 24).padding(.trailing, 14).padding(.top, 16)

            VStack(alignment: .leading, spacing: 22) {
                field("Download folder") {
                    HStack(spacing: 8) {
                        Label(displayPath, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        Button("Change…", action: chooseFolder).buttonStyle(SecondaryButtonStyle(height: 44))
                    }
                }

                field("Appearance") {
                    Picker("Appearance", selection: $s.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simultaneous downloads").font(.system(size: 14, weight: .semibold))
                        Text("How many files download at the same time. Others wait in the queue.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 0)
                    Stepper(value: $s.maxConcurrentDownloads, in: 1...5) {
                        Text("\(settings.maxConcurrentDownloads)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                    }
                    .accessibilityLabel("Simultaneous downloads")
                }

                Toggle(isOn: $s.showThumbnail) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show video thumbnail").font(.system(size: 14, weight: .semibold))
                        Text("Turn off to hide the preview image and avoid loading it.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                }
                .toggleStyle(.switch)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VPN (SSH tunnel)").font(.system(size: 14, weight: .semibold))
                        Text("Send downloads through your own server. Switch it on from the VPN button in the toolbar.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 0)
                    Button("Set up…") { showVPNSetup = true }.buttonStyle(SecondaryButtonStyle(height: 36))
                }

                Toggle(isOn: $s.showNotifications) {
                    Text("Notify me when a download finishes").font(.system(size: 14, weight: .semibold))
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(height: 40))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 480)
        .background(Theme.elevated)
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(isPresented: $showVPNSetup) {
            VStack(spacing: 0) {
                VPNSettingsView()
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { showVPNSetup = false }
                        .buttonStyle(PrimaryButtonStyle(height: 40))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            }
            .environment(tunnel)
            .frame(width: 520, height: 640)
        }
    }

    private var displayPath: String {
        (settings.defaultOutputDir as NSString).abbreviatingWithTildeInPath
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultOutputDir = url.path
            appState.outputDirectory = url.path
        }
    }
}
