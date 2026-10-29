import AppKit
import SwiftUI

@MainActor
final class ApplicationWindowController: ObservableObject {
    private let title: String
    private let size: NSSize
    private let minimumSize: NSSize
    private(set) var window: NSWindow?

    init(title: String, size: NSSize, minimumSize: NSSize) {
        self.title = title
        self.size = size
        self.minimumSize = minimumSize
    }

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        if window == nil {
            // 菜单栏应用按需持有窗口，避免依赖弹窗中的 Settings 场景路由或恢复出重复窗口。
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(size)
            window.minSize = minimumSize
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle<Content: View>(@ViewBuilder content: () -> Content) {
        // 点击菜单栏会让原窗口失去 key 状态；是否隐藏必须判断可见性，而不是焦点。
        if let window, window.isVisible, !window.isMiniaturized {
            window.orderOut(nil)
        } else {
            show(content: content)
        }
    }
}

@MainActor
final class PrivacyPolicyWindowController {
    static let shared = PrivacyPolicyWindowController()
    private(set) var window: NSWindow?
    private var includesClaude: Bool?

    func show(includesClaude: Bool) {
        let content = PrivacyPolicyView(includesClaude: includesClaude) { [weak self] in self?.close() }
        if window == nil {
            // MenuBarExtra 会在焦点变化时收起，其 sheet 的首次关闭可能被父容器收起截断。
            // 说明窗口独立持有且只由阅读按钮打开，不跟随菜单/浮窗的显示状态恢复。
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "DevMeter 隐私说明"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 580))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            self.window = window
        } else if self.includesClaude != includesClaude {
            // 同一窗口可从 Codex/Claude 或设置进入；来源范围变化时更新正文，不重复创建窗口。
            (window?.contentViewController as? NSHostingController<PrivacyPolicyView>)?.rootView = content
        }
        self.includesClaude = includesClaude
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}
