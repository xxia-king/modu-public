import SwiftUI
import AppKit

/// 编辑器：用 NSViewRepresentable 包装 NSScrollView+NSTextView，替换 SwiftUI TextEditor。
///
/// 除了等宽编辑、text 双向绑定、onChange 之外，额外暴露源文本位置监听（onScroll）
/// 与外部位置控制（scrollOffset），用于在编辑模式下与预览按内容位置同步滚动。
/// 这是项目首个 AppKit 桥接组件。
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var font: NSFont
    /// 文本变更回调（替代 TextEditor 的 .onChange 逻辑）
    var onChange: (String) -> Void
    /// 外部驱动的目标源文本 UTF-16 偏移（来自预览侧）
    var scrollOffset: Int
    /// 报告自身顶部可见源文本 UTF-16 偏移给上层，用于驱动预览
    var onScroll: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // scrollableTextView() 返回自带 NSScrollView 的可滚动文本视图
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = font
        textView.string = text
        textView.setSelectedRange(selection)
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        // 代码/Markdown 编辑惯例：关闭自动引号、破折号、文本替换，避免 -- 变 em-dash 等
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        // 禁用垂直弹性回弹，避免滚动同步到顶/底时 contentView.bounds.origin 出现负值（视觉超框）
        scrollView.verticalScrollElasticity = .none

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.registerScrollObserver()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coord = context.coordinator
        coord.parent = self

        // 字体更新
        if textView.font != font {
            textView.font = font
        }

        // 外部文本变更（工具栏的 wrapSelection/insertAtLineStart 等改写 $editText）
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            let nextSelection = selection.clamped(toLength: (text as NSString).length)
            textView.setSelectedRange(sel.length == 0 ? nextSelection : sel.clamped(toLength: (text as NSString).length))
            // 外部改写也需触发 onChange（更新 hasUnsavedChanges / documentContent / 预览），
            // 否则工具栏插入后实时预览不会刷新
            onChange(text)
        }

        if textView.selectedRange() != selection {
            textView.setSelectedRange(selection.clamped(toLength: (textView.string as NSString).length))
        }

        // 外部驱动滚动（来自预览侧的源文本位置）
        if coord.lastAppliedOffset != scrollOffset {
            coord.isExternalScroll = true
            coord.applyOffset(scrollOffset)
            coord.lastAppliedOffset = scrollOffset
            DispatchQueue.main.async { coord.isExternalScroll = false }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        /// 程序化滚动期间为 true，屏蔽 boundsDidChange 的回声，防止同步循环
        var isExternalScroll = false
        var lastAppliedOffset: Int?

        init(_ parent: EditorTextView) { self.parent = parent }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func registerScrollObserver() {
            guard let clip = scrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard !isExternalScroll else { return }
            parent.onScroll(currentTopOffset())
        }

        nonisolated func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let tv = textView else { return }
                parent.text = tv.string
                parent.selection = tv.selectedRange()
                parent.onChange(tv.string)
            }
        }

        nonisolated func textViewDidChangeSelection(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let tv = textView else { return }
                parent.selection = tv.selectedRange()
            }
        }

        /// 当前顶部可见文本的 UTF-16 偏移
        func currentTopOffset() -> Int {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return 0 }

            layoutManager.ensureLayout(for: textContainer)
            var visibleRect = textView.visibleRect
            visibleRect.origin.x -= textView.textContainerOrigin.x
            visibleRect.origin.y -= textView.textContainerOrigin.y

            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            guard glyphRange.location < layoutManager.numberOfGlyphs else {
                return (textView.string as NSString).length
            }
            return layoutManager.characterIndexForGlyph(at: glyphRange.location)
        }

        /// 按源文本 UTF-16 偏移程序化滚动
        func applyOffset(_ offset: Int) {
            guard let sv = scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            layoutManager.ensureLayout(for: textContainer)
            let length = (textView.string as NSString).length
            guard length > 0, layoutManager.numberOfGlyphs > 0 else {
                sv.contentView.scroll(to: .zero)
                sv.reflectScrolledClipView(sv.contentView)
                return
            }
            let clamped = min(max(0, offset), max(0, length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clamped)
            let glyphRange = NSRange(location: glyphIndex, length: min(1, layoutManager.numberOfGlyphs - glyphIndex))
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y

            let docHeight = textView.bounds.height
            let visHeight = sv.contentView.bounds.height
            let maxY = max(0, docHeight - visHeight)
            let y = min(max(0, rect.origin.y), maxY)
            sv.contentView.scroll(to: NSPoint(x: 0, y: y))
            sv.reflectScrolledClipView(sv.contentView)
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
