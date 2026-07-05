import SwiftUI
@preconcurrency import MarkdownUI

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @State private var scrollTarget: String?
    @State private var editText: String = ""
    @State private var isEditing: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    @State private var savedTextSnapshot: String = ""
    @State private var editSelection: NSRange = NSRange(location: 0, length: 0)
    @State private var activeLiveBlockID: Int?
    @State private var vditorCommand: VditorEditorCommand?
    // 编辑模式：编辑器与预览按源文本 UTF-16 偏移同步
    @State private var editorTargetOffset: Int = 0
    @State private var previewTargetOffset: Int = 0
    @State private var scrollSource: ScrollSource?

    /// 标记当前由哪一端发起滚动，用于防止双向同步循环
    private enum ScrollSource { case editor, preview }

    var body: some View {
        @Bindable var state = appState
        
        VStack(spacing: 0) {
            // Mode toolbar (top)
            readerToolbar
            
            Divider()
            
            // Edit mode formatting toolbar
            if isEditing {
                editFormatToolbar
                Divider()
            }
            
            // Content area
            if isEditing {
                editModeContent
            } else {
                readModeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.selectedFile) { _, _ in
            editText = appState.documentContent
            savedTextSnapshot = appState.documentContent
            hasUnsavedChanges = false
        }
        .onAppear {
            editText = appState.documentContent
            savedTextSnapshot = appState.documentContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
            if isEditing {
                saveFile()
            }
        }
    }
    
    // MARK: - Top Toolbar
    
    private var readerToolbar: some View {
        HStack(spacing: 12) {
            // Mode toggle
            Picker("", selection: $isEditing) {
                Label("阅读", systemImage: "book").tag(false)
                Label("编辑", systemImage: "pencil").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: isEditing) { _, editing in
                if editing {
                    editText = appState.documentContent
                    savedTextSnapshot = appState.documentContent
                    editSelection = NSRange(location: 0, length: 0)
                    activeLiveBlockID = nil
                } else if hasUnsavedChanges {
                    appState.documentContent = editText
                    appState.extractTOC()
                }
            }
            
            Divider()
                .frame(height: 16)
            
            if isEditing {
                // Save button
                Button(action: saveFile) {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasUnsavedChanges)
                
                if hasUnsavedChanges {
                    Text("未保存")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()
                    .frame(height: 16)

                Button(action: { appState.showTableOfContents.toggle() }) {
                    Image(systemName: "sidebar.trailing")
                }
                .buttonStyle(.borderless)
                .help("目录导航")
                
                Spacer()
                
                Toggle("实时预览", isOn: Binding(
                    get: { appState.showLivePreview },
                    set: { appState.showLivePreview = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            } else {
                // Read mode: file list + TOC toggle
                Button(action: { appState.isFileListVisible.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("文件列表")
                
                Button(action: { appState.showTableOfContents.toggle() }) {
                    Image(systemName: "sidebar.trailing")
                }
                .buttonStyle(.borderless)
                .help("目录导航")
                
                Spacer()
                
                Button(action: { appState.reloadCurrentFile() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("重新加载")
                
                if let file = appState.selectedFile {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    // MARK: - Edit Format Toolbar
    
    private var editFormatToolbar: some View {
        HStack(spacing: 4) {
            // Headings
            Menu {
                Button("标题 1") { applyLinePrefix("# ", placeholder: "标题") }
                Button("标题 2") { applyLinePrefix("## ", placeholder: "标题") }
                Button("标题 3") { applyLinePrefix("### ", placeholder: "标题") }
                Button("标题 4") { applyLinePrefix("#### ", placeholder: "标题") }
            } label: {
                ToolbarButton(icon: "textformat.size", label: "标题")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            ToolbarSeparator()
            
            // Bold
            Button(action: { applyWrap(prefix: "**", suffix: "**") }) {
                ToolbarButton(icon: "bold", label: "加粗")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("b", modifiers: .command)
            
            // Italic
            Button(action: { applyWrap(prefix: "*", suffix: "*") }) {
                ToolbarButton(icon: "italic", label: "斜体")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: .command)
            
            // Strikethrough
            Button(action: { applyWrap(prefix: "~~", suffix: "~~") }) {
                ToolbarButton(icon: "strikethrough", label: "删除线")
            }
            .buttonStyle(.borderless)
            
            // Inline code
            Button(action: { applyWrap(prefix: "`", suffix: "`") }) {
                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", label: "行内代码")
            }
            .buttonStyle(.borderless)
            
            ToolbarSeparator()
            
            // Link
            Button(action: insertLink) {
                ToolbarButton(icon: "link", label: "链接")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("k", modifiers: .command)
            
            // Image
            Button(action: insertImage) {
                ToolbarButton(icon: "photo", label: "图片")
            }
            .buttonStyle(.borderless)
            
            ToolbarSeparator()
            
            // Bullet list
            Button(action: { applyLinePrefix("- ", placeholder: "列表项") }) {
                ToolbarButton(icon: "list.bullet", label: "无序列表")
            }
            .buttonStyle(.borderless)
            
            // Numbered list
            Button(action: { applyLinePrefix("1. ", placeholder: "列表项") }) {
                ToolbarButton(icon: "list.number", label: "有序列表")
            }
            .buttonStyle(.borderless)
            
            // Task list
            Button(action: { applyLinePrefix("- [ ] ", placeholder: "任务") }) {
                ToolbarButton(icon: "checklist", label: "任务列表")
            }
            .buttonStyle(.borderless)
            
            ToolbarSeparator()
            
            // Quote
            Button(action: { applyLinePrefix("> ", placeholder: "引用") }) {
                ToolbarButton(icon: "text.quote", label: "引用")
            }
            .buttonStyle(.borderless)
            
            // Code block
            Button(action: insertCodeBlock) {
                ToolbarButton(icon: "curlybraces", label: "代码块")
            }
            .buttonStyle(.borderless)
            
            // Horizontal rule
            Button(action: insertHorizontalRule) {
                ToolbarButton(icon: "minus", label: "分隔线")
            }
            .buttonStyle(.borderless)
            
            // Table
            Button(action: insertTable) {
                ToolbarButton(icon: "tablecells", label: "表格")
            }
            .buttonStyle(.borderless)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
    
    // MARK: - Read Mode
    
    private var readModeContent: some View {
        HSplitView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        documentHeader
                            .padding(.horizontal, 32)
                            .padding(.top, 24)
                            .padding(.bottom, 8)
                        
                        Divider()
                            .padding(.horizontal, 32)
                            .padding(.bottom, 16)
                        
                        Markdown(appState.documentContent)
                            .markdownTheme(
                                .customGitHub(
                                    baseFontSize: appState.readerFontSize.baseFontSize,
                                    wrapsCodeBlocks: appState.wrapCodeBlocks
                                )
                            )
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    self.scrollTarget = nil
                }
            }
            .frame(minWidth: 400)
            
            if appState.showTableOfContents && !appState.tocItems.isEmpty {
                tableOfContents
                    .frame(width: 220)
            }
        }
    }
    
    // MARK: - Edit Mode
    
    private var editModeContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                if appState.showLivePreview {
                    VditorWebEditorView(
                        text: $editText,
                        command: vditorCommand,
                        baseFontSize: appState.readerFontSize.baseFontSize,
                        onChange: applyLiveEditChange
                    )
                } else {
                    sourceEditor
                }

                editStatusBar
            }
            .frame(minWidth: 400)

            if appState.showTableOfContents && !appState.tocItems.isEmpty {
                tableOfContents
                    .frame(width: 220)
            }
        }
    }

    private var sourceEditor: some View {
        EditorTextView(
            text: $editText,
            selection: $editSelection,
            font: .monospacedSystemFont(
                ofSize: appState.readerFontSize.editorFontSize, weight: .regular),
            onChange: { newValue in
                hasUnsavedChanges = (newValue != savedTextSnapshot)
            },
            scrollOffset: editorTargetOffset,
            onScroll: { offset in
                guard scrollSource == nil else { return }
                scrollSource = .editor
                previewTargetOffset = offset
                DispatchQueue.main.async { scrollSource = nil }
            }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Edit Status Bar
    
    private var editStatusBar: some View {
        HStack(spacing: 16) {
            let charCount = editText.count
            let lineCount = editText.components(separatedBy: "\n").count
            let wordCount = editText.split { $0.isWhitespace }.count
            
            Label("\(lineCount) 行", systemImage: "text.alignleft")
            Label("\(wordCount) 词", systemImage: "textformat")
            Label("\(charCount) 字符", systemImage: "character")
            
            Spacer()
            
            if let file = appState.selectedFile {
                Text(file.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
    
    // MARK: - Document Header (Read Mode)
    
    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.documentTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let file = appState.selectedFile {
                HStack(spacing: 16) {
                    Label(file.name, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let date = file.modificationDate {
                        Label(date.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Table of Contents
    
    private var tableOfContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("目录")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { appState.showTableOfContents = false }) {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("隐藏目录")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.tocItems) { item in
                        Button(action: { navigateToTOCItem(item) }) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.secondary.opacity(0.3))
                                    .frame(width: 2)
                                
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.vertical, 4)
                                    .padding(.leading, 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat(item.level - 2) * 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 200, maxWidth: 250)
        .background(.background)
    }
    
    // MARK: - Save
    
    private func saveFile() {
        guard let file = appState.selectedFile else { return }
        
        do {
            try editText.write(to: file.url, atomically: true, encoding: .utf8)
            appState.documentContent = editText
            savedTextSnapshot = editText
            hasUnsavedChanges = false
            appState.extractTOC()
            appState.selectedFile = FileItem(url: file.url)
        } catch {
            appState.errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Edit Helpers

    private func applyLiveEditChange(_ newValue: String) {
        hasUnsavedChanges = (newValue != savedTextSnapshot)
        appState.documentContent = newValue
        appState.extractTOC()
    }

    private func navigateToTOCItem(_ item: TOCItem) {
        if isEditing {
            if appState.showLivePreview {
                vditorCommand = .scrollToHeading(item.title)
            } else {
                editorTargetOffset = sourceOffset(for: item)
            }
        } else {
            scrollTarget = item.anchor
        }
    }

    private func sourceOffset(for item: TOCItem) -> Int {
        let lines = editText.components(separatedBy: .newlines)
        var offset = 0

        for line in lines {
            if headingTitle(in: line, level: item.level) == item.title {
                return offset
            }
            offset += (line as NSString).length + 1
        }

        return 0
    }

    private func headingTitle(in line: String, level: Int) -> String? {
        let marker = String(repeating: "#", count: level) + " "
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(marker) else { return nil }
        return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }

    private func applyWrap(prefix: String, suffix: String, placeholder: String = "文本") {
        if appState.showLivePreview {
            vditorCommand = .wrap(prefix: prefix, suffix: suffix, placeholder: placeholder)
        } else {
            wrapSelection(prefix: prefix, suffix: suffix)
        }
    }

    private func applyLinePrefix(_ prefix: String, placeholder: String) {
        if appState.showLivePreview {
            vditorCommand = .line(prefix: prefix, placeholder: placeholder)
        } else {
            insertAtLineStart(prefix)
        }
    }

    private func applyInsert(_ text: String) {
        if appState.showLivePreview {
            vditorCommand = .insert(text)
        } else {
            insertText(text)
        }
    }
    
    private func wrapSelection(prefix: String, suffix: String) {
        let placeholder = "文本"
        replaceSelection(defaultText: placeholder) { selected in
            "\(prefix)\(selected)\(suffix)"
        }
    }
    
    private func insertAtLineStart(_ prefix: String) {
        let nsText = editText as NSString
        let range = editSelection.clamped(toLength: nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        let selectedLineText = nsText.substring(with: lineRange)
        if selectedLineText.hasPrefix(prefix) {
            return
        }
        editText = nsText.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
        editSelection = NSRange(location: range.location + (prefix as NSString).length, length: range.length)
        applyEditChange()
    }
    
    private func insertLink() {
        if appState.showLivePreview {
            vditorCommand = .wrap(prefix: "[", suffix: "](https://)", placeholder: "链接文字")
        } else {
            replaceSelection(defaultText: "链接文字") { selected in
                "[\(selected)](https://)"
            }
        }
    }
    
    private func insertImage() {
        if appState.showLivePreview {
            vditorCommand = .wrap(prefix: "![", suffix: "](https://)", placeholder: "图片描述")
        } else {
            replaceSelection(defaultText: "图片描述") { selected in
                "![\(selected)](https://)"
            }
        }
    }
    
    private func insertCodeBlock() {
        if appState.showLivePreview {
            vditorCommand = .wrap(prefix: "```\n", suffix: "\n```", placeholder: "代码")
        } else {
            replaceSelection(defaultText: "代码") { selected in
                "```\n\(selected)\n```"
            }
        }
    }
    
    private func insertHorizontalRule() {
        applyInsert("\n\n---\n")
    }
    
    private func insertTable() {
        applyInsert("\n| 列1 | 列2 | 列3 |\n|---|---|---|\n| 内容 | 内容 | 内容 |\n")
    }

    private func replaceSelection(defaultText: String, transform: (String) -> String) {
        let nsText = editText as NSString
        let range = editSelection.clamped(toLength: nsText.length)
        let selected = range.length > 0 ? nsText.substring(with: range) : defaultText
        let replacement = transform(selected)
        editText = nsText.replacingCharacters(in: range, with: replacement)
        let replacementLength = (replacement as NSString).length
        if range.length > 0 {
            editSelection = NSRange(location: range.location, length: replacementLength)
        } else {
            let cursorLocation = range.location + replacementLength
            editSelection = NSRange(location: cursorLocation, length: 0)
        }
        applyEditChange()
    }

    private func insertText(_ text: String) {
        let nsText = editText as NSString
        let range = editSelection.clamped(toLength: nsText.length)
        editText = nsText.replacingCharacters(in: range, with: text)
        editSelection = NSRange(location: range.location + (text as NSString).length, length: 0)
        applyEditChange()
    }

    private func applyEditChange() {
        hasUnsavedChanges = (editText != savedTextSnapshot)
        if appState.showLivePreview {
            appState.documentContent = editText
            appState.extractTOC()
        }
    }
}

private extension NSRange {
    func clamped(toLength length: Int) -> NSRange {
        let location = min(max(0, self.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, self.length), maxLength))
    }
}

// MARK: - Toolbar UI Components

private struct ToolbarButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
        }
        .help(label)
    }
}

private struct ToolbarSeparator: View {
    var body: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 2)
    }
}

// MARK: - Custom Markdown Theme

private let customText = Color(
    light: Color(rgba: 0x1F1F_1FFF), dark: Color(rgba: 0xE8E8_E8FF)
)
private let customSecondaryText = Color(
    light: Color(rgba: 0x656D_76FF), dark: Color(rgba: 0x8B94_9EFF)
)
private let customBackground = Color(
    light: Color(rgba: 0xFFFF_FFFF), dark: Color(rgba: 0x0D11_17FF)
)
private let customSecondaryBackground = Color(
    light: Color(rgba: 0xF6F8_FAFF), dark: Color(rgba: 0x161B_22FF)
)
private let customLink = Color(
    light: Color(rgba: 0x0969_DAFF), dark: Color(rgba: 0x4493_F8FF)
)
private let customBorder = Color(
    light: Color(rgba: 0xD0D7_DEFF), dark: Color(rgba: 0x3D44_4DFF)
)
private let customDivider = Color(
    light: Color(rgba: 0xD8DE_E4FF), dark: Color(rgba: 0x3338_40FF)
)

@MainActor
extension MarkdownUI.Theme {
    static func customGitHub(baseFontSize: Double = 16, wrapsCodeBlocks: Bool = true) -> MarkdownUI.Theme {
        MarkdownUI.Theme()
            .text {
            ForegroundColor(customText)
            BackgroundColor(customBackground)
            FontSize(baseFontSize)
            }
            .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            BackgroundColor(customSecondaryBackground)
            }
            .strong {
            FontWeight(.semibold)
            }
            .link {
            ForegroundColor(customLink)
            }
            .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .markdownMargin(top: 32, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(2.0))
                    }
                Divider().overlay(customDivider)
            }
            }
            .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .markdownMargin(top: 24, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
                Divider().overlay(customDivider)
            }
            }
            .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
            }
            .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.0))
                }
            }
            .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.35))
                .markdownMargin(top: 0, bottom: 16)
            }
            .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(customLink.opacity(0.4))
                    .relativeFrame(width: .em(0.25))
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(customSecondaryText)
                    }
                    .relativePadding(.horizontal, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 8, bottom: 8)
            }
            .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                if let language = configuration.language, !language.isEmpty {
                    HStack {
                        Text(language)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Spacer()
                        
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(configuration.content, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("复制代码")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(customDivider.opacity(0.3))
                }
                
                if wrapsCodeBlocks {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.225))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal) {
                        configuration.label
                            .fixedSize(horizontal: false, vertical: true)
                            .relativeLineSpacing(.em(0.225))
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(0.85))
                            }
                            .padding(16)
                    }
                }
            }
            .background(customSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(customBorder, lineWidth: 0.5)
            )
            .markdownMargin(top: 12, bottom: 12)
            }
            .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
            }
            .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor, Color.clear)
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
            }
            .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: customBorder))
                .markdownTableBackgroundStyle(
                    .alternatingRows(customBackground, customSecondaryBackground)
                )
                .markdownMargin(top: 0, bottom: 16)
            }
            .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .relativeLineSpacing(.em(0.25))
            }
            .thematicBreak {
            Divider()
                .relativeFrame(height: .em(0.25))
                .overlay(customDivider)
                .markdownMargin(top: 24, bottom: 24)
            }
    }
}
