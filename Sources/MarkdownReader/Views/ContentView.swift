import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    
    @State private var sidebarSelection: FileItem?
    @State private var fileListSelection: FileItem?
    @State private var renamingFile: FileItem?
    @State private var renameText: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var fileListWidth: CGFloat = 260
    @State private var splitDragStartWidth: CGFloat?
    
    var body: some View {
        @Bindable var state = appState
        
        mainContent
            .preferredColorScheme(appState.preferredColorScheme)
            .onDrop(of: [.fileURL], delegate: FileDropDelegate(appState: appState))
            .alert("提示", isPresented: .init(get: { appState.errorMessage != nil },
                                              set: { if !$0 { appState.errorMessage = nil } })) {
                Button("确定") { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
            .alert("重命名", isPresented: $showRenameAlert) {
                TextField("文件名", text: $renameText)
                Button("确定", action: confirmRename)
                Button("取消", role: .cancel) {
                    renamingFile = nil
                    renameText = ""
                }
            } message: {
                Text("输入新的文件名")
            }
            .onChange(of: appState.errorMessage) { _, newValue in
                if newValue != nil { }
            }
    }
    
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            // 文件列表 + 阅读器 的双栏布局，支持隐藏文件列表
            fileListAndReader
        }
    }
    
    /// 文件列表 + 阅读器 的双栏布局，支持隐藏文件列表和拖动调整宽度
    private var fileListAndReader: some View {
        Group {
            if appState.isFileListVisible {
                GeometryReader { proxy in
                    let maxFileListWidth = max(180, min(500, proxy.size.width - 400))
                    let clampedFileListWidth = min(max(fileListWidth, 180), maxFileListWidth)
                    
                    HStack(spacing: 0) {
                        fileListContent
                            .frame(width: clampedFileListWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                        
                        splitDivider(maxFileListWidth: maxFileListWidth)
                        
                        readerContent
                            .frame(width: max(proxy.size.width - clampedFileListWidth - 1, 400))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .onAppear {
                        fileListWidth = clampedFileListWidth
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                readerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func splitDivider(maxFileListWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if splitDragStartWidth == nil {
                            splitDragStartWidth = fileListWidth
                        }
                        let startWidth = splitDragStartWidth ?? fileListWidth
                        fileListWidth = min(max(startWidth + value.translation.width, 180), maxFileListWidth)
                    }
                    .onEnded { _ in
                        splitDragStartWidth = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.isSidebarVisible ? .all : .detailOnly },
            set: { appState.isSidebarVisible = ($0 != .detailOnly) }
        )
    }
    
    // MARK: - Sidebar (Left Column)
    
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $sidebarSelection) {
            // Quick access section
            Section("快捷访问") {
                ForEach(appState.sidebarItems) { item in
                    SidebarRow(item: item)
                        .tag(item)
                }
            }
            
            // Recent files section
            if !appState.recentFiles.isEmpty {
                Section("最近打开") {
                    ForEach(appState.recentFiles.prefix(10).map { FileItem(url: $0) }) { item in
                        SidebarRow(item: item)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .onChange(of: sidebarSelection) { _, newValue in
            guard let item = newValue else { return }
            if item.isDirectory {
                appState.currentDirectory = item.url
            } else {
                appState.openFile(url: item.url)
            }
        }
    }
    
    // MARK: - File List (Middle Column)
    
    @ViewBuilder
    private var fileListContent: some View {
        if let dir = appState.currentDirectory {
            VStack(spacing: 0) {
                // Path bar
                PathBar(url: dir)
                
                // File list
                if appState.isLoading {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else if appState.currentFiles.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "没有 Markdown 文件",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("此文件夹中没有 .md 或 .txt 文件")
                    )
                    Spacer()
                } else {
                    List(appState.currentFiles, selection: $fileListSelection) { file in
                        FileListRow(file: file)
                            .tag(file)
                            .contextMenu {
                                Button(action: {
                                    if file.isDirectory {
                                        appState.currentDirectory = file.url
                                    } else {
                                        appState.openFile(url: file.url)
                                    }
                                }) {
                                    Label(file.isDirectory ? "打开文件夹" : "打开", systemImage: "folder")
                                }
                                
                                if !file.isDirectory {
                                    Button(action: {
                                        startRenaming(file)
                                    }) {
                                        Label("重命名", systemImage: "pencil")
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                }) {
                                    Label("在 Finder 中显示", systemImage: "folder")
                                }
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file.url.path, forType: .string)
                                }) {
                                    Label("复制路径", systemImage: "doc.on.doc")
                                }
                                
                                if file.isDirectory {
                                    Button(action: {
                                        appState.currentDirectory = file.url
                                    }) {
                                        Label("设为当前目录", systemImage: "arrow.right.square")
                                    }
                                }
                                
                                Divider()
                                
                                if !file.isDirectory {
                                    Button(role: .destructive, action: {
                                        moveToTrash(url: file.url)
                                    }) {
                                        Label("移到废纸篓", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: fileListSelection) { _, newValue in
                        guard let file = newValue, !file.isDirectory else { return }
                        appState.selectedFile = file
                    }
                    .onChange(of: fileListSelection) { _, newValue in
                        guard let file = newValue, file.isDirectory else { return }
                        appState.currentDirectory = file.url
                        fileListSelection = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                "选择文件夹",
                systemImage: "folder",
                description: Text("从侧边栏或菜单栏选择 Markdown 文件夹")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Reader (Right Column)
    
    @ViewBuilder
    private var readerContent: some View {
        if appState.isLoading {
            ProgressView("正在加载...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.errorMessage, appState.selectedFile == nil {
            ContentUnavailableView(
                "无法加载",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if appState.selectedFile == nil {
            ContentUnavailableView(
                "墨读",
                systemImage: "doc.text",
                description: Text("选择一个文件开始阅读")
            )
        } else {
            ReaderView()
                .environment(appState)
        }
    }
    
    // MARK: - Rename
    
    private func startRenaming(_ file: FileItem) {
        renamingFile = file
        renameText = file.name
        showRenameAlert = true
    }
    
    private func confirmRename() {
        guard let file = renamingFile else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let newURL = file.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        
        do {
            try FileManager.default.moveItem(at: file.url, to: newURL)
            if appState.selectedFile?.url == file.url {
                appState.openFile(url: newURL)
            }
            appState.loadFiles()
        } catch {
            appState.errorMessage = "重命名失败: \(error.localizedDescription)"
        }
        
        renamingFile = nil
        renameText = ""
        showRenameAlert = false
    }
}

// MARK: - Supporting Views

struct SidebarRow: View {
    let item: FileItem
    
    var body: some View {
        Label(item.name, systemImage: item.iconName)
            .lineLimit(1)
            .truncationMode(.tail)
            .badge(item.isDirectory ? nil : Text(item.url.pathExtension.uppercased()))
    }
}

struct FileListRow: View {
    let file: FileItem
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.iconName)
                .foregroundStyle(file.isDirectory ? Color.accentColor : .secondary)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.body)
                    .lineLimit(1)
                
                if let date = file.modificationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !file.isDirectory, let size = file.fileSize {
                Text(formatFileSize(size))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct PathBar: View {
    let url: URL
    @Environment(AppState.self) private var appState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                if let firstSegment {
                    pathButton(firstSegment)
                }
                
                if !overflowSegments.isEmpty {
                    pathChevron
                    
                    Menu {
                        ForEach(overflowSegments) { segment in
                            Button(segment.title) {
                                appState.currentDirectory = segment.url
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("显示上级路径")
                }
                
                ForEach(tailSegments) { segment in
                    pathChevron
                    pathButton(segment)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            
            Spacer()
            
            Button(action: { appState.isFileListVisible = false }) {
                Image(systemName: "sidebar.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("隐藏文件列表")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
    }
    
    private var firstSegment: PathSegment? {
        pathSegments.first
    }
    
    private var overflowSegments: [PathSegment] {
        guard pathSegments.count > 4 else { return [] }
        return Array(pathSegments.dropFirst().dropLast(3))
    }
    
    private var tailSegments: [PathSegment] {
        guard pathSegments.count > 1 else { return [] }
        if pathSegments.count <= 4 {
            return Array(pathSegments.dropFirst())
        }
        return Array(pathSegments.suffix(3))
    }
    
    private var pathChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
    
    private func pathButton(_ segment: PathSegment) -> some View {
        Button(action: { appState.currentDirectory = segment.url }) {
            Text(segment.title)
                .font(.caption)
                .foregroundStyle(segment.url == url ? .primary : Color.accentColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .help(segment.url.path)
    }
    
    private var pathSegments: [PathSegment] {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let currentURL = url.standardizedFileURL
        let homePath = homeURL.path
        let currentPath = currentURL.path
        
        if currentPath == homePath || currentPath.hasPrefix(homePath + "/") {
            var segments = [PathSegment(title: "~", url: homeURL)]
            let relativePath = String(currentPath.dropFirst(homePath.count))
            let components = relativePath.split(separator: "/").map(String.init)
            var runningURL = homeURL
            
            for component in components {
                runningURL.appendPathComponent(component)
                segments.append(PathSegment(title: component, url: runningURL.standardizedFileURL))
            }
            
            return segments
        }
        
        var segments: [PathSegment] = []
        var runningPath = ""
        
        for component in currentURL.pathComponents {
            if component == "/" {
                runningPath = "/"
                segments.append(PathSegment(title: "/", url: URL(fileURLWithPath: runningPath)))
            } else {
                runningPath = URL(fileURLWithPath: runningPath).appendingPathComponent(component).path
                segments.append(PathSegment(title: component, url: URL(fileURLWithPath: runningPath)))
            }
        }
        
        return segments
    }
}

private struct PathSegment: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private func moveToTrash(url: URL) {
    var resultURL: NSURL?
    do {
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
    } catch {
        // 静默失败
    }
}

// MARK: - Drag & Drop Delegate

struct FileDropDelegate: DropDelegate {
    let appState: AppState
    
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
                if let url = url {
                    urls.append(url)
                }
            }
            _ = appState.handleDrop(urls: urls)
        }
        
        return true
    }
}
