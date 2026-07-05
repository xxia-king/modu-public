import SwiftUI
import UniformTypeIdentifiers

/// Global application state
@MainActor
@Observable
final class AppState {
    // MARK: - Navigation
    
    /// Current directory being browsed
    var currentDirectory: URL? {
        didSet { loadFiles() }
    }
    
    /// Files in the current directory
    var currentFiles: [FileItem] = []
    
    /// Currently selected file
    var selectedFile: FileItem? {
        didSet { loadSelectedFile() }
    }
    
    /// Currently loaded document content
    var documentContent: String = ""
    
    /// Document title (extracted from first H1)
    var documentTitle: String = ""
    
    // MARK: - Sidebar
    
    var isSidebarVisible: Bool = true
    var isFileListVisible: Bool = true
    var showTableOfContents: Bool = true
    var showLivePreview: Bool = true
    
    /// Root items in the sidebar (favorites + volumes)
    var sidebarItems: [FileItem] = []
    
    /// Recently opened files
    var recentFiles: [URL] = []
    
    // MARK: - Theme
    
    var selectedTheme: ThemeOption = .auto {
        didSet { saveSetting(selectedTheme.rawValue, forKey: SettingsKey.selectedTheme) }
    }
    var preferredColorScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
    var openLastFolderOnLaunch: Bool = true {
        didSet { saveSetting(openLastFolderOnLaunch, forKey: SettingsKey.openLastFolderOnLaunch) }
    }
    var autoReloadChangedFiles: Bool = true {
        didSet { saveSetting(autoReloadChangedFiles, forKey: SettingsKey.autoReloadChangedFiles) }
    }
    var defaultEncoding: FileEncodingOption = .utf8 {
        didSet { saveSetting(defaultEncoding.rawValue, forKey: SettingsKey.defaultEncoding) }
    }
    var defaultView: DefaultViewOption = .full {
        didSet {
            saveSetting(defaultView.rawValue, forKey: SettingsKey.defaultView)
            applyDefaultView()
        }
    }
    var readerFontSize: ReaderFontSizeOption = .medium {
        didSet { saveSetting(readerFontSize.rawValue, forKey: SettingsKey.readerFontSize) }
    }
    var showLineNumbers: Bool = false {
        didSet { saveSetting(showLineNumbers, forKey: SettingsKey.showLineNumbers) }
    }
    var wrapCodeBlocks: Bool = true {
        didSet { saveSetting(wrapCodeBlocks, forKey: SettingsKey.wrapCodeBlocks) }
    }
    var fitImagesToWidth: Bool = true {
        didSet { saveSetting(fitImagesToWidth, forKey: SettingsKey.fitImagesToWidth) }
    }
    
    // MARK: - State
    
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Table of Contents
    
    var tocItems: [TOCItem] = []
    
    init() {
        loadSettings()
        loadRecentFiles()
        setupSidebar()
        openLastFolderIfNeeded()
    }
    
