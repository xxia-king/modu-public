import SwiftUI

@main
struct MarkdownReaderApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    appState.openExternalURL(url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("打开文件...") {
                    appState.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("打开文件夹...") {
                    appState.openFolderPanel()
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
                
                Divider()
                
                Button("保存") {
                    NotificationCenter.default.post(name: .saveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            
            // View menu
            CommandMenu("显示") {
                @Bindable var state = appState
                
                Toggle(isOn: $state.isSidebarVisible) {
                    Text("侧边栏")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Toggle(isOn: $state.isFileListVisible) {
                    Text("文件列表")
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                
                Toggle(isOn: $state.showTableOfContents) {
                    Text("目录导航")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                
                Divider()
                
                Picker("主题", selection: $state.selectedTheme) {
                    ForEach(ThemeOption.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme)
                    }
                }
            }
        }
        
        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
