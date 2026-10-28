import AppKit
import Combine
import SwiftUI

struct FloatingUsageView: View {
    @ObservedObject var store: UsageStore
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !store.isEnabled {
                Label("额度展示已暂停", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else if !store.isProviderAuthorized {
                ProviderAuthorizationView(source: store.selectedProviderID) {
                    store.grantProviderAccess(store.selectedProviderID)
                }
            } else if let snapshot = store.snapshot {
                VStack(spacing: 10) {
                    ForEach(snapshot.limits) { limit in
                        FloatingUsageLimitRow(limit: limit)
                    }
                }

                if let creditBalance = snapshot.creditBalance {
                    LabeledContent("Credits", value: creditBalance)
                        .font(.caption)
                }

                status(snapshot: snapshot)
            } else if let lastError = store.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取 \(store.selectedProviderID.title) 用量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(store.floatingPanelOpacity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: store.symbolName)
                    .font(.title2)
                    .foregroundStyle(accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DevMeter")
                        .font(.headline)
                    if let remaining = store.snapshot?.mostConstrainedLimit?.remainingPercent {
                        Text("\(store.selectedProviderID.title) · 最低剩余 \(remaining)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .overlay { FloatingWindowDragArea().accessibilityHidden(true) }

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(!store.isEnabled || !store.isProviderAuthorized)
                .help("立即刷新")
            }

            Button {
                onHide()
            } label: {
                Image(systemName: "eye.slash")
            }
            .buttonStyle(.plain)
            .help("隐藏置顶浮窗")
        }
    }

    @ViewBuilder
    private func status(snapshot: UsageSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.fetchedAt, style: .relative)\(store.selectedProviderID.timestampAction)")
                .foregroundStyle(.secondary)

            if store.isSnapshotStale { Text("旧数据").foregroundStyle(.orange) }

            if let lastError = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("刷新失败，正在显示上次数据：\(lastError)")
            }
        }
        .font(.caption2)
    }

    private var accentColor: Color {
        guard let remaining = store.snapshot?.mostConstrainedLimit?.remainingPercent else {
            return .secondary
        }

        switch remaining {
        case 0..<10:
            return .red
        case 10..<40:
            return .orange
        default:
            return .green
        }
    }
}

private struct FloatingWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> FloatingPanelDragView {
        let view = FloatingPanelDragView()
        view.toolTip = "拖动标题区域移动浮窗"
        return view
    }

    func updateNSView(_ nsView: FloatingPanelDragView, context: Context) {}
}

final class FloatingPanelDragView: NSView {
    private struct DragStart {
        let windowNumber: Int
        let mouse: NSPoint
        let origin: NSPoint
    }
    private var dragStart: DragStart?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // 由此视图管理拖动，避免透明视图被当作窗口背景而绕过事件处理。
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = nil
        guard event.type == .leftMouseDown, let window, window.isMovable,
              window.attachedSheet == nil else { return }
        dragStart = DragStart(windowNumber: window.windowNumber,
                              mouse: window.convertPoint(toScreen: event.locationInWindow), origin: window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.type == .leftMouseDragged, let window, window.isMovable, window.attachedSheet == nil,
              let start = dragStart, start.windowNumber == window.windowNumber else {
            dragStart = nil
            return
        }
        // AppKit 将窗口内坐标转换为全局逻辑点，跨缩放比例不同的屏幕也不混用像素坐标。
        // 只处理标题视图收到的事件，不安装全局鼠标监听，也不影响右侧按钮和正文交互。
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                      y: start.origin.y + mouse.y - start.mouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        dragStart = nil
    }
}

private struct FloatingUsageLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(limit.remainingPercent)%")
                    .font(.body.weight(.semibold).monospacedDigit())
            }

            ProgressView(value: Double(limit.remainingPercent), total: 100)
                .tint(tint)

            if let resetsAt = limit.resetsAt {
                Text("\(resetsAt, style: .relative)重置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var tint: Color {
        switch limit.remainingPercent {
        case 0..<10:
            return .red
        case 10..<40:
            return .orange
        default:
            return .green
        }
    }
}

@MainActor
final class FloatingPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private let store: UsageStore
    private let frameAutosaveName: String?
    private(set) var panel: NSPanel?
    private var storeChangeCancellable: AnyCancellable?
    private var isStarted = false

    init(store: UsageStore, frameAutosaveName: String? = "DevMeter.FloatingPanel") {
        self.store = store
        self.frameAutosaveName = frameAutosaveName
        super.init()
        storeChangeCancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.resizePanelToFit()
            }
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        DispatchQueue.main.async { [weak self] in
            self?.showIfEnabled()
        }
    }

    func show() {
        store.showsFloatingPanel = true
        let panel = makePanelIfNeeded()
        resizePanelToFit()
        panel.orderFrontRegardless()
    }

    func hide() {
        store.showsFloatingPanel = false
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        // 以真实窗口为准，避免首次创建前的显示偏好或失焦状态被当作窗口可见性。
        isVisible ? hide() : show()
    }

    private func showIfEnabled() {
        if store.showsFloatingPanel {
            show()
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let rootView = FloatingUsageView(store: store) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        if let frameAutosaveName {
            // 浮窗没有 resizable 样式；不传 force 时 AppKit 会拒绝恢复该窗口的位置。
            if !panel.setFrameUsingName(frameAutosaveName, force: true) { positionNearTopTrailing(panel) }
            panel.setFrameAutosaveName(frameAutosaveName)
        } else {
            // 测试不读写用户的真实窗口位置。
            positionNearTopTrailing(panel)
        }

        self.panel = panel
        panel.delegate = self
        return panel
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, notification.object as? NSPanel === panel, let frameAutosaveName else { return }
        // 在移动通知中显式保存，确保无边框浮窗的拖动结果更新到位置记录。
        panel.saveFrame(usingName: frameAutosaveName)
    }

    private func resizePanelToFit() {
        guard let panel, let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        let targetSize = contentView.fittingSize
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        // 普通数据刷新不应重设相同窗口尺寸，以免干扰标题区域正在处理的拖动。
        guard abs(targetSize.width - contentView.frame.width) > 0.5
                || abs(targetSize.height - contentView.frame.height) > 0.5 else { return }

        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(targetSize)
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func positionNearTopTrailing(_ panel: NSPanel) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 20
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - margin,
            y: visibleFrame.maxY - panel.frame.height - margin
        )
        panel.setFrameOrigin(origin)
    }
}