    // MARK: - File Operations
    
    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择 Markdown 文件"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url: url)
    }
    
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.title = "选择文件夹"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentDirectory = url
        addRecentFolder(url)
    }
    
    func openFile(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "文件不存在: \(url.lastPathComponent)"
            return
        }
        
        selectedFile = FileItem(url: url)
        addRecentFile(url)
        loadFileContent(url: url)
    }
    
    func openExternalURL(_ url: URL) {
        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            errorMessage = "文件不存在: \(fileURL.lastPathComponent)"
            return
        }
        
        if isDir.boolValue {
            currentDirectory = fileURL
            isFileListVisible = true
            addRecentFolder(fileURL)
            return
        }
        
        let ext = fileURL.pathExtension.lowercased()
        guard ["md", "markdown", "mdown", "txt"].contains(ext) else {
            errorMessage = "不支持的文件类型: \(fileURL.lastPathComponent)"
            return
        }
        
        currentDirectory = fileURL.deletingLastPathComponent()
        // 不强制显示文件列表：尊重当前 defaultView（如「仅阅读器」模式下，从 Finder 打开文件应保持纯阅读）
        openFile(url: fileURL)
    }
    
    private func loadFileContent(url: URL) {
        isLoading = true
        errorMessage = nil
        
        do {
            let data = try Data(contentsOf: url)
            
            if let content = decode(data) {
                documentContent = content
            } else {
                errorMessage = "无法解码文件内容（不支持的编码格式）"
                documentContent = ""
            }
            
            extractDocumentTitle()
            extractTOC()
        } catch {
            errorMessage = "读取文件失败: \(error.localizedDescription)"
            documentContent = ""
        }
        
        isLoading = false
    }
    
    private func loadSelectedFile() {
        guard let file = selectedFile else {
            documentContent = ""
            documentTitle = ""
            tocItems = []
            return
        }
        loadFileContent(url: file.url)
    }
    
    // MARK: - Document Metadata
    
    private func extractDocumentTitle() {
        let lines = documentContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                documentTitle = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return
            }
        }
        documentTitle = selectedFile?.name ?? "Markdown 预览"
    }
    
    func extractTOC() {
        tocItems = []
        let lines = documentContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                tocItems.append(TOCItem(level: 2, title: title, anchor: title))
            } else if trimmed.hasPrefix("### ") {
                let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                tocItems.append(TOCItem(level: 3, title: title, anchor: title))
            } else if trimmed.hasPrefix("#### ") {
                let title = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                tocItems.append(TOCItem(level: 4, title: title, anchor: title))
            }
        }
    }
    
    // MARK: - Directory Browsing
    
    func loadFiles() {
        guard let dir = currentDirectory else {
            currentFiles = []
            return
        }
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            currentFiles = urls
                .filter { url in
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
                    if isDir.boolValue { return true }
                    let ext = url.pathExtension.lowercased()
                    return ["md", "markdown", "mdown", "txt"].contains(ext)
                }
                .map { FileItem(url: $0) }
                .sorted { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory && !b.isDirectory
                    }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
        } catch {
            errorMessage = "读取目录失败: \(error.localizedDescription)"
            currentFiles = []
        }
    }
    
    // MARK: - Sidebar Setup
    
    private func setupSidebar() {
        var items: [FileItem] = []
        
        // Desktop & Documents shortcuts
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            items.append(FileItem(url: desktop))
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            items.append(FileItem(url: documents))
        }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(FileItem(url: downloads))
        }
        
        // Recent folders
        for url in recentFiles where isDirectoryURL(url) {
            items.append(FileItem(url: url))
        }
        
        sidebarItems = items
    }

    private func openLastFolderIfNeeded() {
        guard openLastFolderOnLaunch,
              let folder = recentFiles.first(where: { isDirectoryURL($0) }) else { return }
        currentDirectory = folder
    }
    
    // MARK: - Recent Files
    
    private var recentFilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("墨读")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("recent.json")
    }
    
    private func loadRecentFiles() {
        guard let data = try? Data(contentsOf: recentFilesURL),
              let urls = try? JSONDecoder().decode([String].self, from: data) else { return }
        recentFiles = urls.compactMap { URL(fileURLWithPath: $0) }
    }
    
    private func saveRecentFiles() {
        let paths = recentFiles.prefix(20).map { $0.path }
        guard let data = try? JSONEncoder().encode(Array(paths)) else { return }
        try? data.write(to: recentFilesURL, options: .atomic)
    }
    
    private func addRecentFile(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 20 { recentFiles = Array(recentFiles.prefix(20)) }
        saveRecentFiles()
    }
    
    private func addRecentFolder(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        saveRecentFiles()
        setupSidebar()
    }
    
    // MARK: - Drag & Drop
    
    func handleDrop(urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        
        if isDir.boolValue {
            currentDirectory = url
        } else {
            let ext = url.pathExtension.lowercased()
            guard ["md", "markdown", "mdown", "txt"].contains(ext) else { return false }
            openFile(url: url)
        }
        return true
    }
    
    // MARK: - Quick Actions
    
    func reloadCurrentFile() {
        guard let file = selectedFile else { return }
        loadFileContent(url: file.url)
    }
    
    func increaseFontSize() {
        guard let next = readerFontSize.larger else { return }
        readerFontSize = next
    }
    
    func decreaseFontSize() {
        guard let next = readerFontSize.smaller else { return }
        readerFontSize = next
    }
    
    private func decode(_ data: Data) -> String? {
        for encoding in defaultEncoding.encodingOrder {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }
        return nil
    }
    
    private func applyDefaultView() {
        switch defaultView {
        case .full:
            isSidebarVisible = true
            isFileListVisible = true
        case .fileListAndReader:
            isSidebarVisible = false
            isFileListVisible = true
        case .readerOnly:
            isSidebarVisible = false
            isFileListVisible = false
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let theme = defaults.string(forKey: SettingsKey.selectedTheme),
           let value = ThemeOption(rawValue: theme) {
            selectedTheme = value
        }
        if let encoding = defaults.string(forKey: SettingsKey.defaultEncoding),
           let value = FileEncodingOption(rawValue: encoding) {
            defaultEncoding = value
        }
        if let view = defaults.string(forKey: SettingsKey.defaultView),
           let value = DefaultViewOption(rawValue: view) {
            defaultView = value
        }
        if let size = defaults.string(forKey: SettingsKey.readerFontSize),
           let value = ReaderFontSizeOption(rawValue: size) {
            readerFontSize = value
        }
        
        openLastFolderOnLaunch = defaults.object(forKey: SettingsKey.openLastFolderOnLaunch) as? Bool ?? true
        autoReloadChangedFiles = defaults.object(forKey: SettingsKey.autoReloadChangedFiles) as? Bool ?? true
        showLineNumbers = defaults.object(forKey: SettingsKey.showLineNumbers) as? Bool ?? false
        wrapCodeBlocks = defaults.object(forKey: SettingsKey.wrapCodeBlocks) as? Bool ?? true
        fitImagesToWidth = defaults.object(forKey: SettingsKey.fitImagesToWidth) as? Bool ?? true
    }
    
    private func saveSetting(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    private func isDirectoryURL(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - Supporting Types

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    
    var name: String {
        url.lastPathComponent
    }
    
    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    
    var iconName: String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown": return "doc.text"
        case "txt": return "doc.plaintext"
        default: return "doc"
        }
    }
    
    var modificationDate: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    
    var fileSize: Int64? {
        guard !isDirectory else { return nil }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { return Int64(size) }; return nil
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

struct TOCItem: Identifiable {
    let id = UUID()
    let level: Int
    let title: String
    let anchor: String
}

enum ThemeOption: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "circle.righthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

enum FileEncodingOption: String, CaseIterable, Identifiable {
    case utf8
    case utf16
    case auto
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .auto: return "自动检测"
        }
    }
    
    var encodingOrder: [String.Encoding] {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        
        switch self {
        case .utf8:
            return [.utf8, .utf16, .ascii, .isoLatin1, gb18030]
        case .utf16:
            return [.utf16, .utf8, .ascii, .isoLatin1, gb18030]
        case .auto:
            return [.utf8, .utf16, gb18030, .ascii, .isoLatin1]
        }
    }
}

enum DefaultViewOption: String, CaseIterable, Identifiable {
    case full
    case fileListAndReader
    case readerOnly
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .full: return "侧边栏 + 文件列表 + 阅读器"
        case .fileListAndReader: return "文件列表 + 阅读器"
        case .readerOnly: return "仅阅读器"
        }
    }
}

enum ReaderFontSizeOption: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
    
    var baseFontSize: Double {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
    
    var editorFontSize: Double {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 16
        }
    }
    
    var larger: ReaderFontSizeOption? {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return nil
        }
    }
    
    var smaller: ReaderFontSizeOption? {
        switch self {
        case .small: return nil
        case .medium: return .small
        case .large: return .medium
        }
    }
}

private enum SettingsKey {
    static let selectedTheme = "selectedTheme"
    static let openLastFolderOnLaunch = "openLastFolderOnLaunch"
    static let autoReloadChangedFiles = "autoReloadChangedFiles"
    static let defaultEncoding = "defaultEncoding"
    static let defaultView = "defaultView"
    static let readerFontSize = "readerFontSize"
    static let showLineNumbers = "showLineNumbers"
    static let wrapCodeBlocks = "wrapCodeBlocks"
    static let fitImagesToWidth = "fitImagesToWidth"
}
