import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
            
            appearanceSettings
                .tabItem {
                    Label("外观", systemImage: "paintbrush")
                }
            
            aboutSettings
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
    
    // MARK: - General
    
    private var generalSettings: some View {
        @Bindable var state = appState
        
        return Form {
            Section("文件管理") {
                Toggle("启动时自动打开上次的文件夹", isOn: $state.openLastFolderOnLaunch)
                Toggle("自动重新加载已更改的文件", isOn: $state.autoReloadChangedFiles)
                Picker("默认编码", selection: $state.defaultEncoding) {
                    ForEach(FileEncodingOption.allCases) { encoding in
                        Text(encoding.displayName).tag(encoding)
                    }
                }
            }
            
            Section("导航") {
                Picker("默认视图", selection: $state.defaultView) {
                    ForEach(DefaultViewOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Appearance
    
    private var appearanceSettings: some View {
        @Bindable var state = appState
        
        return Form {
            Section("主题") {
                Picker("配色方案", selection: $state.selectedTheme) {
                    ForEach(ThemeOption.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("阅读") {
                Picker("字体大小", selection: $state.readerFontSize) {
                    ForEach(ReaderFontSizeOption.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                
                Toggle("显示行号", isOn: $state.showLineNumbers)
                Toggle("代码块自动换行", isOn: $state.wrapCodeBlocks)
                Toggle("图片自适应宽度", isOn: $state.fitImagesToWidth)
            }
        }
        .padding()
    }
    
    // MARK: - About
    
    private var aboutSettings: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            
            Text("墨读")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("版本 1.0.10")
                .foregroundStyle(.secondary)
            
            Text("优雅的 Markdown 文档阅读器\n支持语法高亮、目录导航、多主题")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.caption)
            
            Text("© 2026 浙江嘉瑞成律师事务所 · 金莉珊律师")
                .foregroundStyle(.tertiary)
                .font(.caption2)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
