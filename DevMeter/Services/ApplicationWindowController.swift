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
