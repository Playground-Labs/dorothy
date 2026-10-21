import SwiftUI
import Combine

/// Status-bar icon. Left-click → compact Dorothy in a drop-down panel; right/ctrl-click → small custom menu panel.
@MainActor
final class MenuBar: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: 26)
    private var panel: NSPanel?
    private var showingMenu = false
    private var monitors: [Any] = []
    private var closedAt = Date.distantPast
    private var micSub: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel("Dorothy")
        }
        micSub = model.$mic.sink { [weak self] mic in self?.drawIcon(recording: mic == .recording) }
        model.closeMenuBarPanel = { [weak self] in self?.close() }
    }

    /// Plain 13px square: yellow + black check, or pink + black dot while recording.
    private func drawIcon(recording: Bool) {
        item.button?.image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor(recording ? B.pink : B.yellow).setFill()
            NSRect(x: 1.5, y: 1.5, width: 13, height: 13).fill()
            NSColor(B.ink).set()
            if recording {
                NSBezierPath(ovalIn: NSRect(x: 5.4, y: 5.4, width: 5.2, height: 5.2)).fill()
            } else {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 4.5, y: 8.2))
                check.line(to: NSPoint(x: 7, y: 10.7))
                check.line(to: NSPoint(x: 11.5, y: 5))
                check.lineWidth = 2.4
                check.stroke()
            }
            return true
        }
    }

    @objc private func clicked() {
        let e = NSApp.currentEvent
        toggle(menu: e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true)
    }

    private func toggle(menu: Bool) {
        if panel != nil {
            let switching = showingMenu != menu
            close()
            if !switching { return }
        } else if Date().timeIntervalSince(closedAt) < 0.25 {
            return  // this click already closed the panel via resign-key
        }
        open(menu: menu)
    }

    private func open(menu: Bool) {
        guard let button = item.button, let bw = button.window else { return }
        let size = menu ? CGSize(width: 204, height: 122) : CGSize(width: 346, height: 566)
        let root = menu
            ? AnyView(MenuPanelView(open: { [weak self] in self?.model.showMainWindow() },
                                    settings: { [weak self] in self?.model.showMainWindow(settings: true) },
                                    quit: { NSApp.terminate(nil) }))
            : AnyView(DropDownView(onExpand: { [weak self] in self?.model.showMainWindow(full: true) }).environmentObject(model))

        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: root)

        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? anchor
        let x = min(max(menu ? anchor.minX : anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
        p.makeKeyAndOrderFront(nil)

        panel = p
        showingMenu = menu
        button.highlight(true)
        NotificationCenter.default.addObserver(self, selector: #selector(resigned), name: NSWindow.didResignKeyNotification, object: p)
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard e.keyCode == 53 else { return e }  // Esc
                let window = e.windowNumber
                let closed = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.panel?.windowNumber == window else { return false }
                    self.close()
                    return true
                }
                return closed ? nil : e
            } as Any,
        ]
    }

    @objc private func resigned() { close() }

    func close() {
        guard let p = panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: p)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel = nil
        closedAt = Date()
        p.orderOut(nil)
        item.button?.highlight(false)
    }
}

/// Borderless panels can't become key by default; the drop-down needs key for quick-add typing.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The compact layout, bound to the shared AppModel, in a 3px-bordered box with a hard 6px shadow.
struct DropDownView: View {
    @EnvironmentObject var m: AppModel
    let onExpand: () -> Void
    @Namespace private var ns
    @State private var shown = false

    var body: some View {
        CompactView(ns: ns, menuBar: true, onExpand: onExpand)
            .frame(width: 340, height: 560)
            .background(B.paper)
            .overlay(Rectangle().strokeBorder(B.ink, lineWidth: 3))
            .background(B.ink.offset(x: 6, y: 6))
            .foregroundColor(B.ink)
            .scaleEffect(shown || reduceMotion ? 1 : 0.95, anchor: .top)
            .opacity(shown ? 1 : 0)
            .frame(width: 346, height: 566, alignment: .topLeading)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.7)) { shown = true }
            }
    }
}

struct MenuPanelView: View {
    let open: () -> Void
    let settings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Open Dorothy", primary: true, action: open)
            B.ink.frame(height: 2)
            MenuRow(title: "Settings…", action: settings)
            B.ink.frame(height: 2)
            MenuRow(title: "Quit Dorothy", action: quit)
        }
        .frame(width: 194)
        .brutalBox(shadow: 4)
        .foregroundColor(B.ink)
        .frame(width: 204, height: 122, alignment: .topLeading)
    }

    private struct MenuRow: View {
        let title: String
        var primary = false
        let action: () -> Void
        @State private var hover = false
        var body: some View {
            Button(action: action) {
                Text(title).font(.body(14, primary ? .bold : .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9).padding(.horizontal, 12)
                    .foregroundColor(primary || hover ? B.onAccent : B.ink)
                    .background(primary || hover ? B.yellow : B.paper)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}
