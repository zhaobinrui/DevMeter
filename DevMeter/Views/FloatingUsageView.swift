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
                    Text("正在读取 Codex 用量…")
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
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.symbolName)
                .font(.title2)
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("DevMeter")
                    .font(.headline)
                if let remaining = store.snapshot?.mostConstrainedLimit?.remainingPercent {
                    Text("最低剩余 \(remaining)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
                .disabled(!store.isEnabled)
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
            Text("\(snapshot.fetchedAt, style: .relative)更新")
                .foregroundStyle(.secondary)

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
final class FloatingPanelController: ObservableObject {
    private let store: UsageStore
    private let frameAutosaveName: String?
    private var panel: NSPanel?
    private var storeChangeCancellable: AnyCancellable?
    private var isStarted = false

    init(store: UsageStore, frameAutosaveName: String? = "DevMeter.FloatingPanel") {
        self.store = store
        self.frameAutosaveName = frameAutosaveName
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
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        if let frameAutosaveName {
            if !panel.setFrameUsingName(frameAutosaveName) { positionNearTopTrailing(panel) }
            panel.setFrameAutosaveName(frameAutosaveName)
        } else {
            // 测试不读写用户的真实窗口位置。
            positionNearTopTrailing(panel)
        }

        self.panel = panel
        return panel
    }

    private func resizePanelToFit() {
        guard let panel, let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        let targetSize = contentView.fittingSize
        guard targetSize.width > 0, targetSize.height > 0 else { return }

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
