import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(QueueManager.self) private var queueManager
    @Environment(CommandBuilder.self) private var commandBuilder
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(LogStore.self) private var logStore
    @Environment(PresetManager.self) private var presetManager
    
    var body: some View {
        @Bindable var state = appState
        
        Group {
            if appState.section == .browser && settingsStore.showBrowserTab {
                BrowserView()
            } else if appState.mode == .simple {
                SimpleRootView()
            } else {
                advancedBody
            }
        }
        .toolbar {
            if settingsStore.showBrowserTab {
                ToolbarItem(placement: .navigation) {
                    Picker("Section", selection: $state.section) {
                        Text("Downloader").tag(AppSection.downloader)
                        Text("Browser (Beta)").tag(AppSection.browser)
                    }
                    .pickerStyle(.segmented)
                }
            }
            ToolbarItem(placement: .automatic) { VPNToolbarButton() }
            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $state.mode) {
                    Text("Simple").tag(AppMode.simple)
                    Text("Advanced").tag(AppMode.advanced)
                }
                .pickerStyle(.segmented)
            }
        }
        .onChange(of: appState.mode) { _, mode in settingsStore.appMode = mode }
        .sheet(isPresented: $state.showSetupAssistant) {
            SetupAssistantSheet()
        }
        .task {
            let status = await DependencyChecker.check()
            if !status.isReady { appState.showSetupAssistant = true }
        }
    }

    @ViewBuilder
    private var advancedBody: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                URLInputView()
                    .padding()
                
                Divider()
                
                if appState.mode == .advanced, appState.listing != nil {
                    ListingView(embedded: true)
                        .padding(.horizontal)
                } else if appState.mode == .advanced {
                    TabView(selection: $state.selectedTab) {
                        FormatTabView()
                            .tabItem { Text("Format") }
                            .tag(OptionsTab.format)
                        
                        PostProcessingTabView()
                            .tabItem { Text("Post-Processing") }
                            .tag(OptionsTab.postProcessing)
                        
                        SubtitlesTabView()
                            .tabItem { Text("Subtitles") }
                            .tag(OptionsTab.subtitles)
                        
                        NetworkTabView()
                            .tabItem { Text("Network") }
                            .tag(OptionsTab.network)
                        
                        FilesystemTabView()
                            .tabItem { Text("Filesystem") }
                            .tag(OptionsTab.filesystem)
                        
                        AdvancedTabView()
                            .tabItem { Text("Advanced") }
                            .tag(OptionsTab.advanced)
                    }
                    .padding()
                } else {
                    Spacer()
                }
                
                Divider()
                
                CLIPreviewView()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        guard !appState.currentURL.isEmpty else { return }
                        queueManager.enqueue(
                            url: appState.currentURL,
                            options: appState.downloadOptions,
                            outputDir: appState.outputDirectory,
                            videoInfo: appState.currentVideoInfo
                        )
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                }
            }
        }
    }
}
