import AppKit
import SwiftUI
@preconcurrency import MarkdownUI

/// Markdown 预览滚动容器。
///
/// 这里故意不再使用“全文滚动百分比”同步。Markdown 源文本和渲染结果的高度不是同一个坐标系，
/// 百分比同步遇到标题、列表、代码块、表格时会系统性错位。此容器按 Markdown 块记录源文本 UTF-16
/// 偏移和预览真实 y 坐标，在两边滚动时用内容位置互相定位。
struct PreviewScrollView: NSViewRepresentable {
    let blocks: [MarkdownSyncBlock]
    var baseFontSize: Double
    var wrapsCodeBlocks: Bool
    /// 外部驱动的目标源文本 UTF-16 偏移（来自编辑器侧）
    var scrollOffset: Int
    /// 报告预览顶部对应的源文本 UTF-16 偏移给上层，用于驱动编辑器
    var onScroll: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MappedPreviewScrollView {
        let scrollView = MappedPreviewScrollView()
        context.coordinator.scrollView = scrollView
        context.coordinator.registerScrollObserver()
        return scrollView
    }

    func updateNSView(_ scrollView: MappedPreviewScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        let changed = scrollView.updateBlocks(
            blocks,
            baseFontSize: baseFontSize,
            wrapsCodeBlocks: wrapsCodeBlocks
        )
        if changed {
            coord.lastAppliedOffset = nil
        }

        if coord.lastAppliedOffset != scrollOffset {
            coord.isExternalScroll = true
            scrollView.applyOffset(scrollOffset)
            coord.lastAppliedOffset = scrollOffset
            DispatchQueue.main.async { coord.isExternalScroll = false }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PreviewScrollView
        weak var scrollView: MappedPreviewScrollView?
        var isExternalScroll = false
        var lastAppliedOffset: Int?

        init(_ parent: PreviewScrollView) { self.parent = parent }

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
            guard !isExternalScroll, let scrollView else { return }
            parent.onScroll(scrollView.currentOffset())
        }
    }
}

@MainActor
final class MappedPreviewScrollView: NSScrollView {
    private let documentContainer = FlippedDocumentView()
    private var blockHosts: [BlockHost] = []
    private var signature: [BlockSignature] = []
    private var currentBaseFontSize: Double = 16
    private var currentWrapsCodeBlocks: Bool = true
    private var lastLayoutWidth: CGFloat = 0
    private let horizontalPadding: CGFloat = 24
    private let topPadding: CGFloat = 16
    private let bottomPadding: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        documentView = documentContainer
        contentView.postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layoutBlocks()
    }

    func updateBlocks(
        _ blocks: [MarkdownSyncBlock],
        baseFontSize: Double,
        wrapsCodeBlocks: Bool
    ) -> Bool {
        currentBaseFontSize = baseFontSize
        currentWrapsCodeBlocks = wrapsCodeBlocks
        let nextSignature = blocks.map { BlockSignature(block: $0, baseFontSize: baseFontSize, wrapsCodeBlocks: wrapsCodeBlocks) }
        let changed = nextSignature != signature
        guard changed else {
            layoutBlocks()
            return false
        }

        blockHosts.forEach { $0.host.removeFromSuperview() }
        blockHosts = blocks.map { block in
            let host = NSHostingView(rootView: AnyView(EmptyView()))
            host.isFlipped = true
            documentContainer.addSubview(host)
            return BlockHost(block: block, host: host, rect: .zero)
        }
        signature = nextSignature
        lastLayoutWidth = 0
        layoutBlocks()
        return true
    }

    func applyOffset(_ offset: Int) {
        layoutBlocks()
        let y = yPosition(for: offset)
        let maxY = max(0, documentContainer.bounds.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        reflectScrolledClipView(contentView)
    }

    func currentOffset() -> Int {
        layoutBlocks()
        return sourceOffset(forY: contentView.bounds.origin.y)
    }

    private func layoutBlocks() {
        let width = max(1, contentView.bounds.width)
        let needsRootUpdate = abs(width - lastLayoutWidth) > 0.5
        if needsRootUpdate {
            lastLayoutWidth = width
        }
        var y = topPadding

        for index in blockHosts.indices {
            let host = blockHosts[index].host
            if needsRootUpdate {
                host.rootView = blockView(for: blockHosts[index].block, width: width)
            }
            host.frame = NSRect(x: 0, y: y, width: width, height: 10)
            host.layoutSubtreeIfNeeded()
            let fittingHeight = max(1, host.fittingSize.height)
            let rect = NSRect(x: 0, y: y, width: width, height: fittingHeight)
            host.frame = rect
            blockHosts[index].rect = rect
            y += fittingHeight
        }

        let height = max(contentView.bounds.height, y + bottomPadding)
        documentContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func blockView(for block: MarkdownSyncBlock, width: CGFloat) -> AnyView {
        AnyView(
            Markdown(block.markdown)
                .markdownTheme(
                    .customGitHub(
                        baseFontSize: currentBaseFontSize,
                        wrapsCodeBlocks: currentWrapsCodeBlocks
                    )
                )
                .padding(.horizontal, horizontalPadding)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func yPosition(for offset: Int) -> CGFloat {
        guard !blockHosts.isEmpty else { return 0 }
        let clampedOffset = min(max(offset, blockHosts.first?.block.startOffset ?? 0), blockHosts.last?.block.endOffset ?? 0)

        for host in blockHosts {
            if clampedOffset <= host.block.endOffset {
                let progress = CGFloat(clampedOffset - host.block.startOffset) / CGFloat(host.block.length)
                return host.rect.minY + progress * host.rect.height
            }
        }
        return blockHosts.last?.rect.minY ?? 0
    }

    private func sourceOffset(forY y: CGFloat) -> Int {
        guard !blockHosts.isEmpty else { return 0 }

        if let first = blockHosts.first, y <= first.rect.minY {
            return first.block.startOffset
        }

        for host in blockHosts {
            if y <= host.rect.maxY {
                let progress = host.rect.height > 0 ? (y - host.rect.minY) / host.rect.height : 0
                let offset = host.block.startOffset + Int(progress * CGFloat(host.block.length))
                return min(max(host.block.startOffset, offset), host.block.endOffset)
            }
        }

        return blockHosts.last?.block.endOffset ?? 0
    }

    private struct BlockHost {
        let block: MarkdownSyncBlock
        let host: NSHostingView<AnyView>
        var rect: NSRect
    }

    private struct BlockSignature: Equatable {
        let id: Int
        let markdown: String
        let startOffset: Int
        let endOffset: Int
        let baseFontSize: Double
        let wrapsCodeBlocks: Bool

        init(block: MarkdownSyncBlock, baseFontSize: Double, wrapsCodeBlocks: Bool) {
            id = block.id
            markdown = block.markdown
            startOffset = block.startOffset
            endOffset = block.endOffset
            self.baseFontSize = baseFontSize
            self.wrapsCodeBlocks = wrapsCodeBlocks
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
